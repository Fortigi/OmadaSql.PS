# Tenant test checklist

The module is covered by unit tests and by integration tests against a local mock of the Omada
endpoints. What the mock cannot show is how a real tenant answers. This checklist settles that: the
open items in [PLAN.md](PLAN.md#open-items-to-verify-not-assume), and the assumptions the module
makes about request and response shapes.

Run it against a **test or acceptance tenant**, never production: several steps create, delete and
purge objects. Record the outcome of every step (pass, fail, or what was observed), and copy the
**shape** of a response where a step asks for it, with values that identify the tenant or a person
replaced. Update `docs/PLAN.md` and open an issue for every deviation.

## Preparation

| # | Step | Expected |
|---|---|---|
| P1 | Two accounts on the test tenant: an **administrator** (System, Operation or Data Administrator) and a **regular user** with Read, Create, Update and Delete on the `OData` auth element for SQL Troubleshooting, and no administrator role. | Both can open SQL Troubleshooting in the web UI. |
| P2 | Install the module from a local build or the first nightly: `./Build/build.ps1 -Task Build; ./deploy.ps1 -Scope CurrentUser`. | `Get-Module OmadaSql.PS -ListAvailable` shows the version. |
| P3 | Note the name of at least one data connection (for example `OISES`) and of a second one if the tenant has it. | - |
| P4 | Use a fresh settings file for the test, so the slot pool starts empty: rename `%LOCALAPPDATA%\OmadaSql.PS\settings.json` if it exists. | - |
| P5 | Run every step with `-Verbose` when the outcome is unexpected: it shows each request (method, URI, outcome), never bodies. | - |

All objects this checklist creates are named `OSQLTEST <step>` so they are easy to find and remove.

## 1. Connection and data connections

| # | Step | Expected | Settles |
|---|---|---|---|
| 1.1 | `Connect-OmadaSql -Url 'https://<tenant>.omada.cloud'` (interactive), then `Get-OmadaSqlConnection`. | Connects; the connection test (`odata/dataobjects/C_P_SQLTROUBLESHOOTING?$top=1`) passes. | Endpoint and auth |
| 1.2 | Connect unattended: `-AuthenticationType OAuth -NoInteractiveAuthentication -ClientId ... -OAuthCertificateThumbprint ... -EntraIdTenantId ...`. | Connects without a browser. | Unattended sign-in |
| 1.3 | On a tenant without the SQL Troubleshooting OData endpoint enabled (if one is available), connect. | `OmadaSql.EndpointNotEnabled`. | Error classification |
| 1.4 | `Get-OmadaSqlDataConnection` | The same list of data connections as the dropdown in the SQL Troubleshooting form, with ids. | View lookup and the `dataobjdlg.aspx` option list |

## 2. Object management

| # | Step | Expected | Settles |
|---|---|---|---|
| 2.1 | `New-OmadaSqlQuery -Name 'OSQLTEST 2.1' -Query 'SELECT [Id] = Id FROM dbo.tblDataObject WHERE 1 = 0' -DataConnection '<dc>'` | The object is created and shows in the web UI with the right data connection. | Create body |
| 2.2 | `Get-OmadaSqlQuery -Name 'OSQLTEST 2.1' -Detailed` | Owner, data connection and history are filled. **Copy the shape** of one raw OData object (`-Verbose` URI, then the same GET in a browser): which properties exist, `EXPLICITOWNER`, and the shape of `C_SQLTROUBLESHOOTING_DATACONNECTION`. | Open item: object properties and reference shape |
| 2.3 | `Set-OmadaSqlQuery -Name 'OSQLTEST 2.1' -Query 'SELECT [Id] = Id, [Name] = DisplayName FROM dbo.tblDataObject WHERE 1 = 0'`, then `Get-OmadaSqlQueryHistory -Name 'OSQLTEST 2.1'`. | The change is saved; the history shows it. Check whether the first history row has a **'Create'** change type. | Open item: 'Create' in history |
| 2.4 | `Remove-OmadaSqlQuery -Name 'OSQLTEST 2.1'`, then `Restore-OmadaSqlQuery` it, **as the regular user**. | Note whether the regular user may undelete. | (verify) undelete permission |
| 2.5 | As the regular user, `Get-OmadaSqlQuery -Name 'OSQLTEST*'` with a deleted object present (deleted listing). | Note whether deleted objects are listed for a non-administrator. | Open item: deleted listing for non-admins |
| 2.6 | On a tenant with more SQL Troubleshooting objects than its `ODataPageSizeLimit`, `@(Get-OmadaSqlQuery).Count`. | Equals the count in the web UI. If it stops at the page size, note whether the response had `@odata.nextLink`. | Open item: OData paging |

## 3. Query execution

| # | Step | Expected | Settles |
|---|---|---|---|
| 3.1 | `Invoke-OmadaSqlQuery -Query 'SELECT TOP 5 [Id] = Id, [Name] = DisplayName FROM dbo.tblDataObject' -DataConnection '<dc>'` | Five rows. Then `Get-OmadaSqlTempQuery`: one soft-deleted `TMP_<profile id>_1` object. | Temporary object flow |
| 3.2 | Repeat 3.1. | The same `TMP_..._1` object is restored and reused; no `_2`. | Slot reuse (undelete, update) |
| 3.3 | **Copy the shape** of one row: `(Invoke-OmadaSqlQuery -Query 'SELECT TOP 1 [Id] = Id, [Created] = CreateTime, [Deleted] = Deleted FROM dbo.tblDataObject' -DataConnection '<dc>') \| Format-List *` and `\| ForEach-Object { $_.PSObject.Properties \| Select-Object Name, TypeNameOfValue }`. | Note whether every value is a string, and how a date and a bit arrive. | Value types (export typing, schema hints) |
| 3.4 | Two runs at the same time: in two PowerShell windows, start a slow query (`SELECT [n] = COUNT(*) FROM dbo.tblDataObject AS a CROSS JOIN dbo.tblDataObject AS b`, or another that takes several seconds) at once. | Each uses its own slot (`_1` and `_2`); neither fails. | Mutex slot pool |
| 3.5 | Run a failing statement: `Invoke-OmadaSqlQuery -Query 'SELECT [x] = NoSuchColumn FROM dbo.tblDataObject' -DataConnection '<dc>' -SkipValidation`. | A non-terminating `OmadaSql.ServerError`; the temporary object is soft-deleted afterwards. **Copy the error message and body shape.** | Open item: response for a failing statement |
| 3.6 | `Invoke-OmadaSqlQuery -Query 'DECLARE @x int = 1; SELECT [x] = @x' -DataConnection '<dc>' -SkipValidation` | Note whether it runs or fails, and how. | Open item: `DECLARE` |
| 3.7 | A query with an unnamed column, with `-SkipValidation`: `SELECT COUNT(*) FROM dbo.tblDataObject`. | Returns no rows, as OMD001 says. | OMD001 |
| 3.8 | A query whose alias has a space: `SELECT TOP 1 [Display Name] = DisplayName FROM dbo.tblDataObject`. | The column arrives as `Display_Name`, as OMD003 says. | OMD003 |
| 3.9 | Text outside ASCII: `SELECT [Text] = N'Zoë € 测试'`. | The text comes back unchanged, on Windows PowerShell 5.1 and PowerShell 7. | Body encoding |
| 3.10 | A script with two data connections: `SELECT [a] = COUNT(*) FROM [<dc1>].dbo.tblDataObject; SELECT [b] = 1 FROM [<dc2>].<schema>.<table>` with `-AsStatementResult`. | Two results, each from its own data connection. | Database-name resolution |
| 3.11 | A saved object: create `OSQLTEST 3.11` in the web UI, then `Invoke-OmadaSqlQuery -Name 'OSQLTEST 3.11'`. | Rows; the object's change history shows **no** new change. | Saved objects are read-only |
| 3.12 | A result of more than 100 000 rows (only if the tenant has that much data). | `OmadaSql.InvalidResult` with the row count, not a truncated result. Note the `Records` value Omada reports. | Open item: paging above 100 000 rows |

## 4. Validation and schema

| # | Step | Expected | Settles |
|---|---|---|---|
| 4.1 | `Get-OmadaSqlSchema -DataConnection '<dc>' \| Measure-Object`, and time it with `Measure-Command`. | The tables and views of the data connection; note the count and the time. | `GetSqlSchema` request and answer shape |
| 4.2 | Repeat 4.1. | Answers at once from the cache; `-Force` reads it again. | Schema cache |
| 4.3 | **Copy the shape** of the answer for one table: `(Get-OmadaSqlSchema -DataConnection '<dc>' -Name 'dbo.tblDataObject').Column`. | Column names and types as SQL Server Management Studio shows them. Note any entry the module did not split as expected (a type with spaces, a column without a type). | Column entry format |
| 4.4 | The largest data connection the tenant has: 4.1 against it. | Completes; note the time and the number of tables. | Large schemas |
| 4.5 | `Test-OmadaSqlQuery -Query 'SELECT [n] = o.DisplayNam FROM dbo.tblDataObject AS o JOIN dbo.NoSuchTable AS t ON 1 = 1' -DataConnection '<dc>'` and the same without the join. | OMD030 for the unknown table; without the join, OMD031 for the column. | Schema rules |
| 4.6 | `Test-OmadaSqlQuery -Path` on three or four real queries the team uses. | No false schema findings. Note every finding that is wrong. | Schema-rule noise |

## 5. Export

| # | Step | Expected | Settles |
|---|---|---|---|
| 5.1 | `Invoke-OmadaSqlQuery ... \| Export-OmadaSqlResult -Path .\osqltest.csv -Encoding UTF8BOM -Force`, open in Excel with Dutch regional settings. | Opens in columns (semicolon) with characters outside ASCII intact. | CSV defaults |
| 5.2 | The same with `-Format Json`, `Xml` and `Text`. | Readable; dates in ISO 8601. | Other formats |
| 5.3 | An id column as `-Format SqlArray`, pasted into `WHERE Id IN ...` in SQL Troubleshooting. | Runs. | SqlArray literals |

## 6. Cleanup and purge

| # | Step | Expected | Settles |
|---|---|---|---|
| 6.1 | As the regular user, `Clear-OmadaSqlTempQuery -Purge`. | Soft delete works; the purge is refused with a message that names the System, Operation or Data Administrator role. | Purge permission message |
| 6.2 | As the administrator, `Clear-OmadaSqlTempQuery -Purge`, then `Get-OmadaSqlTempQuery`. | This profile's temporary objects are gone, also from the deleted list. | `PurgeDataObject` |
| 6.3 | Remove the `OSQLTEST` objects: `Get-OmadaSqlQuery -Name 'OSQLTEST*' \| Remove-OmadaSqlQuery`, then purge them in the web UI if wanted. | No test objects left. | - |
| 6.4 | Restore the settings file renamed in P4. | - | - |

## 7. Unattended run

| # | Step | Expected | Settles |
|---|---|---|---|
| 7.1 | The scheduled-task example from the README as a Windows scheduled task under a service account. | The file is written; the task exits with 0. | Unattended use |
| 7.2 | The same with an invalid certificate thumbprint. | The task fails with a clear error and exits non-zero, without waiting for a browser. | `-NoInteractiveAuthentication` |
