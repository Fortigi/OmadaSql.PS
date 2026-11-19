#Requires -Version 7.0

# The bundled T-SQL parser is pinned twice: by version in Build/Dependencies/Dependencies.csproj, which
# Dependabot updates, and by version and hash in Build/DependencyLock.psd1, which the build verifies
# against. These tests keep the two in step and prove the verification helpers refuse what they must.

BeforeAll {
    $Script:RepositoryRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    . (Join-Path $Script:RepositoryRoot 'Build/Get-BundledDependency.ps1')
    . (Join-Path $Script:RepositoryRoot 'Build/Update-DependencyLock.ps1')
    $Script:Lock = Import-PowerShellDataFile -Path (Join-Path $Script:RepositoryRoot 'Build/DependencyLock.psd1')
    $Script:ProjectXml = Get-Content -LiteralPath (Join-Path $Script:RepositoryRoot 'Build/Dependencies/Dependencies.csproj') -Raw
}

Describe 'Build/DependencyLock.psd1' {
    It 'pins the version Dependencies.csproj asks for' {
        @(Get-DependencyLockFault -Lock $Script:Lock -ProjectXml $Script:ProjectXml) | Should -BeNullOrEmpty
    }

    It 'pins every artifact and every file by a 64-character lower-case SHA-256' {
        foreach ($Artifact in $Script:Lock.Artifacts) {
            $Artifact.Sha256 | Should -MatchExactly '^[0-9a-f]{64}$'
            $Artifact.Url | Should -BeLike ('https://api.nuget.org/*/{0}.nupkg' -f $Artifact.Version)
            foreach ($File in $Artifact.Files) {
                $File.Sha256 | Should -MatchExactly '^[0-9a-f]{64}$'
            }
        }
    }

    It 'bundles a build for Windows PowerShell 5.1 and one for PowerShell 7' {
        $Targets = @($Script:Lock.Artifacts | ForEach-Object { $_.Files } | ForEach-Object { $_.Target })
        $Targets | Should -Contain 'lib/net472/Microsoft.SqlServer.TransactSql.ScriptDom.dll'
        $Targets | Should -Contain 'lib/net8.0/Microsoft.SqlServer.TransactSql.ScriptDom.dll'
    }

    It 'declares a license for every artifact' {
        foreach ($Artifact in $Script:Lock.Artifacts) {
            $Artifact.License | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'Get-DependencyLockFault' {
    It 'reports a version the csproj moved' {
        $Xml = $Script:ProjectXml -replace 'Version="[^"]+"', 'Version="999.0.0"'
        @(Get-DependencyLockFault -Lock $Script:Lock -ProjectXml $Xml) | Should -BeLike '*asks for 999.0.0*'
    }

    It 'reports a package the csproj no longer references' {
        $Xml = '<Project><ItemGroup /></Project>'
        @(Get-DependencyLockFault -Lock $Script:Lock -ProjectXml $Xml) | Should -BeLike '*not in Dependencies.csproj*'
    }
}

Describe 'Bundled file verification' {
    BeforeEach {
        $Script:Folder = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $null = New-Item -Path (Join-Path $Script:Folder 'lib') -ItemType Directory -Force
        $Script:FilePath = Join-Path $Script:Folder 'lib/a.dll'
        Set-Content -LiteralPath $Script:FilePath -Value 'payload' -NoNewline
        $Script:Hash = (Get-FileHash -LiteralPath $Script:FilePath -Algorithm SHA256).Hash.ToLowerInvariant()
    }

    It 'treats an artifact whose files all carry the pinned hash as current' {
        $Artifact = @{ Files = @(@{ Target = 'lib/a.dll'; Sha256 = $Script:Hash }) }
        Test-BundledDependencyCurrent -Artifact $Artifact -Destination $Script:Folder | Should -BeTrue
    }

    It 'treats a missing or altered file as not current' {
        Test-BundledDependencyCurrent -Artifact @{ Files = @(@{ Target = 'lib/b.dll'; Sha256 = $Script:Hash }) } -Destination $Script:Folder | Should -BeFalse
        Test-BundledDependencyCurrent -Artifact @{ Files = @(@{ Target = 'lib/a.dll'; Sha256 = ('0' * 64) }) } -Destination $Script:Folder | Should -BeFalse
    }

    It 'deletes a file whose hash does not match and refuses it' {
        { Assert-BundledHash -Path $Script:FilePath -Expected ('0' * 64) -Description 'a.dll' } | Should -Throw '*a.dll has SHA-256*'
        Test-Path -LiteralPath $Script:FilePath | Should -BeFalse
    }

    It 'keeps a file whose hash matches' {
        Assert-BundledHash -Path $Script:FilePath -Expected $Script:Hash -Description 'a.dll'
        Test-Path -LiteralPath $Script:FilePath | Should -BeTrue
    }

    It 'extracts only the listed files and verifies each one' {
        $Zip = Join-Path $TestDrive ('{0}.zip' -f [guid]::NewGuid().ToString('N'))
        Compress-Archive -LiteralPath $Script:FilePath -DestinationPath $Zip
        $Out = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $Artifact = @{ Id = 'x'; Version = '1'; Files = @(@{ Source = 'a.dll'; Target = 'lib/net/a.dll'; Sha256 = $Script:Hash }) }
        Expand-BundledDependency -Artifact $Artifact -PackagePath $Zip -Destination $Out
        Get-BundledFileHash -Path (Join-Path $Out 'lib/net/a.dll') | Should -Be $Script:Hash
        $Missing = @{ Id = 'x'; Version = '1'; Files = @(@{ Source = 'nope.dll'; Target = 'lib/n.dll'; Sha256 = $Script:Hash }) }
        { Expand-BundledDependency -Artifact $Missing -PackagePath $Zip -Destination $Out } | Should -Throw "*has no 'nope.dll'*"
    }
}
