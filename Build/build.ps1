#Requires -Version 5.1
<#
.SYNOPSIS
    Entry point of the build: installs and imports the pinned build modules, then runs psake.
.EXAMPLE
    ./Build/build.ps1

    Runs the default task list: Analyze, Build, ImportModule, TestHelp, Test.
.EXAMPLE
    ./Build/build.ps1 -Task TestBuildOnly -BuildVersion '0.0.0'

    What PR validation runs.
#>
[CmdletBinding()]
param(
    [string[]]$Task = 'default',
    [string]$BuildVersion = ""
)
$Error.Clear()
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
try {
    # The module list and its pinned versions live in BuildModules.psd1 alone; this installs and
    # imports exactly those versions. Its failure path exits non-zero.
    . (Join-Path -Path $PSScriptRoot -ChildPath "InstallModules.ps1") -Import

    Invoke-psake -buildFile (Join-Path -Path $PSScriptRoot -ChildPath "psakeBuild.ps1") -taskList $Task -Verbose:$VerbosePreference -parameters @{ "BuildVersion" = $BuildVersion }

    if (!$psake.build_success) {
        throw "psake build failed, see output above for details."
    }
}
catch {
    $PSCmdlet.ThrowTerminatingError($PSItem)
}
