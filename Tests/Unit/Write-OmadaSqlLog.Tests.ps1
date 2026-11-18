param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaSql.PS\OmadaSql.PS.psm1')
)

BeforeAll {
    Get-Module -Name OmadaSql.PS -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Write-OmadaSqlLog' -Tag 'Unit' {
    It 'Writes the redacted message to the Verbose stream by default' {
        InModuleScope 'OmadaSql.PS' {
            $Output = Write-OmadaSqlLog -Message 'password=Hunter2' -Verbose 4>&1
            $Output.Message | Should -BeLike '[[]OmadaSql.PS[]]*REDACTED*'
            $Output.Message | Should -Not -BeLike '*Hunter2*'
        }
    }

    It 'Writes to the Debug stream when asked' {
        InModuleScope 'OmadaSql.PS' {
            # -Debug would set DebugPreference to Inquire on Windows PowerShell 5.1 and prompt.
            $DebugPreference = 'Continue'
            $Output = Write-OmadaSqlLog -Message 'debug detail' -Level Debug 5>&1
            $Output.Message | Should -Be '[OmadaSql.PS] debug detail'
        }
    }
}
