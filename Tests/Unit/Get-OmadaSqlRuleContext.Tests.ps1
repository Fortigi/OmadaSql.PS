param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaSql.PS\OmadaSql.PS.psm1')
)

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers\OmadaSqlTestHelper.ps1')
    Import-OmadaWebStub
    Get-Module -Name OmadaSql.PS -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Get-OmadaSqlRuleContext' -Tag 'Unit' {
    BeforeAll {
        function Get-TestRuleContext {
            param([string]$Sql)
            & (Get-Module -Name 'OmadaSql.PS') {
                param($Text)
                $Parsed = ConvertTo-OmadaSqlScriptFragment -Sql $Text
                Get-OmadaSqlRuleContext -Fragment $Parsed.Fragment -Statement @(Split-OmadaSqlStatement -Fragment $Parsed.Fragment -Sql $Text)
            } $Sql
        }
    }

    It 'Takes the result columns of a UNION from its first branch' {
        $Context = Get-TestRuleContext -Sql 'SELECT [a] = 1 UNION SELECT 2'
        @($Context.ResultQuerySpecification).Count | Should -Be 1
        $Context.ResultQuerySpecification[0].SelectElements[0].ColumnName.Value | Should -Be 'a'
    }

    It 'Unwraps a parenthesised query' {
        $Context = Get-TestRuleContext -Sql '(SELECT [a] = 1)'
        @($Context.ResultQuerySpecification).Count | Should -Be 1
    }

    It 'Counts only top-level SELECT statements as results, not a SELECT INTO or one inside IF' {
        $Context = Get-TestRuleContext -Sql "SELECT [a] = 1;`nSELECT [b] = 2 INTO dbo.x;`nIF 1 = 1 SELECT [c] = 3"
        @($Context.ResultQuerySpecification).Count | Should -Be 1
        @($Context.TopStatement).Count | Should -Be 3
    }

    It 'Lists every statement node, also one nested in a block' {
        $Context = Get-TestRuleContext -Sql "IF 1 = 1`nBEGIN`n  UPDATE dbo.t SET a = 1`nEND"
        @($Context.Statement | ForEach-Object { $_.GetType().Name }) | Should -Contain 'UpdateStatement'
    }

    It 'Lists the scopes that must name every column: <Case>' -ForEach @(
        @{ Case = 'a derived table'; Sql = 'SELECT [a] = d.x FROM (SELECT 1) AS d'; Description = 'derived table' }
        @{ Case = 'a CTE without a column list'; Sql = 'WITH c AS (SELECT 1) SELECT [a] = 1 FROM c'; Description = 'common table expression' }
        @{ Case = 'a SELECT INTO'; Sql = 'SELECT 1 INTO dbo.x'; Description = 'SELECT ... INTO' }
    ) {
        $Context = Get-TestRuleContext -Sql $Sql
        @($Context.NamedScope.Description) | Should -Be @($Description)
        $Context.NamedScope[0].QuerySpecification.GetType().Name | Should -Be 'QuerySpecification'
    }

    It 'Leaves out a CTE that names its columns in a column list' {
        $Context = Get-TestRuleContext -Sql 'WITH c (x) AS (SELECT 1) SELECT [a] = 1 FROM c'
        @($Context.NamedScope).Count | Should -Be 0
    }
}

Describe 'Get-OmadaSqlResultQuerySpecification' -Tag 'Unit' {
    It 'Returns $null for no expression' {
        InModuleScope 'OmadaSql.PS' {
            Get-OmadaSqlResultQuerySpecification -QueryExpression $null | Should -BeNullOrEmpty
        }
    }

    It 'Returns $null for an expression that is not a query' {
        InModuleScope 'OmadaSql.PS' {
            Get-OmadaSqlResultQuerySpecification -QueryExpression ([pscustomobject]@{ Name = 'x' }) | Should -BeNullOrEmpty
        }
    }
}

Describe 'Get-OmadaSqlRuleContext parameter contract' -Tag 'Unit' {
    # Parameter declarations run no code a test could observe, so the mutation gate's mutants of
    # Mandatory, Position, pipeline binding and ValidateRange are caught only by asserting the contract.
    It '<Command> -<Parameter> <ParameterSet>' -ForEach @(
        @{ Command = 'Get-OmadaSqlRuleContext'; Parameter = 'Fragment'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Get-OmadaSqlRuleContext'; Parameter = 'Statement'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Get-OmadaSqlResultQuerySpecification'; Parameter = 'QueryExpression'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Get-OmadaSqlResultScope'; Parameter = 'Statement'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Get-OmadaSqlNamedScope'; Parameter = 'Fragment'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
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
