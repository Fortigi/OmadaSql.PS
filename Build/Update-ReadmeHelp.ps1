#Requires -Version 5.1
<#
.SYNOPSIS
    Regenerates the command table in README.md from the module's comment-based help.
.DESCRIPTION
    The region between '<!-- BEGIN GENERATED COMMANDS -->' and '<!-- END GENERATED COMMANDS -->' in
    README.md is written from the exported commands of the module: one row per command with its
    synopsis. The full syntax, parameters and examples stay in Get-Help, which is where they are
    maintained.

    With -Check nothing is written: the script fails when the README differs from what it would
    generate. The build's TestHelp task runs it that way, so a new or renamed command cannot ship
    with a stale README.
.PARAMETER ModuleManifestPath
    The module manifest to read the commands from. Defaults to the manifest in the working copy.
.PARAMETER ReadmePath
    The README to update.
.PARAMETER Check
    Only compare, and fail when the README is out of date.
.EXAMPLE
    ./Build/Update-ReadmeHelp.ps1

    Rewrites the command table in README.md.
.EXAMPLE
    ./Build/Update-ReadmeHelp.ps1 -Check -ModuleManifestPath ./buildoutput/OmadaSql.PS/OmadaSql.PS.psd1

    Fails when README.md does not match the built module, which is what the build does.
#>
[CmdletBinding()]
param(
    [string]$ModuleManifestPath = (Join-Path -Path $PSScriptRoot -ChildPath '..\OmadaSql.PS\OmadaSql.PS.psd1'),
    [string]$ReadmePath = (Join-Path -Path $PSScriptRoot -ChildPath '..\README.md'),
    [switch]$Check
)

$ErrorActionPreference = 'Stop'
$BeginMarker = '<!-- BEGIN GENERATED COMMANDS -->'
$EndMarker = '<!-- END GENERATED COMMANDS -->'

$null = Import-Module -Name $ModuleManifestPath -Force -PassThru
$Manifest = Import-PowerShellDataFile -Path $ModuleManifestPath

$Rows = foreach ($Name in @($Manifest.FunctionsToExport | Sort-Object)) {
    $Synopsis = ((Get-Help -Name $Name).Synopsis | Out-String).Trim() -replace '\s+', ' ' -replace '\|', '\|'
    '| `{0}` | {1} |' -f $Name, $Synopsis
}

$Generated = @(
    $BeginMarker
    ''
    '| Command | Synopsis |'
    '|---|---|'
    $Rows
    ''
    '_Generated from the comment-based help by `Build/Update-ReadmeHelp.ps1`. Run `Get-Help <Command> -Full` for syntax, parameters and examples._'
    ''
    $EndMarker
) -join "`n"

$Readme = [System.IO.File]::ReadAllText((Resolve-Path -Path $ReadmePath).Path)
$Start = $Readme.IndexOf($BeginMarker)
$End = $Readme.IndexOf($EndMarker)
if ($Start -lt 0 -or $End -lt $Start) {
    throw "README '$ReadmePath' has no '$BeginMarker' ... '$EndMarker' region."
}
$Updated = $Readme.Substring(0, $Start) + $Generated + $Readme.Substring($End + $EndMarker.Length)

# Compared with normalised line endings: a checkout with CRLF is not a stale README.
if (($Updated -replace "`r`n", "`n") -eq ($Readme -replace "`r`n", "`n")) {
    'README command table is up to date.' | Write-Host
    return
}

if ($Check) {
    throw "README.md is out of date with the module's exported commands. Run ./Build/Update-ReadmeHelp.ps1 and commit the result."
}

[System.IO.File]::WriteAllText((Resolve-Path -Path $ReadmePath).Path, $Updated, [System.Text.UTF8Encoding]::new($false))
'README command table updated.' | Write-Host
