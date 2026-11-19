param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaSql.PS\OmadaSql.PS.psm1')
)

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers\OmadaSqlTestHelper.ps1')
    Import-OmadaWebStub
    Get-Module -Name OmadaSql.PS -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Get-OmadaSqlFragmentDescendant' -Tag 'Unit' {
    BeforeAll {
        $Script:Fragment = & (Get-Module -Name 'OmadaSql.PS') { (ConvertTo-OmadaSqlScriptFragment -Sql 'SELECT a FROM t; SELECT b FROM u WHERE c = 1').Fragment }
    }

    It 'Returns the matching fragments in document order' {
        InModuleScope 'OmadaSql.PS' -Parameters @{ Fragment = $Script:Fragment } {
            param($Fragment)
            $Column = @(Get-OmadaSqlFragmentDescendant -Fragment $Fragment -TypeName 'ColumnReferenceExpression')
            @($Column | ForEach-Object { $_.MultiPartIdentifier.Identifiers[0].Value }) | Should -Be @('a', 'b', 'c')
        }
    }

    It 'Filters on several type names at once' {
        InModuleScope 'OmadaSql.PS' -Parameters @{ Fragment = $Script:Fragment } {
            param($Fragment)
            @(Get-OmadaSqlFragmentDescendant -Fragment $Fragment -TypeName 'SelectStatement', 'IntegerLiteral').Count | Should -Be 3
        }
    }

    It 'Leaves the fragment itself out unless -IncludeSelf' {
        InModuleScope 'OmadaSql.PS' -Parameters @{ Fragment = $Script:Fragment } {
            param($Fragment)
            $All = @(Get-OmadaSqlFragmentDescendant -Fragment $Fragment)
            $WithSelf = @(Get-OmadaSqlFragmentDescendant -Fragment $Fragment -IncludeSelf)
            $All | Should -Not -Contain $Fragment
            [object]::ReferenceEquals($WithSelf[0], $Fragment) | Should -BeTrue
            $WithSelf.Count | Should -Be ($All.Count + 1)
            @(Get-OmadaSqlFragmentDescendant -Fragment $Fragment -TypeName 'TSqlScript' -IncludeSelf).Count | Should -Be 1
        }
    }

    It 'Returns every fragment once' {
        InModuleScope 'OmadaSql.PS' -Parameters @{ Fragment = $Script:Fragment } {
            param($Fragment)
            $All = @(Get-OmadaSqlFragmentDescendant -Fragment $Fragment)
            $Unique = [System.Collections.Generic.HashSet[object]]::new()
            foreach ($Item in $All) { $null = $Unique.Add($Item) }
            $Unique.Count | Should -Be $All.Count
        }
    }

    It 'Returns nothing for a null fragment' {
        InModuleScope 'OmadaSql.PS' {
            @(Get-OmadaSqlFragmentDescendant -Fragment $null).Count | Should -Be 0
        }
    }
}

Describe 'Get-OmadaSqlFragmentChildProperty' -Tag 'Unit' {
    BeforeAll {
        $null = & (Get-Module -Name 'OmadaSql.PS') { Import-OmadaSqlScriptDom }
    }

    It 'Lists the properties that can hold a fragment, without the token stream' {
        InModuleScope 'OmadaSql.PS' {
            # The function returns its array as one object; the parentheses unroll it.
            $Name = @((Get-OmadaSqlFragmentChildProperty -Type ([Microsoft.SqlServer.TransactSql.ScriptDom.TSqlScript])) | ForEach-Object { $_.Name })
            $Name | Should -Contain 'Batches'
            $Name | Should -Not -Contain 'ScriptTokenStream'
            $Name | Should -Not -Contain 'StartOffset'
        }
    }

    It 'Leaves out string properties although a string is a collection of characters' {
        InModuleScope 'OmadaSql.PS' {
            # The function returns its array as one object; the parentheses unroll it.
            $Name = @((Get-OmadaSqlFragmentChildProperty -Type ([Microsoft.SqlServer.TransactSql.ScriptDom.Identifier])) | ForEach-Object { $_.Name })
            $Name | Should -Not -Contain 'Value'
        }
    }

    It 'Resolves a type once and then returns the remembered list' {
        InModuleScope 'OmadaSql.PS' {
            $First = Get-OmadaSqlFragmentChildProperty -Type ([Microsoft.SqlServer.TransactSql.ScriptDom.TSqlBatch])
            $Second = Get-OmadaSqlFragmentChildProperty -Type ([Microsoft.SqlServer.TransactSql.ScriptDom.TSqlBatch])
            [object]::ReferenceEquals($First, $Second) | Should -BeTrue
            $First.GetType() | Should -Be ([System.Reflection.PropertyInfo[]])
        }
    }
}

Describe 'Get-OmadaSqlFragmentDescendant parameter contract' -Tag 'Unit' {
    # Parameter declarations run no code a test could observe, so the mutation gate's mutants of
    # Mandatory, Position, pipeline binding and ValidateRange are caught only by asserting the contract.
    It '<Command> -<Parameter> <ParameterSet>' -ForEach @(
        @{ Command = 'Get-OmadaSqlFragmentDescendant'; Parameter = 'Fragment'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Get-OmadaSqlFragmentChild'; Parameter = 'Fragment'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Get-OmadaSqlFragmentChildProperty'; Parameter = 'Type'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
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
