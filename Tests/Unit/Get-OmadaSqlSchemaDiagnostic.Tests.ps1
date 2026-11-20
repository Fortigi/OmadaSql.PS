param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaSql.PS\OmadaSql.PS.psm1')
)

BeforeDiscovery {
    # The case table feeds -ForEach, which Pester evaluates during discovery, before BeforeAll.
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers\OmadaSqlTestHelper.ps1')
}

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers\OmadaSqlTestHelper.ps1')
    Import-OmadaWebStub
    Get-Module -Name OmadaSql.PS -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Get-OmadaSqlSchemaRule' -Tag 'Unit' {
    It 'Lists OMD030 to OMD032, all Info so they never block' {
        $Rule = @(InModuleScope 'OmadaSql.PS' { Get-OmadaSqlSchemaRule })
        @($Rule.Id) | Should -Be @('OMD030', 'OMD031', 'OMD032')
        @($Rule.Severity | Select-Object -Unique) | Should -Be @('Info')
        @($Rule.Title) | Should -Be @('Table or view not in the schema', 'Column not in the schema', 'Ambiguous column')
    }
}

Describe 'Find-OmadaSqlSchemaFinding' -Tag 'Unit' {
    It 'Finds <Expected> for <Case>' -ForEach @(Get-OmadaSqlTestSchemaCase) {
        @(Find-OmadaSqlTestSchemaFinding -Sql $Sql) | Should -Be $Expected
    }

    It 'Words the findings with the name, the table and the data connection' {
        $Statement = @(Get-OmadaSqlTestStatement -Sql 'SELECT [a] = p.Nope, [b] = Missing, [c] = Id FROM dbo.Person AS p JOIN dbo.Contract AS c ON c.PersonId = p.Id JOIN dbo.Gone AS g ON 1 = 1')
        $Statement2 = @(Get-OmadaSqlTestStatement -Sql 'SELECT [a] = p.Nope, [b] = Missing, [c] = Id FROM dbo.Person AS p JOIN dbo.Contract AS c ON c.PersonId = p.Id')
        $Message = & (Get-Module -Name 'OmadaSql.PS') {
            param($One, $Two, $Data)
            $Model = ConvertTo-OmadaSqlSchemaModel -Data $Data -DataConnection ([pscustomobject]@{ Name = 'OISES'; Id = 1 })
            @(Find-OmadaSqlSchemaFinding -Fragment $One[0].Fragment -Model $Model -ScriptName @{}) | ForEach-Object { $_.Message }
            @(Find-OmadaSqlSchemaFinding -Fragment $Two[0].Fragment -Model $Model -ScriptName @{}) | ForEach-Object { $_.Message }
        } $Statement $Statement2 (Get-OmadaSqlTestSchemaData)
        $Message | Should -Be @(
            "'dbo.Gone' is not in the schema of data connection 'OISES'. Check the name, or read the schema again with Get-OmadaSqlSchema -Force if the database changed."
            "Column 'Nope' is not on 'dbo.Person' in the schema of data connection 'OISES'. Check the name, or read the schema again with Get-OmadaSqlSchema -Force if the database changed."
            "Column 'Missing' is not on any table of this query in the schema of data connection 'OISES'. Check the name, or read the schema again with Get-OmadaSqlSchema -Force if the database changed."
            "Column 'Id' is ambiguous: 2 tables in this query have a column with that name (p, c). Qualify it with a table name or alias."
        )
    }
}

Describe 'Get-OmadaSqlScriptDefinedName' -Tag 'Unit' {
    It 'Collects CTE names, SELECT INTO targets and CREATE TABLE names from every statement' {
        $Statement = @(Get-OmadaSqlTestStatement -Sql "WITH Recent AS (SELECT [a] = 1) SELECT [a] = 1 FROM Recent;`nSELECT [b] = 1 INTO dbo.Staging FROM dbo.Person;`nCREATE TABLE Scratch (Id int);`nSELECT [c] = 1 FROM dbo.Person")
        $Name = & (Get-Module -Name 'OmadaSql.PS') { param($Statement) Get-OmadaSqlScriptDefinedName -Statement $Statement } $Statement
        @($Name.Keys | Sort-Object) | Should -Be @('Recent', 'Scratch', 'Staging')
        $Name.ContainsKey('recent') | Should -BeTrue
    }

    It 'Returns an empty table for a script that defines none' {
        $Statement = @(Get-OmadaSqlTestStatement -Sql 'SELECT [a] = 1')
        $Name = & (Get-Module -Name 'OmadaSql.PS') { param($Statement) Get-OmadaSqlScriptDefinedName -Statement $Statement } $Statement
        $Name.Count | Should -Be 0
    }
}

