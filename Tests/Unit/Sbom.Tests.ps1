# Build/Sbom.ps1 builds the release SBOM from the dependency lock; these tests pin its shape, so a
# change to the lock shows up in the SBOM and a change to the SBOM is deliberate.

BeforeAll {
    $Script:RepositoryRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    . (Join-Path $Script:RepositoryRoot 'Build/Sbom.ps1')
    $Script:Lock = Import-PowerShellDataFile -Path (Join-Path $Script:RepositoryRoot 'Build/DependencyLock.psd1')
}

Describe 'New-OmadaSqlSbom' {
    BeforeAll {
        $Script:Sbom = New-OmadaSqlSbom -Lock $Script:Lock -Version '2026.11.20.1'
    }

    It 'is a CycloneDX 1.5 document for the module version' {
        $Script:Sbom.bomFormat | Should -Be 'CycloneDX'
        $Script:Sbom.specVersion | Should -Be '1.5'
        $Script:Sbom.version | Should -Be 1
        $Script:Sbom.metadata.component.name | Should -Be 'OmadaSql.PS'
        $Script:Sbom.metadata.component.version | Should -Be '2026.11.20.1'
        $Script:Sbom.metadata.component.purl | Should -Be 'pkg:nuget/OmadaSql.PS@2026.11.20.1'
        $Script:Sbom.metadata.component.'bom-ref' | Should -Be 'pkg:nuget/OmadaSql.PS@2026.11.20.1'
        $Script:Sbom.metadata.component.licenses[0].license.id | Should -Be 'MIT'
        $Script:Sbom.Contains('serialNumber') | Should -BeFalse
        $Script:Sbom.metadata.Contains('timestamp') | Should -BeFalse
    }

    It 'lists every locked package with its hash, license, source and files' {
        $Script:Sbom.components.Count | Should -Be $Script:Lock.Artifacts.Count
        for ($Index = 0; $Index -lt $Script:Lock.Artifacts.Count; $Index++) {
            $Artifact = $Script:Lock.Artifacts[$Index]
            $Component = $Script:Sbom.components[$Index]
            $Ref = 'pkg:nuget/{0}@{1}' -f $Artifact.Id, $Artifact.Version
            $Component.type | Should -Be 'library'
            $Component.name | Should -Be $Artifact.Id
            $Component.version | Should -Be $Artifact.Version
            $Component.purl | Should -Be $Ref
            $Component.'bom-ref' | Should -Be $Ref
            $Component.hashes[0].alg | Should -Be 'SHA-256'
            $Component.hashes[0].content | Should -Be $Artifact.Sha256
            $Component.licenses[0].license.id | Should -Be $Artifact.License
            $Component.externalReferences[0].type | Should -Be 'distribution'
            $Component.externalReferences[0].url | Should -Be $Artifact.Url
            @($Component.components.name) | Should -Be @($Artifact.Files.Target)
            @($Component.components.type | Select-Object -Unique) | Should -Be @('file')
            @($Component.components | ForEach-Object { $_.hashes[0].content }) | Should -Be @($Artifact.Files.Sha256)
            $Component.components[0].'bom-ref' | Should -Be ('{0}#{1}' -f $Ref, $Artifact.Files[0].Target)
        }
    }

    It 'records that the module depends on every bundled package' {
        $Script:Sbom.dependencies.Count | Should -Be 1
        $Script:Sbom.dependencies[0].ref | Should -Be 'pkg:nuget/OmadaSql.PS@2026.11.20.1'
        @($Script:Sbom.dependencies[0].dependsOn) | Should -Be @($Script:Sbom.components | ForEach-Object { $_.'bom-ref' })
    }

    It 'accepts a nightly version and refuses <Version>' -ForEach @(@{ Version = '1.2.3' }, @{ Version = 'v2026.11.20.1' }, @{ Version = '2026.11.20.1-' }) {
        (New-OmadaSqlSbom -Lock $Script:Lock -Version '2026.11.20.1-nightly').metadata.component.version | Should -Be '2026.11.20.1-nightly'
        { New-OmadaSqlSbom -Lock $Script:Lock -Version $Version } | Should -Throw
    }
}

Describe 'Build/New-Sbom.ps1' {
    It 'writes the SBOM as UTF-8 JSON without a byte order mark, creating the folder' {
        $Path = Join-Path $TestDrive 'out\OmadaSql.PS.cdx.json'
        $null = & (Join-Path $Script:RepositoryRoot 'Build/New-Sbom.ps1') -Version '2026.11.20.1' -OutputPath $Path
        $Bytes = [System.IO.File]::ReadAllBytes($Path)
        $Bytes[0] | Should -Be ([byte][char]'{')
        $Parsed = [System.IO.File]::ReadAllText($Path) | ConvertFrom-Json
        $Parsed.bomFormat | Should -Be 'CycloneDX'
        $Parsed.components[0].components[0].hashes[0].content | Should -Be $Script:Lock.Artifacts[0].Files[0].Sha256
    }
}
