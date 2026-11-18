param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaSql.PS\OmadaSql.PS.psm1')
)

BeforeAll {
    Get-Module OmadaSql.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'StrictMode' -Tag 'Unit' {

    Context 'Opt-in switch' {
        BeforeAll {
            $Script:PreviousStrictModeFlag = $Env:OMADASQLPS_STRICTMODE
        }

        AfterAll {
            # Restored, and the module re-imported under it, so the files Pester runs after this one
            # see the same module state they would have seen had this file never run.
            $Env:OMADASQLPS_STRICTMODE = $Script:PreviousStrictModeFlag
            Get-Module OmadaSql.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
            Import-Module $ModulePath -Force -ErrorAction Stop
        }

        It 'Should run module code under StrictMode when OMADASQLPS_STRICTMODE is 1' {
            $Env:OMADASQLPS_STRICTMODE = "1"
            Get-Module OmadaSql.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
            Import-Module $ModulePath -Force -ErrorAction Stop

            InModuleScope 'OmadaSql.PS' {
                # Built and invoked inside the module's session state, so it inherits whatever
                # StrictMode the module set on itself - which is the thing under test. A read of an
                # unset variable is an error only when StrictMode is on.
                { & { if ($NeverAssignedAnywhereInThisModule) { "reached" } } } | Should -Throw
            }
        }

        It 'Should leave module code unstrict when OMADASQLPS_STRICTMODE is not set' {
            $Env:OMADASQLPS_STRICTMODE = $null
            Get-Module OmadaSql.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
            Import-Module $ModulePath -Force -ErrorAction Stop

            InModuleScope 'OmadaSql.PS' {
                { & { if ($NeverAssignedAnywhereInThisModule) { "reached" } } } | Should -Not -Throw
            }
        }
    }
}
