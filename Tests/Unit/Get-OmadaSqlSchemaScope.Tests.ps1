param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaSql.PS\OmadaSql.PS.psm1')
)

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers\OmadaSqlTestHelper.ps1')
    Import-OmadaWebStub
    Get-Module -Name OmadaSql.PS -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Get-OmadaSqlSchemaScope' -Tag 'Unit' {
    It 'Finds <Expected> for <Case>' -ForEach @(Get-OmadaSqlTestSchemaCase) {
        @(Find-OmadaSqlTestSchemaFinding -Sql $Sql) | Should -Be $Expected
    }

    It 'Opens one scope per query specification, own sources first, with aliases and columns' {
        $Statement = @(Get-OmadaSqlTestStatement -Sql 'SELECT [Label] = p.DisplayName FROM dbo.Person AS p WHERE EXISTS (SELECT [x] = 1 FROM dbo.Contract WHERE PersonId = p.Id)')
        $Scope = & (Get-Module -Name 'OmadaSql.PS') {
            param($Statement, $Data)
            $Model = ConvertTo-OmadaSqlSchemaModel -Data $Data -DataConnection ([pscustomobject]@{ Name = 'OISES'; Id = 1 })
            Get-OmadaSqlSchemaScope -Fragment $Statement[0].Fragment -Model $Model -ScriptName @{}
        } $Statement (Get-OmadaSqlTestSchemaData)
        $Scope.Count | Should -Be 2
        $Scope[0].Level.Count | Should -Be 1
        @($Scope[0].Level[0].Name) | Should -Be @('p')
        $Scope[0].Level[0][0].Entry.Name | Should -Be 'dbo.Person'
        $Scope[0].Level[0][0].Opaque | Should -BeFalse
        @($Scope[0].Alias.Keys) | Should -Be @('Label')
        $Scope[0].Column.Count | Should -Be 1
        $Scope[1].Level.Count | Should -Be 2
        @($Scope[1].Level[0].Name) | Should -Be @('Contract')
        @($Scope[1].Level[1].Name) | Should -Be @('p')
        $Scope[1].Column.Count | Should -Be 2
    }

    It 'Marks a source the schema cannot resolve as opaque, named by its alias' {
        $Statement = @(Get-OmadaSqlTestStatement -Sql 'SELECT [a] = 1 FROM (SELECT [x] = 1) AS d JOIN dbo.Nope ON 1 = 1 JOIN Event AS e ON 1 = 1')
        $Source = & (Get-Module -Name 'OmadaSql.PS') {
            param($Statement, $Data)
            $Model = ConvertTo-OmadaSqlSchemaModel -Data $Data -DataConnection ([pscustomobject]@{ Name = 'OISES'; Id = 1 })
            (Get-OmadaSqlSchemaScope -Fragment $Statement[0].Fragment -Model $Model -ScriptName @{})[0].Level[0]
        } $Statement (Get-OmadaSqlTestSchemaData)
        @($Source.Name) | Should -Be @('d', 'Nope', 'e')
        @($Source.Opaque) | Should -Be @($true, $true, $true)
    }

    It 'Has no scope for a statement without a query specification' {
        $Statement = @(Get-OmadaSqlTestStatement -Sql 'DECLARE @x int')
        $Scope = & (Get-Module -Name 'OmadaSql.PS') {
            param($Statement)
            @(Get-OmadaSqlSchemaScope -Fragment $Statement[0].Fragment -Model @{ Table = @{}; ByName = @{}; Column = @{} } -ScriptName @{})
        } $Statement
        $Scope.Count | Should -Be 0
    }
}

Describe 'Test-OmadaSqlSchemaLookup' -Tag 'Unit' {
    It 'Returns <Expected> for <Case>' -ForEach @(
        @{ Case = 'no part'; Identifier = @(); Expected = $false }
        @{ Case = 'one part'; Identifier = @('T'); Expected = $true }
        @{ Case = 'three parts'; Identifier = @('db', 'dbo', 'T'); Expected = $true }
        @{ Case = 'four parts'; Identifier = @('srv', 'db', 'dbo', 'T'); Expected = $false }
        @{ Case = 'a temporary table'; Identifier = @('#T'); Expected = $false }
        @{ Case = 'a qualified temporary table'; Identifier = @('dbo', '#T'); Expected = $false }
        @{ Case = 'a table variable'; Identifier = @('@T'); Expected = $false }
        @{ Case = 'a name the script defines'; Identifier = @('cte'); Expected = $false }
        @{ Case = 'a script name with a schema'; Identifier = @('dbo', 'cte'); Expected = $true }
    ) {
        $Result = & (Get-Module -Name 'OmadaSql.PS') { param($Identifier) Test-OmadaSqlSchemaLookup -Identifier $Identifier -ScriptName @{ CTE = $true } } $Identifier
        $Result | Should -Be $Expected
    }
}

Describe 'Get-OmadaSqlSchemaScope parameter contract' -Tag 'Unit' {
    # Parameter declarations run no code a test could observe, so the mutation gate's mutants of
    # Mandatory, Position, pipeline binding and ValidateRange are caught only by asserting the contract.
    It '<Command> -<Parameter> <ParameterSet>' -ForEach @(
        @{ Command = 'Get-OmadaSqlSchemaScope'; Parameter = 'Fragment'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Get-OmadaSqlSchemaScope'; Parameter = 'Model'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Get-OmadaSqlSchemaScope'; Parameter = 'ScriptName'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Add-OmadaSqlSchemaScopeNode'; Parameter = 'Node'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Add-OmadaSqlSchemaScopeNode'; Parameter = 'Level'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Add-OmadaSqlSchemaScopeNode'; Parameter = 'State'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Test-OmadaSqlSchemaColumnReference'; Parameter = 'Node'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Test-OmadaSqlSchemaColumnReference'; Parameter = 'State'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Add-OmadaSqlDatePartIgnore'; Parameter = 'Node'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Add-OmadaSqlDatePartIgnore'; Parameter = 'State'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'New-OmadaSqlSchemaScope'; Parameter = 'Specification'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'New-OmadaSqlSchemaScope'; Parameter = 'Enclosing'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'New-OmadaSqlSchemaScope'; Parameter = 'State'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Get-OmadaSqlScopeSource'; Parameter = 'Specification'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Get-OmadaSqlScopeSource'; Parameter = 'Model'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Get-OmadaSqlScopeSource'; Parameter = 'ScriptName'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Get-OmadaSqlTableReferenceLeaf'; Parameter = 'Reference'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Resolve-OmadaSqlSchemaReference'; Parameter = 'Reference'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Resolve-OmadaSqlSchemaReference'; Parameter = 'Model'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Resolve-OmadaSqlSchemaReference'; Parameter = 'ScriptName'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Test-OmadaSqlSchemaLookup'; Parameter = 'Identifier'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Test-OmadaSqlSchemaLookup'; Parameter = 'ScriptName'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
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
