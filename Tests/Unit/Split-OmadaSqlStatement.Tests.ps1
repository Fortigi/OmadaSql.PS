param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaSql.PS\OmadaSql.PS.psm1')
)

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers\OmadaSqlTestHelper.ps1')
    Import-OmadaWebStub
    Get-Module -Name OmadaSql.PS -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Split-OmadaSqlStatement' -Tag 'Unit' {
    It 'Returns every top-level statement with its own text, line and offset' {
        $Sql = "SELECT 1 AS a;`nSELECT 'x;y' AS b`nGO`nSELECT 3 AS c"
        $Statement = @(Get-OmadaSqlTestStatement -Sql $Sql)
        $Statement.Count | Should -Be 3
        @($Statement.Ordinal) | Should -Be @(1, 2, 3)
        @($Statement.Line) | Should -Be @(1, 2, 4)
        $Statement[0].Text | Should -Be 'SELECT 1 AS a;'
        $Statement[1].Text | Should -Be "SELECT 'x;y' AS b"
        $Statement[2].Text | Should -Be 'SELECT 3 AS c'
        $Statement[2].StartOffset | Should -Be $Sql.IndexOf('SELECT 3')
        $Statement[0].Fragment.GetType().Name | Should -Be 'SelectStatement'
        $Statement[0].PSObject.TypeNames | Should -Contain 'OmadaSql.Statement'
    }

    It 'Keeps a statement inside a block as one statement' {
        $Statement = @(Get-OmadaSqlTestStatement -Sql "IF 1 = 1`nBEGIN`n  SELECT 1 AS a`nEND")
        $Statement.Count | Should -Be 1
        $Statement[0].Fragment.GetType().Name | Should -Be 'IfStatement'
    }

    It 'Returns nothing for an empty script or a missing tree' {
        @(Get-OmadaSqlTestStatement -Sql '').Count | Should -Be 0
        InModuleScope 'OmadaSql.PS' {
            @(Split-OmadaSqlStatement -Fragment $null -Sql 'SELECT 1').Count | Should -Be 0
        }
    }
}

Describe 'Split-OmadaSqlStatement parameter contract' -Tag 'Unit' {
    # Parameter declarations run no code a test could observe, so the mutation gate's mutants of
    # Mandatory, Position, pipeline binding and ValidateRange are caught only by asserting the contract.
    It '<Command> -<Parameter> <ParameterSet>' -ForEach @(
        @{ Command = 'Split-OmadaSqlStatement'; Parameter = 'Fragment'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Split-OmadaSqlStatement'; Parameter = 'Sql'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
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
