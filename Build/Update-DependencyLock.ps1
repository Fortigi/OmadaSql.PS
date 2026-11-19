#Requires -Version 5.1

<#
.SYNOPSIS
    Keeps Build/DependencyLock.psd1 in step with Build/Dependencies/Dependencies.csproj.
.DESCRIPTION
    Dependabot moves the version in Dependencies.csproj. The lock then still pins the old version and
    its hashes, and Tests/Unit/DependencyLock.Tests.ps1 fails. Run this script on that branch: it
    downloads the package at the csproj version, computes the package hash and the hash of every file
    the lock takes out of it, and rewrites the lock. Review the diff like any other change: the new
    hashes are what every later build verifies against.

    -Check only compares the two versions and makes no request.
.PARAMETER Check
    Fail when the lock and the csproj disagree; change nothing.
.EXAMPLE
    ./Build/Update-DependencyLock.ps1

    Re-pins the lock to the versions in Dependencies.csproj.
#>
[CmdletBinding()]
param(
    [switch]$Check,
    [string]$LockPath = (Join-Path -Path $PSScriptRoot -ChildPath 'DependencyLock.psd1'),
    [string]$ProjectPath = (Join-Path -Path $PSScriptRoot -ChildPath 'Dependencies\Dependencies.csproj')
)

function Get-DependencyManifestVersion {
    # The version a csproj's PackageReference pins for a package, or $null.
    param(
        [Parameter(Mandatory = $true)][string]$ProjectXml,
        [Parameter(Mandatory = $true)][string]$PackageId
    )
    $Project = [xml]$ProjectXml
    $Reference = @($Project.SelectNodes('//PackageReference') | Where-Object { $_.Include -eq $PackageId })
    if ($Reference.Count -eq 0) {
        return $null
    }
    return [string]$Reference[0].Version
}

function Get-DependencyLockFault {
    # One line per artifact whose lock version differs from the csproj, or is missing there.
    param(
        [Parameter(Mandatory = $true)][hashtable]$Lock,
        [Parameter(Mandatory = $true)][string]$ProjectXml
    )
    foreach ($Artifact in $Lock.Artifacts) {
        $Manifest = Get-DependencyManifestVersion -ProjectXml $ProjectXml -PackageId $Artifact.Id
        if ($null -eq $Manifest) {
            "{0} is in the lock but not in Dependencies.csproj." -f $Artifact.Id
        }
        elseif ($Manifest -ne $Artifact.Version) {
            "{0}: the lock pins {1}, Dependencies.csproj asks for {2}." -f $Artifact.Id, $Artifact.Version, $Manifest
        }
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    $ErrorActionPreference = 'Stop'
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Get-BundledDependency.ps1')
    $Lock = Import-PowerShellDataFile -Path $LockPath
    $ProjectXml = Get-Content -LiteralPath $ProjectPath -Raw
    $Fault = @(Get-DependencyLockFault -Lock $Lock -ProjectXml $ProjectXml)
    if ($Check) {
        if ($Fault.Count -gt 0) {
            throw ("The dependency lock is out of date:`n{0}`nRun ./Build/Update-DependencyLock.ps1." -f ($Fault -join "`n"))
        }
        'The dependency lock matches Dependencies.csproj.' | Write-Host
        return
    }
    $LockText = Get-Content -LiteralPath $LockPath -Raw
    foreach ($Artifact in $Lock.Artifacts) {
        $Version = Get-DependencyManifestVersion -ProjectXml $ProjectXml -PackageId $Artifact.Id
        if ($Version -eq $Artifact.Version) {
            continue
        }
        $Url = 'https://api.nuget.org/v3-flatcontainer/{0}/{1}/{0}.{1}.nupkg' -f $Artifact.Id.ToLowerInvariant(), $Version
        $PackagePath = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('{0}.nupkg' -f [guid]::NewGuid().ToString('N'))
        try {
            Invoke-WebRequest -Uri $Url -OutFile $PackagePath -UseBasicParsing
            $LockText = $LockText.Replace($Artifact.Url, $Url).Replace("'$($Artifact.Version)'", "'$Version'").Replace($Artifact.Sha256, (Get-BundledFileHash -Path $PackagePath))
            Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
            $Archive = [System.IO.Compression.ZipFile]::OpenRead($PackagePath)
            try {
                foreach ($File in $Artifact.Files) {
                    $Entry = $Archive.GetEntry($File.Source)
                    if ($null -eq $Entry) {
                        throw ("{0} {1} has no '{2}'." -f $Artifact.Id, $Version, $File.Source)
                    }
                    $Temp = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ([guid]::NewGuid().ToString('N'))
                    [System.IO.Compression.ZipFileExtensions]::ExtractToFile($Entry, $Temp, $true)
                    $LockText = $LockText.Replace($File.Sha256, (Get-BundledFileHash -Path $Temp))
                    Remove-Item -LiteralPath $Temp -Force
                }
            }
            finally {
                $Archive.Dispose()
            }
        }
        finally {
            Remove-Item -LiteralPath $PackagePath -Force -ErrorAction SilentlyContinue
        }
        "{0}: {1} -> {2}" -f $Artifact.Id, $Artifact.Version, $Version | Write-Host
    }
    [System.IO.File]::WriteAllText($LockPath, $LockText, [System.Text.UTF8Encoding]::new($false))
}
