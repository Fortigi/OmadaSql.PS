# Implementation plan

This plan is the agreed scope for OmadaSql.PS. It is based on a read of
[OmadaSqlTroubleshooter](https://github.com/Fortigi/OmadaSqlTroubleshooter) (query execution,
rules, schema, history, export), [OmadaWeb.PS](https://github.com/Fortigi/OmadaWeb.PS)
(authentication, repository framework) and an existing unattended SQL-to-CSV export script.

Status legend: **Verified** = read in reference code; **Assumption** = to be confirmed against a
tenant or documentation before it is relied on.

## Decisions

| Topic | Decision |
|---|---|
| Platform | Windows only (OmadaWeb.PS is Windows-only), Windows PowerShell 5.1 and PowerShell 7. |
| Authentication | Everything through `Invoke-OmadaRestMethod` (OmadaWeb.PS). Unattended use sets `NoInteractiveAuthentication`, so an expired session fails instead of opening a browser. |
| SQL parser (ScriptDom) | **Bundled** in the package, pinned by version and SHA-256 in a dependency lock, with a Dependabot `nuget` entry. No runtime download. Requires the `net462` build for 5.1 and the `net8.0` build for 7 (**Assumption**: both are in the 180.x package). |
| Saved queries | Executed read-only: the saved object is never written, unlike the GUI, which saves before it executes. |
| Temporary query objects | A bounded slot pool `TMP_<InstanceGuid>_<n>` per user profile (`InstanceGuid` persisted in `%LOCALAPPDATA%\OmadaSql.PS\settings.json`), each slot leased with a named mutex, soft-deleted after use and restored (`UndeleteDataObject`) on reuse. `MaxTempQuerySlots` (default 4) caps the number of objects a profile can ever leave on the tenant. |
| Temporary object cleanup | `Clear-OmadaSqlTempQuery`: finds `TMP_*` objects (`DeletedStatus=Both`), by default only those created by the signed-in identity (`-AllUsers` widens), never a leased slot, `-WhatIf`/`-Confirm`. Purging already soft-deleted objects only if Omada exposes a purge API (**Assumption**, see open items). |
| Object overview | `Get-OmadaSqlQuery -Detailed`: all OData properties, the resolved data connection, the owner (created by / changed by) and the history in one object. |
| Validation | On by default, `-SkipValidation` to skip. A blocking diagnostic is a terminating error, never a prompt. Severity per rule can be overridden. |
| Live tenant tests | None for now (no test tenant). Integration tests use a local `HttpListener` mock of the Omada endpoints. |
| Commit attribution | As in OmadaWeb.PS: no AI-attribution trailers in commits or pull request descriptions. |

## Request shapes (Verified in OmadaSqlTroubleshooter `New-OmadaQueryRequest`)

| Purpose | Request |
|---|---|
| Entity | `{BaseUrl}/odata/dataobjects/C_P_SQLTROUBLESHOOTING` |
| Probe temporary object | `GET …?DeletedStatus=Both&$filter=NAME eq '<name>'` |
| Restore soft-deleted object | `POST {BaseUrl}/WebService/DataObjectWebService.asmx/UndeleteDataObject` body `{"id": <DoId>}` (pre-serialized) |
| Create / update | `POST` entity / `PUT …(<DoId>)` with `NAME`, `C_QUERY`, `C_SQLTROUBLESHOOTING_DATACONNECTION = @{ Id = <DoId> }` |
| Execute | `POST {BaseUrl}/webservice/jQGridPopulationWebService.asmx/GetPagingData`, `dataType = SqlDataProducer`, `dataTypeArgs.targetId = <DoId>`, `rows = 100000` |
| Delete (soft) | `DELETE …(<DoId>)` |
| Data connections | `GetPagingData` `Views` search "SQL Troubleshooting", then `DataObjects` of that view, then `GET dataobjdlg.aspx?DOID=<c-13>` and parse the `<option>` list |
| Schema | `POST {BaseUrl}/webservice/SyntaxHighlighting.asmx/GetSqlSchema` body `{ connectionId }` |
| History | `GetPagingData` `dataType = DataObjectHistory`, `dataTypeArgs = { dataObjectId, propertyId = 0, userId = 0 }`, `sidx = when`, `sord = desc` |

## Commands

| Area | Commands |
|---|---|
| Connection | `Connect-OmadaSql`, `Disconnect-OmadaSql`, `Get-OmadaSqlConnection` |
| Data connections | `Get-OmadaSqlDataConnection` |
| Execution | `Invoke-OmadaSqlQuery` (`-Id`/`-Name`/pipeline for saved, `-Query`/`-Path` for ad-hoc, `-DataConnection`, `-SkipValidation`, `-RuleSeverity`, `-AsStatementResult`) |
| Validation | `Test-OmadaSqlQuery` |
| Schema | `Get-OmadaSqlSchema` (in-session cache, `-Force`) |
| CRUD | `Get-OmadaSqlQuery`, `New-OmadaSqlQuery`, `Set-OmadaSqlQuery`, `Remove-OmadaSqlQuery`, `Restore-OmadaSqlQuery` |
| History / overview | `Get-OmadaSqlQueryHistory` (all changed fields, `-Field`), `Get-OmadaSqlQuery -Detailed` |
| Temporary objects | `Get-OmadaSqlTempQuery`, `Clear-OmadaSqlTempQuery` |
| Export | `Export-OmadaSqlResult -Format Csv\|Json\|Xml\|Text\|SqlArray\|PowerShellArray`, `Register-OmadaSqlExportFormat`, `Get-OmadaSqlExportFormat` |

Query rules carried over from OmadaSqlTroubleshooter: T-SQL syntax (ScriptDom), Omada compatibility
OMD001, OMD003, OMD004, OMD010-OMD013, schema warnings (never blocking). Database names: a
`[DataConnectionName].schema.table` prefix or `USE` resolves to a data connection by name and is
removed from the SQL; four-part names and cross-database statements are rejected; multi-statement
scripts run statement by statement.

Bugs in the references that are not carried over: an unescaped `'` in `$filter` name lookups;
`Get-SqlHistory` validating the data connection instead of the query object; the extracted ScriptDom
DLL not being hash-pinned.

## Phases

Each phase is one pull request, test first.

0. **Repository framework** - build, tests, workflows, ruleset as code, issue templates, docs. *(this PR)*
1. **Core** - connection object, request core, error classification (session expired, 401, missing
   OData permission, endpoint not enabled), redaction, Verbose/Debug logging. Add the README command
   generator with the first public commands.
2. **Objects** - data connections, CRUD, history, overview, temporary-object listing and cleanup.
3. **ScriptDom** - bundling (dependency lock, Dependabot `nuget`, SBOM), statement splitting,
   database-name resolution, rules and syntax checker.
4. **Execution** - saved and ad-hoc queries, slot pool with mutex, multi-statement, result objects.
5. **Schema and export** - schema model and cache, export format registry.
6. **Integration and release** - `HttpListener` mock of the Omada endpoints, README, first nightly.

## Open items (to verify, not assume)

| Item | How to settle it |
|---|---|
| Whether Omada can purge (hard-delete) soft-deleted data objects through an API | Omada documentation or a tenant test before `Clear-OmadaSqlTempQuery -Purge` is built |
| Which OData property identifies the creator of an object (for "only my objects") | Inspect a `C_P_SQLTROUBLESHOOTING` object on a tenant; fall back to the view columns the GUI uses |
| Whether `SqlDataProducer` honours `page` > 1 for results over 100 000 rows | Tenant test; until then an explicit error above the limit |
| The response Omada returns for a failing SQL statement | Tenant test; drives error classification |
| ScriptDom 180.x containing a `net462` build for Windows PowerShell 5.1 | Inspect the package in Phase 3 |

## One-time repository settings (maintainer)

- Apply the ruleset: `./Build/Set-RepositoryRuleset.ps1`.
- Create the `release` environment with required reviewers.
- Add the `PSGALLERY_API_KEY` secret.
- Enable private vulnerability reporting, secret scanning and push protection.
