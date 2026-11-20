# Implementation plan

This plan is the agreed scope for OmadaSql.PS. It is based on a read of
[OmadaSqlTroubleshooter](https://github.com/Fortigi/OmadaSqlTroubleshooter) (query execution,
rules, schema, history, export), [OmadaWeb.PS](https://github.com/Fortigi/OmadaWeb.PS)
(authentication, repository framework) and the requirements of unattended SQL-to-CSV exports.

Status legend: **Verified** = read in reference code; **Assumption** = to be confirmed against a
tenant or documentation before it is relied on.

## Decisions

| Topic | Decision |
|---|---|
| Platform | Windows only (OmadaWeb.PS is Windows-only), Windows PowerShell 5.1 and PowerShell 7. |
| Authentication | Everything through `Invoke-OmadaRestMethod` (OmadaWeb.PS). Unattended use sets `NoInteractiveAuthentication`, so an expired session fails instead of opening a browser. |
| SQL parser (ScriptDom) | **Bundled** in the package, pinned by version and SHA-256 in a dependency lock, with a Dependabot `nuget` entry. No runtime download. Pinned at 180.140.0 (`Build/DependencyLock.psd1`): the `net472` build for 5.1 (needs .NET Framework 4.7.2) and the `net8.0` build for PowerShell 7.4+ (**Verified**: the package ships `net472`, `net8.0`, `netstandard2.0` and `netstandard2.1`; there is no `net462` build). Loaded on first use, not at import. |
| Saved queries | Executed read-only: the saved object is never written, unlike the GUI, which saves before it executes. |
| Temporary query objects | A bounded slot pool `TMP_<InstanceGuid>_<n>` per user profile (`InstanceGuid` persisted in `%LOCALAPPDATA%\OmadaSql.PS\settings.json`), each slot leased with a named mutex, soft-deleted after use and restored (`UndeleteDataObject`) on reuse. `MaxTempQuerySlots` (default 4) caps the number of objects a profile can ever leave on the tenant. |
| Temporary object cleanup | `Get-OmadaSqlTempQuery` / `Clear-OmadaSqlTempQuery`: by default only this profile's slots, identified by the `InstanceGuid` in the object name (`-All` widens to every `TMP_` object), never a leased slot. Live objects are soft-deleted; with `-Purge` they are also purged with `PurgeDataObject` (irreversible: `ConfirmImpact = 'High'`, never the default). Filtering on the name instead of `tblDataObject.CreatedBy` keeps cleanup independent of SQL Troubleshooting and of resolving the signed-in user's object ID; it also means another profile of the same user is only covered by `-All`. See "Deleted objects" below. |
| Object overview | `Get-OmadaSqlQuery -Detailed`: all OData properties, the resolved data connection, the owner (created by / changed by) and the history in one object. |
| Validation | On by default, `-SkipValidation` to skip. A blocking diagnostic is a terminating error, never a prompt. Severity per rule can be overridden. |
| Schema | `Get-OmadaSqlSchema` reads `GetSqlSchema` per data connection (body `{ connectionId }`, the id as a string; the answer maps `schema.table` to `"Column Type"` entries, views included) and caches it on the connection for the session; `-Force` reads it again, `Disconnect-OmadaSql` drops it. |
| Schema rules | OMD030 (table not in the schema), OMD031 (column not in the schema), OMD032 (ambiguous column), all **Info**, so they never block: the schema is a cached copy. They run only in `Test-OmadaSqlQuery -DataConnection`, against each statement's own data connection; `Invoke-OmadaSqlQuery` does not read the schema, so a run costs no extra request. A query scope with a derived table, function, CTE, temporary table or unresolved table among its own sources is not checked for columns (no guessing). The checks follow OmadaSqlTroubleshooter's schema pass, which has no rule ids; the ids are this module's. |
| Export | `Export-OmadaSqlResult` with a format registry (`Get-OmadaSqlExportFormat`, `Register-OmadaSqlExportFormat`; built-in formats cannot be replaced). Built in: Csv, Json, Xml, Text, SqlArray, PowerShellArray. Without `-Format` the format follows the `-Path` extension, as the Troubleshooter's Save As does. Output is culture-independent (invariant numbers, ISO 8601 dates) and UTF-8, by default without a byte order mark (`-Encoding UTF8BOM` for Excel); an existing file is only replaced with `-Force`. |
| Export, deviations from OmadaSqlTroubleshooter | CSV uses a semicolon by default, as the Troubleshooter does (`-Option @{ Delimiter = ',' }` for a comma); a null value is an empty unquoted field. Xml is a plain `<Result><Row><Field Name>` document instead of `Export-Clixml`, so any XML tool can read it. Json is the array of rows, not the whole `{ d: ... }` response. SqlArray and PowerShellArray type each column from its values (a column of canonical numbers is unquoted, `007` stays text), not from the schema. |
| Live tenant tests | None for now (no test tenant). Integration tests use a local `HttpListener` mock of the Omada endpoints. |
| Generic bulk undelete / purge of other object types | **Parked.** Out of scope for this module for now; a separate module later can share the request and OData listing helpers. Only `TMP_` cleanup is built here. |
| Quality gates | Required for every pull request: PSComplexity (15 cyclomatic / 15 cognitive per function, empty baseline) and PSMutant (75% over the changed files and 75% for each file, an owning unit test file for every changed source file, uncovered lines mutated too). |
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
| Purge (hard delete) | `POST {BaseUrl}/WebService/DataObjectWebService.asmx/PurgeDataObject` body `{"id": <DoId>}` (observed in the Omada web UI; not yet exercised by any reference code) |
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
OMD001, OMD003, OMD004, OMD010-OMD013, plus this module's OMD020 (four-part name) and OMD021 (two
databases in one statement), schema warnings (never blocking, phase 5). Database names: a
`[DataConnectionName].schema.table` prefix or `USE` resolves to a data connection by name and is
removed from the SQL; four-part names and cross-database statements are rejected; multi-statement
scripts run statement by statement.

