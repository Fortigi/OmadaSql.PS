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

Describe 'Write-OmadaSqlLog parameter contract' -Tag 'Unit' {
    # Parameter declarations run no code a test could observe, so the mutation gate's mutants of
    # Mandatory, Position, pipeline binding and ValidateRange are caught only by asserting the contract.
    It '<Command> -<Parameter> <ParameterSet>' -ForEach @(
        @{ Command = 'Write-OmadaSqlLog'; Parameter = 'Message'; ParameterSet = ''; Mandatory = $true; Position = 0; ValueFromPipeline = $true; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
    ) {
        $Contract = Get-OmadaSqlParameterContract -CommandName $Command -ParameterName $Parameter -ParameterSetName $ParameterSet
        $Contract.Mandatory | Should -Be $Mandatory
        $Contract.Position | Should -Be $Position
        $Contract.ValueFromPipeline | Should -Be $ValueFromPipeline
        $Contract.ValueFromPipelineByPropertyName | Should -Be $ValueFromPipelineByPropertyName
        $Contract.RangeMin | Should -Be $RangeMin
        $Contract.RangeMax | Should -Be $RangeMax
    }
}
