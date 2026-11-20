param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaSql.PS\OmadaSql.PS.psm1')
)

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers\OmadaSqlTestHelper.ps1')
    Import-OmadaWebStub
    Get-Module -Name OmadaSql.PS -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Get-OmadaSqlExportFormat' -Tag 'Unit' {
    BeforeEach {
        InModuleScope 'OmadaSql.PS' { $Script:OmadaSqlExportFormat = $null }
    }

    It 'Lists every format, sorted by name' {
        @(Get-OmadaSqlExportFormat).Name | Should -Be @('Csv', 'Json', 'PowerShellArray', 'SqlArray', 'Text', 'Xml')
    }

    It 'Filters by name with wildcards, by position' {
        @(Get-OmadaSqlExportFormat '*Array').Name | Should -Be @('PowerShellArray', 'SqlArray')
        @(Get-OmadaSqlExportFormat -Name 'json').Name | Should -Be @('Json')
    }

    It 'Lists a registered format' {
        Register-OmadaSqlExportFormat -Name 'Markdown' -ScriptBlock { 'x' }
        @(Get-OmadaSqlExportFormat -Name 'M*').Name | Should -Be @('Markdown')
    }
}

Describe 'Get-OmadaSqlExportFormat parameter contract' -Tag 'Unit' {
    # Parameter declarations run no code a test could observe, so the mutation gate's mutants of
    # Mandatory, Position, pipeline binding and ValidateRange are caught only by asserting the contract.
    It '<Command> -<Parameter> <ParameterSet>' -ForEach @(
        @{ Command = 'Get-OmadaSqlExportFormat'; Parameter = 'Name'; ParameterSet = ''; Mandatory = $false; Position = 0; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
    ) {
        $Contract = Get-OmadaSqlParameterContract -CommandName $Command -ParameterName $Parameter -ParameterSetName $ParameterSet
        $Contract.Mandatory | Should -Be $Mandatory
        if ($null -ne $Position) {
            $Contract.Position | Should -Be $Position
        }
        $Contract.ValueFromPipeline | Should -Be $ValueFromPipeline
        $Contract.ValueFromPipelineByPropertyName | Should -Be $ValueFromPipelineByPropertyName
        $Contract.RangeMin | Should -Be $RangeMin
        $Contract.RangeMax | Should -Be $RangeMax
    }
}