Bugs in the references that are not carried over: an unescaped `'` in `$filter` name lookups;
`Get-SqlHistory` validating the data connection instead of the query object; the extracted ScriptDom
DLL not being hash-pinned.

## Phases

Each phase is one pull request, test first.

0. **Repository framework** - build, tests, workflows, ruleset as code, issue templates, docs. *(done)*
1. **Core** - connection object, request core, error classification (session expired, 401, missing
   OData permission, endpoint not enabled), redaction, Verbose/Debug logging. Add the README command
   generator with the first public commands. *(done)*
2. **Objects** - data connections, CRUD and restore, history, detailed overview. *(done)*
   Temporary-object listing and cleanup moved to phase 4, together with the slot pool.
3. **ScriptDom** *(done)* - bundling (dependency lock, Dependabot `nuget`), statement splitting,
   database-name resolution, rules and syntax checker.
4. **Execution** *(done)* - saved and ad-hoc queries, slot pool with mutex, multi-statement, result objects,
   `Get-OmadaSqlTempQuery` and `Clear-OmadaSqlTempQuery`.
5. **Schema and export** *(in progress)* - schema model and cache, schema rules, export format registry.
6. **Integration and release** - `HttpListener` mock of the Omada endpoints, README, first nightly.

## Deleted objects

Based on the behaviour of the Omada web UI and its OData API. A rule marked (verify) is not
relied on until a test confirms it.

| Topic | Rule |
|---|---|
| Listing | OData `deletedStatus=Deleted` (custom query parameter, values `Deleted`, `NotDeleted`, `Both`, **case-sensitive**; an invalid value silently falls back to `NotDeleted`). Every listing validates that each returned object has `Deleted = true` and throws otherwise. Paging with `$top`/`$skip` until all pages are read (`ODataPageSizeLimit`). |
| Creator | `CreatedBy`/`DeletedBy` are not in OData. Read from `tblDataObject` (database `OISES`) through SQL Troubleshooting: the module runs its own read-only query for this. |
| Undelete | `UndeleteDataObject` `{"id": <int>}`, one object per call; System Administrators or Data Administrators only. Clears `DeletedBy`/`DeleteTime`, so those are captured first. |
| Purge | `PurgeDataObject` `{"id": <int>}`, one object per call; only for delete-marked objects; System, Operation or Data Administrator auth role; also purges child objects and process instances that target the object. |
| Delete (bulk, test setup) | `DeleteDataObjects` `{"ids": [<int>, ...]}` |
| Permissions | A user without those roles can run the slot pool (soft delete and undelete of its own `TMP_` object is what OmadaSqlTroubleshooter does today) but not purge. A refused purge is reported with the required role, not as a generic 401. (verify which roles the undelete of a `C_P_SQLTROUBLESHOOTING` object really needs) |
| SQL errors | Any SQL error in SQL Troubleshooting returns a generic HTTP 500 (`The query pipeline failed at step 'ExecuteQuery'`); `DECLARE`, temp tables, dynamic SQL and `USE` are not available. |

Inconsistency to resolve: one source gives the OData type segment as the system name with only the
first letter upper case (`Identity`, `Resource`), while OmadaSqlTroubleshooter successfully uses
`C_P_SQLTROUBLESHOOTING`. Both are kept as observed; the module uses the segment the GUI uses.

## Open items (to verify, not assume)

| Item | How to settle it |
|---|---|
| Whether a non-admin account can list deleted objects via OData (`deletedStatus=Deleted`) | Tenant test |
| Whether Omada's OData list of C_P_SQLTROUBLESHOOTING pages with @odata.nextLink (what OmadaWeb.PS -Paged follows) or only with $skip | Tenant test with more objects than ODataPageSizeLimit |
| Which properties the C_P_SQLTROUBLESHOOTING OData object exposes (EXPLICITOWNER, the shape of the data connection reference) | Inspect one object on a tenant; the module tolerates both reference shapes and a missing owner |
| Whether SQL Troubleshooting history rows carry a 'Create' change type, used for CreatedBy in -Detailed | Inspect a history on a tenant; without it the oldest entry is used |
| Whether `SqlDataProducer` honours `page` > 1 for results over 100 000 rows | Tenant test; until then an explicit error above the limit |
| The response Omada returns for a failing SQL statement | Expected: generic HTTP 500, `The query pipeline failed at step 'ExecuteQuery'`. Confirm the body shape with a tenant test |
| An SBOM for the bundled parser | Moved to phase 6 (release): generated with the release package |
| Whether SQL Troubleshooting rejects `DECLARE` (named as unavailable, not yet confirmed) | Tenant test before a rule is added for it |

## One-time repository settings (maintainer)

- Apply the ruleset: `./Build/Set-RepositoryRuleset.ps1`.
- Create the `release` environment with required reviewers.
- Add the `PSGALLERY_API_KEY` secret.
- Enable private vulnerability reporting, secret scanning and push protection.
