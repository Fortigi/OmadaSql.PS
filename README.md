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

> **Status: in development.** The connection, data connection and object management commands are in place; the rest is being built phase
> by phase as described in [docs/PLAN.md](docs/PLAN.md). Nothing is published to the PowerShell
> Gallery yet.

## COMMANDS

<!-- BEGIN GENERATED COMMANDS -->

| Command | Synopsis |
|---|---|
| `Connect-OmadaSql` | Connects to an Omada Identity Cloud tenant for SQL Troubleshooting commands. |
| `Disconnect-OmadaSql` | Removes a connection made with Connect-OmadaSql. |
| `Get-OmadaSqlConnection` | Returns the current connection, or every connection. |
| `Get-OmadaSqlDataConnection` | Lists the data connections SQL Troubleshooting queries can run against. |
| `Get-OmadaSqlQuery` | Gets SQL Troubleshooting objects from Omada. |
| `Get-OmadaSqlQueryHistory` | Gets the full change history of a SQL Troubleshooting object. |
| `New-OmadaSqlQuery` | Creates a SQL Troubleshooting object in Omada. |
| `Remove-OmadaSqlQuery` | Deletes a SQL Troubleshooting object in Omada. |
| `Restore-OmadaSqlQuery` | Restores a deleted SQL Troubleshooting object. |
| `Set-OmadaSqlQuery` | Changes the name, SQL text or data connection of a SQL Troubleshooting object. |
| `Test-OmadaSqlQuery` | Checks a T-SQL query for syntax errors and for what SQL Troubleshooting cannot run. |

_Generated from the comment-based help by `Build/Update-ReadmeHelp.ps1`. Run `Get-Help <Command> -Full` for syntax, parameters and examples._

<!-- END GENERATED COMMANDS -->

## PLANNED COMMANDS

| Area | Commands |
|---|---|
| Query execution | `Invoke-OmadaSqlQuery` (existing SQL Troubleshooting objects, or ad-hoc SQL through a temporary query object; database-name prefixes and `USE` resolved to data connections) |
| Validation | Schema warnings in `Test-OmadaSqlQuery`; `-SkipValidation` on `Invoke-OmadaSqlQuery` |
| Schema | `Get-OmadaSqlSchema` |
| Temporary objects | `Get-OmadaSqlTempQuery`, `Clear-OmadaSqlTempQuery` |
| Export | `Export-OmadaSqlResult`, `Register-OmadaSqlExportFormat`, `Get-OmadaSqlExportFormat` |

## REQUIREMENTS

- Windows, with Windows PowerShell 5.1 (on .NET Framework 4.7.2 or later) or PowerShell 7.4 or later.
- [OmadaWeb.PS](https://www.powershellgallery.com/packages/OmadaWeb.PS) 2026.9.23.47 or later
  (installed automatically as a required module).
- An Omada Identity Cloud tenant with the SQL Troubleshooting OData endpoint
  (`C_P_SQLTROUBLESHOOTING`) enabled. Running saved queries needs Read on the OData auth element;
  ad-hoc queries also need Create, Update and Delete, because they run through a temporary query
  object.

The module bundles Microsoft's T-SQL parser, Microsoft.SqlServer.TransactSql.ScriptDom (MIT), to
validate queries locally; see [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).

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
```

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
