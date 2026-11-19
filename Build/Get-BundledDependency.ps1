#Requires -Version 5.1

<#
.SYNOPSIS
    Puts the binaries the module bundles (Build/DependencyLock.psd1) into the module folder, verified.
.DESCRIPTION
    Downloads each pinned NuGet package, refuses it unless its SHA-256 matches the lock, extracts only
    the files the lock lists and refuses each one unless its own SHA-256 matches. A file that is
    already in place with the right hash is left alone, so a second build makes no request.

    The extracted files are not committed (see .gitignore); the build recreates them, and the package
    ships them under lib/.
.PARAMETER Destination
    The module folder to extract into. Defaults to the OmadaSql.PS source folder.
.PARAMETER LockPath
    The dependency lock. Defaults to Build/DependencyLock.psd1.
.EXAMPLE
    ./Build/Get-BundledDependency.ps1

    Places the verified ScriptDom assemblies under OmadaSql.PS/lib.
#>
[CmdletBinding()]
param(
    [string]$Destination = (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'OmadaSql.PS'),
    [string]$LockPath = (Join-Path -Path $PSScriptRoot -ChildPath 'DependencyLock.psd1')
)

function Get-BundledFileHash {
    # Lower-case hex SHA-256 of a file, or $null when the file does not exist.
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $null
    }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-BundledFileTarget {
    # The full path a lock entry's Target resolves to under the destination folder.
    param(
        [Parameter(Mandatory = $true)][string]$Destination,
        [Parameter(Mandatory = $true)][string]$Target
    )
    $Relative = $Target -replace '[\\/]', [System.IO.Path]::DirectorySeparatorChar
    return (Join-Path -Path $Destination -ChildPath $Relative)
}

function Test-BundledDependencyCurrent {
    # Whether every file of an artifact is already in place with the pinned hash.
    param(
        [Parameter(Mandatory = $true)][hashtable]$Artifact,
        [Parameter(Mandatory = $true)][string]$Destination
    )
    foreach ($File in $Artifact.Files) {
        $Hash = Get-BundledFileHash -Path (Get-BundledFileTarget -Destination $Destination -Target $File.Target)
        if ($Hash -ne $File.Sha256) {
            return $false
        }
    }
    return $true
}

function Assert-BundledHash {
    # Throws, after deleting the file, when a file's hash differs from the pinned one.
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Expected,
        [Parameter(Mandatory = $true)][string]$Description
    )
    $Actual = Get-BundledFileHash -Path $Path
    if ($Actual -ne $Expected) {
        Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
        throw ("{0} has SHA-256 '{1}', the lock pins '{2}'. The file was deleted; nothing from it is used." -f $Description, $Actual, $Expected)
    }
}

function Expand-BundledDependency {
    # Extracts the lock's files from a verified package and verifies each one.
    param(
        [Parameter(Mandatory = $true)][hashtable]$Artifact,
        [Parameter(Mandatory = $true)][string]$PackagePath,
        [Parameter(Mandatory = $true)][string]$Destination
    )
    Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
    $Archive = [System.IO.Compression.ZipFile]::OpenRead($PackagePath)
    try {
        foreach ($File in $Artifact.Files) {
            $Entry = $Archive.GetEntry($File.Source)
            if ($null -eq $Entry) {
                throw ("{0} {1} has no '{2}'." -f $Artifact.Id, $Artifact.Version, $File.Source)
            }
            $TargetPath = Get-BundledFileTarget -Destination $Destination -Target $File.Target
            $null = New-Item -Path (Split-Path -Path $TargetPath -Parent) -ItemType Directory -Force
            [System.IO.Compression.ZipFileExtensions]::ExtractToFile($Entry, $TargetPath, $true)
            Assert-BundledHash -Path $TargetPath -Expected $File.Sha256 -Description $File.Target
        }
    }
    finally {
        $Archive.Dispose()
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    $ErrorActionPreference = 'Stop'
    $Lock = Import-PowerShellDataFile -Path $LockPath
    foreach ($Artifact in $Lock.Artifacts) {
        if (Test-BundledDependencyCurrent -Artifact $Artifact -Destination $Destination) {
            "{0} {1} is already in place and verified." -f $Artifact.Id, $Artifact.Version | Write-Host
            continue
        }
        $PackagePath = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('{0}.{1}.{2}.nupkg' -f $Artifact.Id, $Artifact.Version, [guid]::NewGuid().ToString('N'))
        try {
            "Downloading {0} {1}" -f $Artifact.Id, $Artifact.Version | Write-Host
            $PreviousProgress = $ProgressPreference
            $ProgressPreference = 'SilentlyContinue'
            try {
                Invoke-WebRequest -Uri $Artifact.Url -OutFile $PackagePath -UseBasicParsing
            }
            finally {
                $ProgressPreference = $PreviousProgress
            }
            Assert-BundledHash -Path $PackagePath -Expected $Artifact.Sha256 -Description ('{0} {1} package' -f $Artifact.Id, $Artifact.Version)
            Expand-BundledDependency -Artifact $Artifact -PackagePath $PackagePath -Destination $Destination
            "{0} {1} extracted and verified." -f $Artifact.Id, $Artifact.Version | Write-Host
        }
        finally {
            Remove-Item -LiteralPath $PackagePath -Force -ErrorAction SilentlyContinue
        }
    }
}
