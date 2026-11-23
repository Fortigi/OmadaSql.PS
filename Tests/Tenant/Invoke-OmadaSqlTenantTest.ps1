<#
.SYNOPSIS
    Runs the automated steps of docs/TENANT-TEST.md against the tenant of the current connection.

.DESCRIPTION
    Connect first with Connect-OmadaSql, as the account whose role you test. The test creates
    SQL Troubleshooting objects named 'OSQLTEST <run id> <step>' and removes them again, runs only
    general queries (constants, VALUES lists and the schema of the data connection) and reads no
    business data. Run it on a test or acceptance tenant, never on production.

    Run it twice on the same Windows profile: once connected as a regular user (-Role User), then as
    an administrator (-Role Administrator). The administrator pass purges the temporary objects
    both passes left behind, because both use this profile's slot pool.

    The results go to a folder: results.xml (NUnit, one test per step) and observations.json, which
    records what the tenant did where the module only assumes it (shapes and outcomes, no values).
    Error messages are kept, so read observations.json before you share it.

.PARAMETER Role
    The role of the connected account: User (Read, Create, Update and Delete on the OData auth
    element, no administrator role) or Administrator (System, Operation or Data Administrator).

.PARAMETER DataConnection
    The name of the data connection to run the queries against.

.PARAMETER SecondDataConnection
    The name of a second data connection, for the script that addresses two databases (3.10) and
    the second schema (4.4). Leave it out when the tenant has only one.

.PARAMETER QueryPath
    A folder of .sql files the team uses, to check the schema rules for false findings (4.6).

.PARAMETER IncludeLargeResult
    Also run step 3.12, a query of 161 051 rows.

.PARAMETER OutputPath
    The folder for results.xml and observations.json. Defaults to
    .\TenantTestResult-<role>-<timestamp>.

.EXAMPLE
    Connect-OmadaSql -Url 'https://<test tenant>.omada.cloud'
    ./Tests/Tenant/Invoke-OmadaSqlTenantTest.ps1 -Role User -DataConnection 'OISES'

    Runs the steps for a regular user against the OISES data connection.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('User', 'Administrator')]
    [string]$Role,

    [Parameter(Mandatory = $true)]
    [string]$DataConnection,

    [string]$SecondDataConnection,

    [string]$QueryPath,

    [switch]$IncludeLargeResult,

    [string]$OutputPath = (Join-Path -Path (Get-Location) -ChildPath ('TenantTestResult-{0}-{1:yyyyMMdd-HHmmss}' -f $Role, (Get-Date)))
)

$ErrorActionPreference = 'Stop'

$Pester = Get-Module -Name Pester -ListAvailable | Where-Object { $_.Version -ge [version]'5.5.0' } | Sort-Object -Property Version -Descending | Select-Object -First 1
if ($null -eq $Pester) {
    throw 'The tenant test needs Pester 5.5 or later: Install-Module Pester -MinimumVersion 5.5.0 -Scope CurrentUser'
}
Import-Module -Name $Pester.Path -Force
if ($null -eq (Get-Module -Name OmadaSql.PS)) {
    throw 'Import OmadaSql.PS and connect with Connect-OmadaSql before you run the tenant test.'
}
$Connection = Get-OmadaSqlConnection
if ($null -eq $Connection) {
    throw 'Connect with Connect-OmadaSql, as the account whose role you test, before you run the tenant test.'
}
if (-not [string]::IsNullOrEmpty($QueryPath) -and -not (Test-Path -LiteralPath $QueryPath -PathType Container)) {
    throw "QueryPath '$QueryPath' is not a folder."
}

$RunId = Get-Date -Format 'yyyyMMddHHmmss'
$null = New-Item -Path $OutputPath -ItemType Directory -Force
$global:OmadaSqlTenantObservation = [System.Collections.Generic.List[object]]::new()

$Container = New-PesterContainer -Path (Join-Path -Path $PSScriptRoot -ChildPath 'OmadaSql.TenantTest.ps1') -Data @{
    DataConnection       = $DataConnection
    SecondDataConnection = $SecondDataConnection
    QueryPath            = $QueryPath
    RunId                = $RunId
}
$Configuration = New-PesterConfiguration
$Configuration.Run.Container = $Container
$Configuration.Run.PassThru = $true
$Configuration.Output.Verbosity = 'Detailed'
$Configuration.TestResult.Enabled = $true
$Configuration.TestResult.OutputFormat = 'NUnitXml'
$Configuration.TestResult.OutputPath = Join-Path -Path $OutputPath -ChildPath 'results.xml'
$Exclude = @($(if ($Role -eq 'User') { 'Administrator' } else { 'User' }))
if (-not $IncludeLargeResult) {
    $Exclude += 'Large'
}
$Configuration.Filter.ExcludeTag = $Exclude

try {
    $Result = Invoke-Pester -Configuration $Configuration
}
finally {
    $Report = [ordered]@{
        Run          = $RunId
        Role         = $Role
        Module       = [string](Get-Module -Name OmadaSql.PS).Version
        OmadaWeb     = [string](Get-Module -Name OmadaWeb.PS).Version
        PowerShell   = [string]$PSVersionTable.PSVersion
        Edition      = $PSVersionTable.PSEdition
        Observations = @($global:OmadaSqlTenantObservation)
    }
    $ObservationPath = Join-Path -Path $OutputPath -ChildPath 'observations.json'
    [System.IO.File]::WriteAllText($ObservationPath, (ConvertTo-Json -InputObject $Report -Depth 10), [System.Text.UTF8Encoding]::new($false))
    Remove-Variable -Name OmadaSqlTenantObservation -Scope Global -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host ('Passed {0}, failed {1}, skipped {2}. Results in {3}' -f $Result.PassedCount, $Result.FailedCount, $Result.SkippedCount, $OutputPath)
if ($Result.FailedCount -gt 0) {
    exit 1
}
