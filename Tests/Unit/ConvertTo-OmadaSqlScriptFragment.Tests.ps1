param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaSql.PS\OmadaSql.PS.psm1')
)

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers\OmadaSqlTestHelper.ps1')
    Import-OmadaWebStub
    Get-Module -Name OmadaSql.PS -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'ConvertTo-OmadaSqlScriptFragment' -Tag 'Unit' {
    It 'Returns the tree, no errors and the parser for a valid script' {
        InModuleScope 'OmadaSql.PS' {
            $Parsed = ConvertTo-OmadaSqlScriptFragment -Sql 'SELECT [Id] = Id FROM dbo.tblDataObject'
            $Parsed.Fragment.GetType().Name | Should -Be 'TSqlScript'
            @($Parsed.ParseError).Count | Should -Be 0
            $Parsed.ParserVersion | Should -Be (Get-OmadaSqlParserType).Name
        }
    }

    It 'Returns the parse errors with their position for an invalid script' {
        InModuleScope 'OmadaSql.PS' {
            $Parsed = ConvertTo-OmadaSqlScriptFragment -Sql "SELECT 1 AS a`nSELEC 2"
            @($Parsed.ParseError).Count | Should -BeGreaterThan 0
            $Parsed.ParseError[0].Line | Should -Be 2
            $Parsed.ParseError[0].Number | Should -BeGreaterThan 0
        }
    }

    It 'Reads double quotes as an identifier, as QUOTED_IDENTIFIER ON does' {
        InModuleScope 'OmadaSql.PS' {
            $Parsed = ConvertTo-OmadaSqlScriptFragment -Sql 'SELECT "Name" FROM dbo.t'
            @(Get-OmadaSqlFragmentDescendant -Fragment $Parsed.Fragment -TypeName 'ColumnReferenceExpression').Count | Should -Be 1
            @(Get-OmadaSqlFragmentDescendant -Fragment $Parsed.Fragment -TypeName 'StringLiteral').Count | Should -Be 0
        }
    }

    It 'Parses an empty script without errors' {
        InModuleScope 'OmadaSql.PS' {
            $Parsed = ConvertTo-OmadaSqlScriptFragment -Sql ''
            @($Parsed.ParseError).Count | Should -Be 0
            @($Parsed.Fragment.Batches).Count | Should -Be 0
        }
    }
}

Describe 'ConvertTo-OmadaSqlScriptFragment parameter contract' -Tag 'Unit' {
    # Parameter declarations run no code a test could observe, so the mutation gate's mutants of
    # Mandatory, Position, pipeline binding and ValidateRange are caught only by asserting the contract.
    It '<Command> -<Parameter> <ParameterSet>' -ForEach @(
        @{ Command = 'ConvertTo-OmadaSqlScriptFragment'; Parameter = 'Sql'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
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
