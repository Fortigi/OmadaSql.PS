# Tenant test checklist

The module is covered by unit tests and by integration tests against a local mock of the Omada
endpoints. What the mock cannot show is how a real tenant answers. This checklist settles that: the
open items in [PLAN.md](PLAN.md#open-items-to-verify-not-assume), and the assumptions the module
makes about request and response shapes.

Run it against a **test or acceptance tenant**, never production: it creates, deletes and purges
objects. Every query it runs is general: constants, `VALUES` lists and the schema of the data
connection you give it. It reads no Omada table by name and no business data, so it runs on any
tenant and any data connection.

Most steps are automated in `Tests/Tenant` (column **How**: *auto*). The rest need a person or a
second tenant (*manual*). Update `docs/PLAN.md` and open an issue for every deviation.

## Running the automated steps

Prerequisites:

- Pester 5.5 or later: `Install-Module Pester -MinimumVersion 5.5.0 -Scope CurrentUser`.
- The module installed from a local build or the first nightly: `./Build/build.ps1 -Task Build`,
  then `./deploy.ps1 -Scope CurrentUser`.
- Two accounts on the test tenant:
  - a **regular user** with Read, Create, Update and Delete on the `OData` auth element for SQL
    Troubleshooting and no administrator role;
  - an **administrator** (System, Operation or Data Administrator).
- The name of a data connection, and of a second one if the tenant has it.

Run the test twice on the same Windows profile, regular user first:

```powershell
Import-Module OmadaSql.PS
Connect-OmadaSql -Url 'https://<test tenant>.omada.cloud'          # sign in as the regular user
./Tests/Tenant/Invoke-OmadaSqlTenantTest.ps1 -Role User -DataConnection '<dc>' -SecondDataConnection '<dc2>'
Disconnect-OmadaSql

Connect-OmadaSql -Url 'https://<test tenant>.omada.cloud'          # sign in as the administrator
./Tests/Tenant/Invoke-OmadaSqlTenantTest.ps1 -Role Administrator -DataConnection '<dc>' -SecondDataConnection '<dc2>' -IncludeLargeResult
```

Run both passes on Windows PowerShell 5.1 and on PowerShell 7.

Optional parameters:

- `-QueryPath <folder>`: checks the team's own `.sql` files against the schema rules (step 4.6).
- `-IncludeLargeResult`: adds the result of 161 051 rows (step 3.12).

Each run writes a folder `TenantTestResult-<role>-<timestamp>` with:

- `results.xml`: NUnit, one test per step, named by its number.
- `observations.json`: what the tenant did where the module only assumes it. It holds shapes
  (property names and .NET types) and outcomes, not values. Error messages are kept, so **read it
  before you share it**.

A step marked *observes* passes whatever the tenant does. Its outcome is in `observations.json`, and
the checklist says what to look for.

The objects the test creates are named `OSQLTEST <run id> <step>` and are removed at the end. The
administrator pass purges the temporary query objects both passes used.

## 1. Connection and data connections

| # | How | Step | Expected |
|---|---|---|---|
| 1.1 | manual | `Connect-OmadaSql -Url ...` interactively, then `Get-OmadaSqlConnection`. | Connects; the connection test (`C_P_SQLTROUBLESHOOTING?$top=1`) passes. |
| 1.2 | manual | Connect unattended: `-AuthenticationType OAuth -NoInteractiveAuthentication -ClientId ... -OAuthCertificateThumbprint ... -EntraIdTenantId ...`. | Connects without a browser. |
| 1.3 | manual | On a tenant without the SQL Troubleshooting OData endpoint (if one is available), connect. | `OmadaSql.EndpointNotEnabled`. |
| 1.4 | auto | Lists the data connections and finds the one given. | The list matches the dropdown of the SQL Troubleshooting form (compare the count in observations). |

## 2. Object management

| # | How | Step | Expected |
|---|---|---|---|
| 2.1 | auto | Creates an object with the data connection given. | Created with that data connection and query. |
| 2.2 | auto | Reads the object with `-Detailed`; *observes* the raw OData shape. | History present. In observations: the properties the object has, `HasExplicitOwner`, and the shape of `C_SQLTROUBLESHOOTING_DATACONNECTION`. |
| 2.3 | auto | Changes the query and reads the history; *observes* the change types. | The change is in the history. In observations: whether `OldestChangeType` is a 'Create'. |
| 2.4 | auto | Deletes the object and restores it; *observes* whether this role may restore. | Delete works. In observations: `Restored` per role (the open undelete-permission question). |
| 2.5 | auto | Lists a deleted object; *observes* whether this role sees it. | In observations: `DeletedListed` per role. |
| 2.6 | auto | Counts all objects; *observes* the counts. | Compare `IncludingDeleted` with the web UI. A count equal to the tenant's `ODataPageSizeLimit` points to a paging problem. |

## 3. Query execution

| # | How | Step | Expected |
|---|---|---|---|
| 3.1 | auto | Runs ad-hoc SQL. | Three rows, through `TMP_<profile id>_1`, which is soft-deleted afterwards. |
| 3.2 | auto | Runs it again. | The same object is restored and reused. |
| 3.3 | auto | Runs a row of int, bigint, decimal, float, bit, date, datetime2, uniqueidentifier, text and NULL; *observes* the types. | In observations: whether every value arrives as text, and how bit, decimal and dates are written. |
| 3.4 | auto | Holds slot 1 from another thread and runs a query. | The run takes slot 2. |
| 3.5 | auto | Runs `SELECT [x] = 1 / 0`. | One non-terminating error; the temporary object is soft-deleted. In observations: the message (the open question on the failure response). |
| 3.6 | auto | Sends a `DECLARE` on its own; *observes* the outcome. | In observations: whether it ran or how it failed. |
| 3.7 | auto | A result with an unnamed column. | No rows (OMD001). |
| 3.8 | auto | An alias with a space. | The column arrives as `Display_Name` (OMD003). |
| 3.9 | auto | Text with characters outside ASCII and Latin-1. | Unchanged. |
| 3.10 | auto | A script whose two statements name two data connections (needs `-SecondDataConnection`). | Both run, each against its own data connection. |
| 3.11 | auto | Runs a saved object. | Three rows; its history is unchanged. |
| 3.12 | auto | 161 051 rows (needs `-IncludeLargeResult`). | `OmadaSql.InvalidResult`, or all rows; never a truncated result. In observations: which one. |

## 4. Validation and schema

| # | How | Step | Expected |
|---|---|---|---|
| 4.1 | auto | Reads the schema with `-Force`, then from the cache. | Tables found; the cached read is faster. In observations: counts and times. |
| 4.3 | auto | *Observes* column entries the module could not split. | No column without a name. In observations: `WithoutType` and `TypesWithSpaces` should be empty or explainable. |
| 4.4 | auto | Reads the schema of the second data connection (needs `-SecondDataConnection`). | Tables found. In observations: size and time. |
| 4.5 | auto | Checks an unknown table, an unknown column and a known column of a table from the schema. | OMD030, OMD031, and no finding. |
| 4.6 | auto | Checks the team's queries (needs `-QueryPath`); *observes* the findings. | Review every OMD030 to OMD032 finding in observations: each wrong one is a false positive. |

## 5. Export

| # | How | Step | Expected |
|---|---|---|---|
| 5.1 | auto | CSV with `-Encoding UTF8BOM`. | Byte order mark, header `"Id";"Name"`. |
| 5.2 | auto | JSON, XML and Text. | Each reads back. |
| 5.3 | auto | An `SqlArray` of ids used in an `IN` list. | The query runs and counts 3. |
| 5.4 | manual | Open the CSV of 5.1 in Excel with Dutch regional settings. | Columns split on the semicolon; characters outside ASCII intact. |

## 6. Cleanup and purge

| # | How | Step | Expected |
|---|---|---|---|
| 6.1 | auto | `Clear-OmadaSqlTempQuery -Purge` as the regular user (User pass). | Refused with a message that names the administrator roles. |
| 6.2 | auto | The same as the administrator (Administrator pass). | No temporary objects of this profile are left. |
| 6.3 | manual | Purge the soft-deleted `OSQLTEST` objects in the web UI, if wanted. | No test objects left. |

## 7. Unattended run

| # | How | Step | Expected |
|---|---|---|---|
| 7.1 | manual | The scheduled-task example from the README, as a Windows scheduled task under a service account. | The file is written; the task exits with 0. |
| 7.2 | manual | The same with an invalid certificate thumbprint. | The task fails with a clear error and a non-zero exit code, without waiting for a browser. |
