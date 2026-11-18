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

> **Status: in development.** The repository framework is in place; the commands below are being
> built phase by phase as described in [docs/PLAN.md](docs/PLAN.md). Nothing is published to the
> PowerShell Gallery yet.

## PLANNED COMMANDS

| Area | Commands |
|---|---|
| Connection | `Connect-OmadaSql`, `Disconnect-OmadaSql`, `Get-OmadaSqlConnection` |
| Data connections | `Get-OmadaSqlDataConnection` |
| Query execution | `Invoke-OmadaSqlQuery` (existing SQL Troubleshooting objects, or ad-hoc SQL through a temporary query object; database-name prefixes and `USE` resolved to data connections) |
| Validation | `Test-OmadaSqlQuery` (T-SQL syntax, Omada compatibility rules, schema warnings); `-SkipValidation` on `Invoke-OmadaSqlQuery` |
| Schema | `Get-OmadaSqlSchema` |
| Object management (OData) | `Get-OmadaSqlQuery`, `New-OmadaSqlQuery`, `Set-OmadaSqlQuery`, `Remove-OmadaSqlQuery`, `Restore-OmadaSqlQuery` |
| History and overview | `Get-OmadaSqlQueryHistory`, `Get-OmadaSqlQuery -Detailed` |
| Temporary objects | `Get-OmadaSqlTempQuery`, `Clear-OmadaSqlTempQuery` |
| Export | `Export-OmadaSqlResult`, `Register-OmadaSqlExportFormat`, `Get-OmadaSqlExportFormat` |

## REQUIREMENTS

- Windows, with Windows PowerShell 5.1 or PowerShell 7.
- [OmadaWeb.PS](https://www.powershellgallery.com/packages/OmadaWeb.PS) 2026.9.23.47 or later
  (installed automatically as a required module).
- An Omada Identity Cloud tenant with the SQL Troubleshooting OData endpoint
  (`C_P_SQLTROUBLESHOOTING`) enabled. Running saved queries needs Read on the OData auth element;
  ad-hoc queries also need Create, Update and Delete, because they run through a temporary query
  object.

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
