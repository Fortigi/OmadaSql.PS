<#
    The PowerShell modules the build runs on, each pinned to one exact version.

    This file is the only place these versions live. Build/InstallModules.ps1 installs exactly these
    versions and, with -Import, imports exactly these versions, so a CI runner, a developer machine
    and next month's runner all execute the same analyzer, the same test runner and the same metrics.
    That matters most for PSComplexity: its scores have changed between releases for source that did
    not, so an unpinned upgrade would turn a green commit red without anyone touching it.

    Dependabot does not cover the PowerShell Gallery. The weekly quality workflow
    (.github/workflows/quality-weekly.yml) compares every pin here with the Gallery and files an
    issue when one has a newer release; bump the version here and run the build to adopt it.

    Keys per module:
      Name                     - the PowerShell Gallery module name
      RequiredVersion          - the exact version installed and imported
      Import                   - $true when Build/build.ps1 imports it before invoking psake
      MinimumPowerShellVersion - the module is skipped (not installed, not imported) on an older
                                 PowerShell. The tasks that need it skip themselves there too.

    OmadaWeb.PS is not a build tool but the module's one runtime dependency (RequiredModules in
    OmadaSql.PS/OmadaSql.PS.psd1). It is installed so the ImportModule and TestHelp tasks can import
    the built manifest, and pinned so every build is tested against the same version.
#>
@{
    Modules                  = @(
        @{
            # 6.2.0 still ships a net462 build and declares PowerShell 5.1 as its minimum, so the
            # Windows PowerShell leg of PR validation runs the same Pester as the pwsh leg.
            Name                     = 'Pester'
            RequiredVersion          = '6.2.0'
            Import                   = $true
            MinimumPowerShellVersion = '5.1'
        }
        @{
            Name                     = 'psake'
            RequiredVersion          = '5.0.4'
            Import                   = $true
            MinimumPowerShellVersion = '5.1'
        }
        @{
            Name                     = 'PSScriptAnalyzer'
            RequiredVersion          = '1.25.0'
            Import                   = $true
            MinimumPowerShellVersion = '5.1'
        }
        @{
            Name                     = 'PSComplexity'
            RequiredVersion          = '0.5.1'
            Import                   = $true
            MinimumPowerShellVersion = '7.4'
        }
        @{
            # PSMutant deliberately declares no Pester dependency and runs under whichever Pester is
            # already loaded, which is the Pester pinned above.
            Name                     = 'PSMutant'
            RequiredVersion          = '0.5.0'
            Import                   = $true
            MinimumPowerShellVersion = '7.4'
        }
        @{
            Name                     = 'OmadaWeb.PS'
            RequiredVersion          = '2026.9.23.47'
            Import                   = $false
            MinimumPowerShellVersion = '5.1'
        }
    )

    # The Windows PowerShell leg of PR validation runs the tests on 5.1; the quality gates need 7.4.
    MinimumPowerShellVersion = '5.1'
}
