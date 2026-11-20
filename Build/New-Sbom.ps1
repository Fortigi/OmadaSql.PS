<#
.SYNOPSIS
    Writes the CycloneDX SBOM of a module version, from Build/DependencyLock.psd1 (see Build/Sbom.ps1).
.PARAMETER Version
    The module version the package carries.
.PARAMETER OutputPath
    The .cdx.json file to write, as UTF-8 without a byte order mark.
.EXAMPLE
    ./Build/New-Sbom.ps1 -Version 2026.11.20.1 -OutputPath staging/OmadaSql.PS.2026.11.20.1.cdx.json
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Version,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
. (Join-Path -Path $PSScriptRoot -ChildPath 'Sbom.ps1')
$Lock = Import-PowerShellDataFile -Path (Join-Path -Path $PSScriptRoot -ChildPath 'DependencyLock.psd1')
$Sbom = New-OmadaSqlSbom -Lock $Lock -Version $Version
$Folder = Split-Path -Path $OutputPath -Parent
if (-not [string]::IsNullOrEmpty($Folder)) {
    $null = New-Item -Path $Folder -ItemType Directory -Force
}
$FullPath = [System.IO.Path]::GetFullPath($OutputPath)
[System.IO.File]::WriteAllText($FullPath, (ConvertTo-Json -InputObject $Sbom -Depth 10), [System.Text.UTF8Encoding]::new($false))
Write-Output ("Wrote {0}" -f $FullPath)