Describe 'Get-OmadaSqlSchemaDiagnostic' -Tag 'Unit' {
    BeforeEach {
        $Script:Connection = Initialize-OmadaSqlTestConnection
        Mock Get-OmadaSqlDataConnectionList -ModuleName 'OmadaSql.PS' {
            [pscustomobject]@{ Name = 'OISES'; Id = 1001 }
            [pscustomobject]@{ Name = 'ODW'; Id = 1002 }
        }
        Mock Get-OmadaSqlSchemaData -ModuleName 'OmadaSql.PS' -ParameterFilter { $DataConnectionId -eq 1001 } { [pscustomobject]@{ 'dbo.Person' = @('Id int') } }
        Mock Get-OmadaSqlSchemaData -ModuleName 'OmadaSql.PS' -ParameterFilter { $DataConnectionId -eq 1002 } { [pscustomobject]@{ 'dbo.Fact' = @('Id int') } }
    }

    It 'Checks each statement against the schema of its own data connection' {
        $Statement = @(Get-OmadaSqlTestStatement -Sql "SELECT [a] = Nope FROM dbo.Person;`nSELECT [b] = 1 FROM ODW.dbo.Person;`nSELECT [c] = Id FROM ODW.dbo.Fact")
        $Diagnostic = @(InModuleScope 'OmadaSql.PS' -Parameters @{ Statement = $Statement } {
                param($Statement)
                Get-OmadaSqlSchemaDiagnostic -Context (Get-OmadaSqlConnectionContext) -Statement $Statement -Diagnostic @() -DataConnection 'OISES'
            })
        @($Diagnostic.RuleId) | Should -Be @('OMD031', 'OMD030')
        @($Diagnostic.Line) | Should -Be @(1, 2)
        @($Diagnostic.Column) | Should -Be @(14, 21)
        @($Diagnostic.Severity | Select-Object -Unique) | Should -Be @('Info')
        @($Diagnostic.Blocking | Select-Object -Unique) | Should -Be @($false)
        @($Diagnostic.Source | Select-Object -Unique) | Should -Be @('Schema')
        $Diagnostic[0].PSObject.TypeNames[0] | Should -Be 'OmadaSql.Diagnostic'
        $Diagnostic[1].Message | Should -BeLike "*data connection 'ODW'*"
        Should -Invoke Get-OmadaSqlSchemaData -ModuleName 'OmadaSql.PS' -Times 1 -Exactly -ParameterFilter { $DataConnectionId -eq 1001 }
        Should -Invoke Get-OmadaSqlSchemaData -ModuleName 'OmadaSql.PS' -Times 1 -Exactly -ParameterFilter { $DataConnectionId -eq 1002 }
    }

    It 'Leaves a statement without a data connection unchecked' {
        $Statement = @(Get-OmadaSqlTestStatement -Sql "SELECT [a] = Nope FROM dbo.Person;`nSELECT [b] = Nope FROM OISES.dbo.Person")
        $Diagnostic = @(InModuleScope 'OmadaSql.PS' -Parameters @{ Statement = $Statement } {
                param($Statement)
                Get-OmadaSqlSchemaDiagnostic -Context (Get-OmadaSqlConnectionContext) -Statement $Statement -Diagnostic @()
            })
        @($Diagnostic.Line) | Should -Be @(2)
    }

    It 'Uses the severity -RuleSeverity sets, and skips a rule that is Off' {
        $Statement = @(Get-OmadaSqlTestStatement -Sql 'SELECT [a] = Nope FROM dbo.Gone')
        $Statement2 = @(Get-OmadaSqlTestStatement -Sql 'SELECT [a] = Nope FROM dbo.Person')
        $Diagnostic = @(InModuleScope 'OmadaSql.PS' -Parameters @{ One = $Statement; Two = $Statement2 } {
                param($One, $Two)
                $Context = Get-OmadaSqlConnectionContext
                Get-OmadaSqlSchemaDiagnostic -Context $Context -Statement $One -Diagnostic @() -DataConnection 'OISES' -RuleSeverity @{ OMD030 = 'Warning' }
                Get-OmadaSqlSchemaDiagnostic -Context $Context -Statement $Two -Diagnostic @() -DataConnection 'OISES' -RuleSeverity @{ OMD031 = 'Off' }
            })
        $Diagnostic.Count | Should -Be 1
        $Diagnostic[0].RuleId | Should -Be 'OMD030'
        $Diagnostic[0].Severity | Should -Be 'Warning'
        $Diagnostic[0].Blocking | Should -BeTrue
    }

    It 'Reads no schema when every schema rule is Off' {
        $Statement = @(Get-OmadaSqlTestStatement -Sql 'SELECT [a] = Nope FROM dbo.Gone')
        $Diagnostic = @(InModuleScope 'OmadaSql.PS' -Parameters @{ Statement = $Statement } {
                param($Statement)
                Get-OmadaSqlSchemaDiagnostic -Context (Get-OmadaSqlConnectionContext) -Statement $Statement -Diagnostic @() -DataConnection 'OISES' -RuleSeverity @{ OMD030 = 'Off'; OMD031 = 'Off'; OMD032 = 'Off' }
            })
        $Diagnostic.Count | Should -Be 0
        Should -Invoke Get-OmadaSqlSchemaData -ModuleName 'OmadaSql.PS' -Times 0 -Exactly
    }

    It 'Runs while only some schema rules are Off' {
        $Statement = @(Get-OmadaSqlTestStatement -Sql 'SELECT [a] = 1 FROM dbo.Gone')
        $Diagnostic = @(InModuleScope 'OmadaSql.PS' -Parameters @{ Statement = $Statement } {
                param($Statement)
                Get-OmadaSqlSchemaDiagnostic -Context (Get-OmadaSqlConnectionContext) -Statement $Statement -Diagnostic @() -DataConnection 'OISES' -RuleSeverity @{ OMD031 = 'Off'; OMD032 = 'Off' }
            })
        @($Diagnostic.RuleId) | Should -Be @('OMD030')
    }

    It 'Skips a script with a <Case>' -ForEach @(
        @{ Case = 'syntax error'; RuleId = 'SQL46010'; Source = 'T-SQL syntax' }
        @{ Case = 'four-part name'; RuleId = 'OMD020'; Source = 'Omada compatibility' }
        @{ Case = 'second database'; RuleId = 'OMD021'; Source = 'Omada compatibility' }
    ) {
        $Statement = @(Get-OmadaSqlTestStatement -Sql 'SELECT [a] = Nope FROM dbo.Gone')
        $Found = [pscustomobject]@{ RuleId = $RuleId; Source = $Source }
        $Diagnostic = @(InModuleScope 'OmadaSql.PS' -Parameters @{ Statement = $Statement; Found = $Found } {
                param($Statement, $Found)
                Get-OmadaSqlSchemaDiagnostic -Context (Get-OmadaSqlConnectionContext) -Statement $Statement -Diagnostic @($Found) -DataConnection 'OISES'
            })
        $Diagnostic.Count | Should -Be 0
        Should -Invoke Get-OmadaSqlSchemaData -ModuleName 'OmadaSql.PS' -Times 0 -Exactly
    }

    It 'Still runs beside other findings' {
        $Statement = @(Get-OmadaSqlTestStatement -Sql 'SELECT [a] = 1 FROM dbo.Gone')
        $Found = [pscustomobject]@{ RuleId = 'OMD001'; Source = 'Omada compatibility' }
        $Diagnostic = @(InModuleScope 'OmadaSql.PS' -Parameters @{ Statement = $Statement; Found = $Found } {
                param($Statement, $Found)
                Get-OmadaSqlSchemaDiagnostic -Context (Get-OmadaSqlConnectionContext) -Statement $Statement -Diagnostic @($Found) -DataConnection 'OISES'
            })
        @($Diagnostic.RuleId) | Should -Be @('OMD030')
    }
}

