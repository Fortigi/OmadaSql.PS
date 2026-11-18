# StrictMode has to be set here rather than by the caller: it is scoped to the session state it is
# set in, so a Set-StrictMode in the build script or in a Pester test reaches neither this file's
# load-time code nor any function defined below. Opt-in through OMADASQLPS_STRICTMODE; the build
# sets it for every test run, so an unset-variable read is caught before it ships.
if ($Env:OMADASQLPS_STRICTMODE -eq "1") {
    Set-StrictMode -Version Latest
}

$Script:ModuleName = "OmadaSql.PS"
"Loading {0} module" -f $Script:ModuleName | Write-Verbose

if ($PSVersionTable.PSVersion.Major -ge 6 -and !$IsWindows) {
    # OmadaWeb.PS, which performs every sign-in and request, is Windows-only.
    "{0} is only supported on Windows (Windows PowerShell 5.1 or PowerShell 7)." -f $Script:ModuleName | Write-Error -ErrorAction "Stop"
}

#region exclude
# Source mode only: the build replaces this region with the inlined Public and Private functions.
$Public = @(Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath "Public\*.ps1") -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.Name -notlike "_*.ps1" })
$Private = @(Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath "Private\*.ps1") -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.Name -notlike "_*.ps1" })
foreach ($Import in @($Public + $Private)) {
    try {
        . $Import.FullName
    }
    catch {
        "Failed to import function {0}: {1}" -f $Import.FullName, $_ | Write-Error -ErrorAction "Stop"
    }
}
if ($Public.Count -gt 0) {
    Export-ModuleMember -Function $Public.BaseName
}
#endregion
