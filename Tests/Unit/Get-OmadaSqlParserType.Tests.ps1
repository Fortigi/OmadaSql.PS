param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaSql.PS\OmadaSql.PS.psm1')
)

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers\OmadaSqlTestHelper.ps1')
    Import-OmadaWebStub
    Get-Module -Name OmadaSql.PS -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Select-OmadaSqlNewestParserType' -Tag 'Unit' {
    BeforeAll {
        if (-not ('OmadaSqlPSParserTests.TSql90Parser' -as [type])) {
            Add-Type -TypeDefinition @'
namespace OmadaSqlPSParserTests
{
    public class TSql90Parser { }
    public class TSql170Parser { }
    public class TSql160Parser { }
    public class TSql170ParserHelper { }
    public class Unrelated { }
}
'@
        }
        $Script:Types = @([OmadaSqlPSParserTests.TSql90Parser], [OmadaSqlPSParserTests.TSql170Parser], [OmadaSqlPSParserTests.TSql160Parser], [OmadaSqlPSParserTests.TSql170ParserHelper], [OmadaSqlPSParserTests.Unrelated])
    }

    It 'Returns the parser with the highest number, compared as a number' {
        InModuleScope 'OmadaSql.PS' -Parameters @{ Types = $Script:Types } {
            param($Types)
            (Select-OmadaSqlNewestParserType -Type $Types).Name | Should -Be 'TSql170Parser'
        }
    }

    It 'Returns the only parser when there is one' {
        InModuleScope 'OmadaSql.PS' {
            (Select-OmadaSqlNewestParserType -Type @([OmadaSqlPSParserTests.TSql90Parser], [OmadaSqlPSParserTests.Unrelated])).Name | Should -Be 'TSql90Parser'
        }
    }

    It 'Returns $null when there is no parser among the types' {
        InModuleScope 'OmadaSql.PS' {
            Select-OmadaSqlNewestParserType -Type @([OmadaSqlPSParserTests.Unrelated]) | Should -BeNullOrEmpty
            Select-OmadaSqlNewestParserType -Type @() | Should -BeNullOrEmpty
        }
    }
}

Describe 'Get-OmadaSqlParserType' -Tag 'Unit' {
    AfterEach {
        InModuleScope 'OmadaSql.PS' { $Script:OmadaSqlParserType = $null }
    }

    It 'Returns the newest TSqlNNNParser of the bundled parser' {
        InModuleScope 'OmadaSql.PS' {
            $Type = Get-OmadaSqlParserType
            $Type.Name | Should -Match '^TSql\d+Parser$'
            $Type.Assembly.GetName().Name | Should -Be 'Microsoft.SqlServer.TransactSql.ScriptDom'
        }
    }

    It 'Resolves the parser once and then returns the remembered one' {
        InModuleScope 'OmadaSql.PS' {
            $Script:OmadaSqlParserType = [int]
            Mock Import-OmadaSqlScriptDom { throw 'must not be called' }
            Get-OmadaSqlParserType | Should -Be ([int])
        }
    }

    It 'Fails with ParserUnavailable when the assembly has no parser' {
        InModuleScope 'OmadaSql.PS' {
            Mock Import-OmadaSqlScriptDom { [int].Assembly }
            { Get-OmadaSqlParserType } | Should -Throw -ErrorId 'OmadaSql.ParserUnavailable'
        }
    }
}

Describe 'Get-OmadaSqlParserType parameter contract' -Tag 'Unit' {
    # Parameter declarations run no code a test could observe, so the mutation gate's mutants of
    # Mandatory, Position, pipeline binding and ValidateRange are caught only by asserting the contract.
    It '<Command> -<Parameter> <ParameterSet>' -ForEach @(
        @{ Command = 'Select-OmadaSqlNewestParserType'; Parameter = 'Type'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
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