Describe 'Get-OmadaSqlSchemaDiagnostic parameter contract' -Tag 'Unit' {
    # Parameter declarations run no code a test could observe, so the mutation gate's mutants of
    # Mandatory, Position, pipeline binding and ValidateRange are caught only by asserting the contract.
    It '<Command> -<Parameter> <ParameterSet>' -ForEach @(
        @{ Command = 'Get-OmadaSqlSchemaDiagnostic'; Parameter = 'Context'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Get-OmadaSqlSchemaDiagnostic'; Parameter = 'Statement'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Get-OmadaSqlSchemaDiagnostic'; Parameter = 'Diagnostic'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Get-OmadaSqlStatementSchemaDiagnostic'; Parameter = 'Context'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Get-OmadaSqlStatementSchemaDiagnostic'; Parameter = 'Fragment'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Get-OmadaSqlStatementSchemaDiagnostic'; Parameter = 'DataConnection'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Get-OmadaSqlStatementSchemaDiagnostic'; Parameter = 'ScriptName'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Get-OmadaSqlStatementSchemaDiagnostic'; Parameter = 'Severity'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Get-OmadaSqlScriptDefinedName'; Parameter = 'Statement'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Find-OmadaSqlSchemaFinding'; Parameter = 'Fragment'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Find-OmadaSqlSchemaFinding'; Parameter = 'Model'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Find-OmadaSqlSchemaFinding'; Parameter = 'ScriptName'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Find-OmadaSqlSchemaColumnFinding'; Parameter = 'Scope'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Find-OmadaSqlSchemaColumnFinding'; Parameter = 'Model'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Test-OmadaSqlUnqualifiedColumn'; Parameter = 'Scope'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Test-OmadaSqlUnqualifiedColumn'; Parameter = 'Model'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Test-OmadaSqlUnqualifiedColumn'; Parameter = 'Name'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Get-OmadaSqlColumnOwner'; Parameter = 'Level'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Get-OmadaSqlColumnOwner'; Parameter = 'Model'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Get-OmadaSqlColumnOwner'; Parameter = 'Name'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Test-OmadaSqlQualifiedColumn'; Parameter = 'Scope'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Test-OmadaSqlQualifiedColumn'; Parameter = 'Model'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Test-OmadaSqlQualifiedColumn'; Parameter = 'Qualifier'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Test-OmadaSqlQualifiedColumn'; Parameter = 'Name'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
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
