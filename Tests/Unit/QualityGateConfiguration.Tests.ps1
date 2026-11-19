#Requires -Version 7.0

# Guards the committed configuration of the build modules and the quality gates:
# Build/BuildModules.psd1, Build/QualityGates.psd1 and complexity-baseline.json. None of them is a
# <Name>.ps1 the Test task can map a change to, so this suite is in its always-run list - a bad edit
# to any of them would otherwise skip the very tests that exist to catch it.

BeforeAll {
    $Script:RepositoryRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    $Script:BuildModules = Import-PowerShellDataFile -Path (Join-Path $Script:RepositoryRoot -ChildPath 'Build\BuildModules.psd1')
    $Script:QualityGates = Import-PowerShellDataFile -Path (Join-Path $Script:RepositoryRoot -ChildPath 'Build\QualityGates.psd1')
    $Script:BaselinePath = Join-Path $Script:RepositoryRoot -ChildPath $Script:QualityGates.Complexity.BaselineFile
}

Describe 'Build/BuildModules.psd1' {
    It 'pins <Name> to one exact version' -ForEach @(
        @{ Name = 'Pester' }
        @{ Name = 'psake' }
        @{ Name = 'OmadaWeb.PS' }
        @{ Name = 'PSScriptAnalyzer' }
        @{ Name = 'PSComplexity' }
        @{ Name = 'PSMutant' }
    ) {
        $Entry = @($Script:BuildModules.Modules | Where-Object { $_.Name -eq $Name })
        $Entry.Count | Should -Be 1 -Because "$Name must be listed exactly once"
        $Entry[0].RequiredVersion | Should -Match '^\d+\.\d+\.\d+(\.\d+)?$' -Because 'a pin is an exact release, never a range or a prerelease'
    }

    It 'runs Pester 6 or later, which the tests are written against' {
        [version]($Script:BuildModules.Modules | Where-Object { $_.Name -eq 'Pester' }).RequiredVersion | Should -BeGreaterOrEqual ([version]'6.0.0')
    }

    It 'supports Windows PowerShell 5.1 for the tests, which the module itself supports' {
        [version]$Script:BuildModules.MinimumPowerShellVersion | Should -Be ([version]'5.1')
    }

    It 'requires PowerShell 7.4 for <Name>, which does not load on Windows PowerShell' -ForEach @(
        @{ Name = 'PSComplexity' }
        @{ Name = 'PSMutant' }
    ) {
        [version]($Script:BuildModules.Modules | Where-Object { $_.Name -eq $Name }).MinimumPowerShellVersion | Should -BeGreaterOrEqual ([version]'7.4')
    }

    It 'pins OmadaWeb.PS to the same version the module manifest requires' {
        $Manifest = Import-PowerShellDataFile -Path (Join-Path $Script:RepositoryRoot -ChildPath 'OmadaSql.PS\OmadaSql.PS.psd1')
        $Required = @($Manifest.RequiredModules | Where-Object { $_.ModuleName -eq 'OmadaWeb.PS' })[0]
        ($Script:BuildModules.Modules | Where-Object { $_.Name -eq 'OmadaWeb.PS' }).RequiredVersion | Should -Be $Required.ModuleVersion
    }

    It 'is the only place the build installs modules from' {
        # build.ps1 used to carry its own unpinned Install-Module list next to InstallModules.ps1.
        $BuildScript = Get-Content -Path (Join-Path $Script:RepositoryRoot -ChildPath 'Build\build.ps1') -Raw
        $BuildScript | Should -Not -Match 'Install-Module'
        $BuildScript | Should -Match 'InstallModules\.ps1\S* -Import'
    }
}

Describe 'Build/QualityGates.psd1' {
    It 'sets complexity ceilings of at least 1' {
        $Script:QualityGates.Complexity.MaxCyclomatic | Should -BeGreaterOrEqual 1
        $Script:QualityGates.Complexity.MaxCognitive | Should -BeGreaterOrEqual 1
    }

    It 'measures source paths that exist' {
        foreach ($Path in @($Script:QualityGates.Complexity.SourcePath) + $Script:QualityGates.Mutation.SourcePath) {
            Test-Path -Path (Join-Path $Script:RepositoryRoot -ChildPath $Path) -PathType Container | Should -BeTrue -Because "$Path is measured"
        }
    }

    It 'sets a mutation break threshold, so the gate can fail at all' {
        $Break = $Script:QualityGates.Mutation.Thresholds.Break
        $Break | Should -Not -BeNullOrEmpty -Because 'a null break makes PSMutant report-only'
        $Break | Should -BeGreaterThan 0
        $Break | Should -BeLessOrEqual 100
    }

    It 'sets a per-file mutation floor no lower than the aggregate break' {
        $Floor = $Script:QualityGates.Mutation.Thresholds.FileBreak
        $Floor | Should -Not -BeNullOrEmpty -Because 'without it one weak file hides behind a strong aggregate'
        $Floor | Should -BeGreaterOrEqual $Script:QualityGates.Mutation.Thresholds.Break
        $Floor | Should -BeLessOrEqual 100
    }

    It 'requires an owning unit test file for changed source' {
        $Script:QualityGates.Mutation.RequireOwningTest | Should -BeTrue -Because 'source without a test cannot be mutation-tested'
    }

    It 'gives every declared equivalent mutant a reason' {
        foreach ($Key in $Script:QualityGates.Mutation.Equivalents.Keys) {
            $Script:QualityGates.Mutation.Equivalents[$Key] | Should -Not -BeNullOrEmpty -Because "$Key is excluded from the score"
        }
    }
}

Describe 'complexity-baseline.json' {
    BeforeAll {
        $Script:Baseline = Get-Content -LiteralPath $Script:BaselinePath -Raw | ConvertFrom-Json
    }

    It 'names only files that exist' {
        # A rename or delete that leaves its entry behind fails the weekly whole-tree run after the
        # merge; caught here, in the pull request that caused it.
        $Missing = @($Script:Baseline.units | Where-Object {
                -not (Test-Path -LiteralPath (Join-Path $Script:RepositoryRoot -ChildPath $_.file) -PathType Leaf)
            } | ForEach-Object { $_.file })
        $Missing | Should -BeNullOrEmpty -Because 'run ./Build/build.ps1 -Task UpdateComplexityBaseline after renaming or removing a file'
    }

    It 'records each unit once' {
        $Keys = @($Script:Baseline.units | ForEach-Object { '{0}|{1}' -f $_.file, $_.unit })
        ($Keys | Sort-Object -Unique).Count | Should -Be $Keys.Count
    }

    It 'records only units that are over a ceiling' {
        $UnderBoth = @($Script:Baseline.units | Where-Object {
                $_.cyclomatic -le $Script:QualityGates.Complexity.MaxCyclomatic -and $_.cognitive -le $Script:QualityGates.Complexity.MaxCognitive
            })
        $UnderBoth | Should -BeNullOrEmpty -Because 'a unit under both ceilings needs no baseline entry, and PSComplexity rejects one'
    }
}
