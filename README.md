# OmadaSql.PS

[![PowerShell Gallery Version](https://img.shields.io/powershellgallery/v/OmadaSql.PS?include_prereleases)](https://www.powershellgallery.com/packages/OmadaSql.PS)
![PowerShell 5.1](https://img.shields.io/badge/PowerShell-5.1-blue)
![PowerShell 7](https://img.shields.io/badge/PowerShell-7-blue)
![Platform](https://img.shields.io/badge/platform-Windows-lightgrey)

## DESCRIPTION

PowerShell module to run SQL queries against Omada Identity Cloud through the SQL Troubleshooting
endpoints, headless and suitable for unattended automation. It is the scripting counterpart of
[OmadaSqlTroubleshooter](https://github.com/Fortigi/OmadaSqlTroubleshooter) and uses the same
requests, the same temporary-query technique and the same query rules.

All sign-in and every request go through [OmadaWeb.PS](https://github.com/Fortigi/OmadaWeb.PS), so
every authentication type it supports is available, including unattended OAuth with a client
certificate.

> **Status: pre-release.** All planned commands are in place and covered by unit and integration
> tests; the first nightly is the next step, see [docs/PLAN.md](docs/PLAN.md). Nothing is published
> to the PowerShell Gallery yet, and the module has not yet been run against a live tenant.

## COMMANDS

<!-- BEGIN GENERATED COMMANDS -->

| Command | Synopsis |
|---|---|
| `Clear-OmadaSqlTempQuery` | Deletes, and with -Purge permanently removes, temporary SQL Troubleshooting objects. |
| `Connect-OmadaSql` | Connects to an Omada Identity Cloud tenant for SQL Troubleshooting commands. |
| `Disconnect-OmadaSql` | Removes a connection made with Connect-OmadaSql. |
| `Export-OmadaSqlResult` | Writes query result rows as CSV, JSON, XML, a text table, or T-SQL or PowerShell literals. |
| `Get-OmadaSqlConnection` | Returns the current connection, or every connection. |
| `Get-OmadaSqlDataConnection` | Lists the data connections SQL Troubleshooting queries can run against. |
| `Get-OmadaSqlExportFormat` | Lists the formats Export-OmadaSqlResult can write. |
| `Get-OmadaSqlQuery` | Gets SQL Troubleshooting objects from Omada. |
| `Get-OmadaSqlQueryHistory` | Gets the full change history of a SQL Troubleshooting object. |
| `Get-OmadaSqlSchema` | Lists the tables and views of a data connection, with their columns and data types. |
| `Get-OmadaSqlTempQuery` | Lists the temporary SQL Troubleshooting objects that ad-hoc queries run through. |
| `Invoke-OmadaSqlQuery` | Runs a SQL query on an Omada Identity Cloud tenant through SQL Troubleshooting. |
| `New-OmadaSqlQuery` | Creates a SQL Troubleshooting object in Omada. |
| `Register-OmadaSqlExportFormat` | Adds an export format to Export-OmadaSqlResult for this session. |
| `Remove-OmadaSqlQuery` | Deletes a SQL Troubleshooting object in Omada. |
| `Restore-OmadaSqlQuery` | Restores a deleted SQL Troubleshooting object. |
| `Set-OmadaSqlQuery` | Changes the name, SQL text or data connection of a SQL Troubleshooting object. |
| `Test-OmadaSqlQuery` | Checks a T-SQL query for syntax errors and for what SQL Troubleshooting cannot run. |

_Generated from the comment-based help by `Build/Update-ReadmeHelp.ps1`. Run `Get-Help <Command> -Full` for syntax, parameters and examples._

<!-- END GENERATED COMMANDS -->

## REQUIREMENTS

- Windows, with Windows PowerShell 5.1 (on .NET Framework 4.7.2 or later) or PowerShell 7.4 or later.
- [OmadaWeb.PS](https://www.powershellgallery.com/packages/OmadaWeb.PS) 2026.9.23.47 or later
  (installed automatically as a required module).
- An Omada Identity Cloud tenant with the SQL Troubleshooting OData endpoint
  (`C_P_SQLTROUBLESHOOTING`) enabled. Running saved queries needs Read on the OData auth element;
  ad-hoc queries also need Create, Update and Delete, because they run through a temporary query
  object.

The module bundles Microsoft's T-SQL parser, Microsoft.SqlServer.TransactSql.ScriptDom (MIT), to
validate queries locally; see [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md). Each release has a
CycloneDX SBOM (`OmadaSql.PS.<version>.cdx.json`) next to the package.

## INSTALLATION

Once published:

```powershell
Install-Module -Name OmadaSql.PS -Scope CurrentUser
```

From a local build:

```powershell
./Build/build.ps1 -Task Build
./deploy.ps1 -Scope CurrentUser
```

## USAGE

```powershell
# Unattended, with a client certificate in the certificate store
Connect-OmadaSql -Url 'https://tenant.omada.cloud' -AuthenticationType OAuth `
    -ClientId '<application id>' -OAuthCertificateThumbprint '<thumbprint>' -EntraIdTenantId '<tenant>'

# Interactive
Connect-OmadaSql -Url 'https://tenant.omada.cloud'

# Check a query, including its table and column names, then run it and write a CSV file
Test-OmadaSqlQuery -Path .\Export.sql -DataConnection 'OISES'
Invoke-OmadaSqlQuery -Path .\Export.sql -DataConnection 'OISES' | Export-OmadaSqlResult -Path .\export.csv -Force

# Run a saved SQL Troubleshooting object and turn its ids into an IN list
Invoke-OmadaSqlQuery -Name 'Deleted identities' | Export-OmadaSqlResult -Format SqlArray
```

For a scheduled task, connect with `-NoInteractiveAuthentication`, so an expired session fails
instead of waiting for a browser sign-in, and stop on the first error:

```powershell
$ErrorActionPreference = 'Stop'
Connect-OmadaSql -Url 'https://tenant.omada.cloud' -AuthenticationType OAuth -NoInteractiveAuthentication `
    -ClientId '<application id>' -OAuthCertificateThumbprint '<thumbprint>' -EntraIdTenantId '<tenant>'
Invoke-OmadaSqlQuery -Name 'Daily export' | Export-OmadaSqlResult -Path 'D:\Exports\daily.csv' -Encoding UTF8BOM -Force
Disconnect-OmadaSql
```

### Temporary query objects

Ad-hoc SQL runs through a temporary SQL Troubleshooting object, as in OmadaSqlTroubleshooter. Each
user profile uses a small fixed pool (`TMP_<profile id>_<n>`, at most `MaxTempQuerySlots`, default 4,
in `%LOCALAPPDATA%\OmadaSql.PS\settings.json`): a slot is restored, filled, run and soft-deleted
again, and runs at the same time each lease their own slot. `Get-OmadaSqlTempQuery` lists the
profile's objects and `Clear-OmadaSqlTempQuery -Purge` removes them for good (purging needs the
System, Operation or Data Administrator role). A saved object is never changed by running it.

Every command throws a terminating error whose `FullyQualifiedErrorId` starts with
`OmadaSql.<Kind>`, so a script can act on the cause without parsing messages:

| Kind | Meaning |
|---|---|
| `NotConnected` | No connection; run `Connect-OmadaSql`. |
| `EndpointNotEnabled` | The `C_P_SQLTROUBLESHOOTING` OData endpoint is not enabled on the tenant. |
| `SessionExpired` | No valid session (HTTP 401), or an expired session with `-NoInteractiveAuthentication`. |
| `MissingPermission` | A write over OData was refused after a successful read: the identity lacks Create, Update or Delete on the `OData` auth element. |
| `AccessDenied`, `NotFound`, `ServerError`, `RequestFailed` | HTTP 403, 404, 5xx and anything else. A SQL error arrives as a generic 500. |
| `InvalidArgument` | A parameter combination was refused before anything was sent. |
| `ValidationFailed` | `Invoke-OmadaSqlQuery` found a blocking rule finding and sent nothing (see `Test-OmadaSqlQuery`). |
| `Busy` | Every temporary query slot of this profile stayed in use until the timeout. |
| `InvalidResult` | Omada answered with something the module cannot use, such as a result larger than one page. |

`-Verbose` shows each request (method, URI, duration, outcome); secrets are masked and request
bodies, which can hold query text, are never written.

## CONTRIBUTING AND SECURITY

See [CONTRIBUTING.md](CONTRIBUTING.md) for the test rules, the quality gates and the pull request
flow, and [SECURITY.md](SECURITY.md) for reporting vulnerabilities and the repository's security
controls.

## RELATED LINKS

- [OmadaWeb.PS](https://github.com/Fortigi/OmadaWeb.PS)
- [OmadaSqlTroubleshooter](https://github.com/Fortigi/OmadaSqlTroubleshooter)
- [Omada Identity documentation](https://documentation.omadaidentity.com/)

## LICENSE

[MIT](LICENSE)
