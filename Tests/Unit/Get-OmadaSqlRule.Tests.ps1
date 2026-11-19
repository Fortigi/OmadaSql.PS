param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaSql.PS\OmadaSql.PS.psm1')
)

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers\OmadaSqlTestHelper.ps1')
    Import-OmadaWebStub
    Get-Module -Name OmadaSql.PS -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Get-OmadaSqlRule' -Tag 'Unit' {
    BeforeAll {
        function Get-TestRuleId {
            param([string]$Sql)
            $Diagnostic = & (Get-Module -Name 'OmadaSql.PS') { param($Text) (Get-OmadaSqlDiagnostic -Sql $Text).Diagnostic } $Sql
            (@($Diagnostic | ForEach-Object { $_.RuleId }) | Sort-Object -Unique) -join ','
        }
    }

    It 'Declares every rule with its default severity' {
        InModuleScope 'OmadaSql.PS' {
            (@(Get-OmadaSqlRule | ForEach-Object { '{0}={1}' -f $_.Id, $_.Severity }) -join ',') | Should -Be 'OMD001=Warning,OMD003=Info,OMD004=Error,OMD010=Error,OMD011=Error,OMD012=Error,OMD013=Error,OMD020=Error,OMD021=Error'
            @(Get-OmadaSqlRule | Where-Object { [string]::IsNullOrWhiteSpace($_.Title) -or $null -eq (Get-Command -Name $_.Find -CommandType Function -ErrorAction SilentlyContinue) }).Count | Should -Be 0
        }
    }

    It 'Reports <Expected> for <Case>' -ForEach @(
        @{ Case = 'a clean query'; Sql = 'SELECT [Id] = o.Id, o.DisplayName FROM dbo.tblDataObject AS o'; Expected = '' }
        @{ Case = 'COUNT(*) without a name'; Sql = 'SELECT COUNT(*) FROM dbo.t'; Expected = 'OMD001' }
        @{ Case = 'a literal without a name'; Sql = 'SELECT 1'; Expected = 'OMD001' }
        @{ Case = 'a nameless column in the first UNION branch'; Sql = 'SELECT 1 UNION SELECT 2 AS b'; Expected = 'OMD001' }
        @{ Case = 'SELECT *'; Sql = 'SELECT * FROM dbo.t'; Expected = '' }
        @{ Case = 'a nameless column in a subquery only'; Sql = 'SELECT [a] = 1 WHERE EXISTS (SELECT 1)'; Expected = '' }
        @{ Case = 'an alias with a space'; Sql = 'SELECT [Display Name] = DisplayName FROM dbo.t'; Expected = 'OMD003' }
        @{ Case = 'an alias with a dash and an underscore'; Sql = 'SELECT [a-b_c] = 1'; Expected = '' }
        @{ Case = 'a nameless column in a derived table'; Sql = 'SELECT [a] = d.x FROM (SELECT 1 AS x, 2) AS d'; Expected = 'OMD004' }
        @{ Case = 'a nameless column in a CTE'; Sql = 'WITH c AS (SELECT COUNT(*)) SELECT [a] = 1 FROM c'; Expected = 'OMD004' }
        @{ Case = 'a CTE with a column list'; Sql = 'WITH c (n) AS (SELECT COUNT(*)) SELECT [a] = n FROM c'; Expected = '' }
        @{ Case = 'INSERT'; Sql = 'INSERT INTO dbo.t (a) VALUES (1)'; Expected = 'OMD010' }
        @{ Case = 'UPDATE inside IF'; Sql = "IF 1 = 1`nBEGIN`n  UPDATE dbo.t SET a = 1`nEND"; Expected = 'OMD010' }
        @{ Case = 'DELETE'; Sql = 'DELETE FROM dbo.t'; Expected = 'OMD010' }
        @{ Case = 'MERGE'; Sql = 'MERGE dbo.t AS t USING dbo.s AS s ON t.a = s.a WHEN MATCHED THEN DELETE;'; Expected = 'OMD010' }
        @{ Case = 'TRUNCATE TABLE'; Sql = 'TRUNCATE TABLE dbo.t'; Expected = 'OMD010' }
        @{ Case = 'CREATE VIEW'; Sql = 'CREATE VIEW dbo.v AS SELECT [a] = 1'; Expected = 'OMD011' }
        @{ Case = 'DROP TABLE'; Sql = 'DROP TABLE dbo.t'; Expected = 'OMD011' }
        @{ Case = 'the word create in a string'; Sql = "SELECT [a] = 'create table'"; Expected = '' }
        @{ Case = 'EXEC'; Sql = 'EXEC dbo.p'; Expected = 'OMD012' }
        @{ Case = 'a temporary table'; Sql = 'SELECT [a] = 1 FROM #t'; Expected = 'OMD013' }
        @{ Case = 'SELECT INTO a temporary table'; Sql = 'SELECT [a] = 1 INTO #t'; Expected = 'OMD013' }
        @{ Case = 'a four-part name'; Sql = 'SELECT [a] = 1 FROM srv.OISES.dbo.t'; Expected = 'OMD020' }
        @{ Case = 'two databases'; Sql = 'SELECT [a] = 1 FROM ODW.dbo.a JOIN OISES.dbo.b ON 1 = 1'; Expected = 'OMD021' }
        @{ Case = 'one database'; Sql = 'SELECT [a] = 1 FROM OISES.dbo.a JOIN OISES.dbo.b ON 1 = 1'; Expected = '' }
    ) {
        Get-TestRuleId -Sql $Sql | Should -Be $Expected
    }

    It 'Marks the flagged fragment and explains the fix' {
        $Diagnostic = & (Get-Module -Name 'OmadaSql.PS') { (Get-OmadaSqlDiagnostic -Sql "SELECT [a] = 1,`n  COUNT(*) FROM dbo.t").Diagnostic }
        $Diagnostic.Line | Should -Be 2
        $Diagnostic.Column | Should -Be 3
        $Diagnostic.Message | Should -BeLike '*AS `[COUNT`]*'
    }

    It 'Names the scope and the alias in an OMD004 message' {
        $Diagnostic = & (Get-Module -Name 'OmadaSql.PS') { (Get-OmadaSqlDiagnostic -Sql "SELECT [a] = d.x FROM (SELECT 1 AS x, 'v') AS d").Diagnostic }
        $Diagnostic.Message | Should -BeLike '*in a derived table (Msg 8155)*AS `[Value`]*'
    }

    It 'Names the statement kind in an OMD010 message and the alias in an OMD003 message' {
        $Diagnostic = & (Get-Module -Name 'OmadaSql.PS') { (Get-OmadaSqlDiagnostic -Sql 'TRUNCATE TABLE dbo.t').Diagnostic }
        $Diagnostic.Message | Should -BeLike '*TRUNCATE TABLE cannot run*'
        $Diagnostic = & (Get-Module -Name 'OmadaSql.PS') { (Get-OmadaSqlDiagnostic -Sql 'SELECT [a b] = 1').Diagnostic }
        $Diagnostic.Message | Should -BeLike "*alias 'a b'*"
    }

    It 'Lists both databases in an OMD021 message' {
        $Diagnostic = & (Get-Module -Name 'OmadaSql.PS') { (Get-OmadaSqlDiagnostic -Sql 'SELECT [a] = 1 FROM ODW.dbo.a JOIN OISES.dbo.b ON 1 = 1').Diagnostic }
        $Diagnostic.Message | Should -BeLike '*(ODW, OISES)*'
    }
}

Describe 'Test-OmadaSqlSelectElementNameless' -Tag 'Unit' {
    It 'Returns $false for no element and for an element that is not a scalar expression' {
        InModuleScope 'OmadaSql.PS' {
            Test-OmadaSqlSelectElementNameless -SelectElement $null | Should -BeFalse
            Test-OmadaSqlSelectElementNameless -SelectElement ([pscustomobject]@{ Name = 'x' }) | Should -BeFalse
        }
    }
}

Describe 'Get-OmadaSqlSuggestedColumnAlias' -Tag 'Unit' {
    It 'Suggests <Expected> for <Sql>' -ForEach @(
        @{ Sql = 'SELECT COUNT(*)'; Expected = 'COUNT' }
        @{ Sql = "SELECT 'x'"; Expected = 'Value' }
        @{ Sql = 'SELECT 1'; Expected = 'Value' }
        @{ Sql = 'SELECT CONVERT(int, 1)'; Expected = 'Value' }
        @{ Sql = 'SELECT CAST(1 AS int)'; Expected = 'Value' }
        @{ Sql = 'SELECT (SELECT 1 AS a)'; Expected = 'Value' }
        @{ Sql = 'SELECT CASE WHEN 1 = 1 THEN 1 END'; Expected = 'Case' }
        @{ Sql = 'SELECT 1 + 1'; Expected = 'Column' }
        @{ Sql = 'SELECT dbo.[my func](1)'; Expected = 'my_func' }
    ) {
        $Expression = & (Get-Module -Name 'OmadaSql.PS') { param($Text) (ConvertTo-OmadaSqlScriptFragment -Sql $Text).Fragment.Batches[0].Statements[0].QueryExpression.SelectElements[0].Expression } $Sql
        InModuleScope 'OmadaSql.PS' -Parameters @{ Expression = $Expression; Expected = $Expected } {
            param($Expression, $Expected)
            Get-OmadaSqlSuggestedColumnAlias -Expression $Expression | Should -BeExactly $Expected
        }
    }
}


Describe 'Get-OmadaSqlRule parameter contract' -Tag 'Unit' {
    # Parameter declarations run no code a test could observe, so the mutation gate's mutants of
    # Mandatory, Position, pipeline binding and ValidateRange are caught only by asserting the contract.
    It '<Command> -<Parameter> <ParameterSet>' -ForEach @(
        @{ Command = 'Find-OmadaSqlNamelessResultColumn'; Parameter = 'Context'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Find-OmadaSqlRenamedAlias'; Parameter = 'Context'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Find-OmadaSqlNamelessScopedColumn'; Parameter = 'Context'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Find-OmadaSqlDataManipulation'; Parameter = 'Context'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Find-OmadaSqlDataDefinition'; Parameter = 'Context'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Find-OmadaSqlExecute'; Parameter = 'Context'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Find-OmadaSqlTemporaryTable'; Parameter = 'Context'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Find-OmadaSqlFourPartName'; Parameter = 'Context'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Find-OmadaSqlCrossDatabase'; Parameter = 'Context'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Test-OmadaSqlSelectElementNameless'; Parameter = 'SelectElement'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Get-OmadaSqlSuggestedColumnAlias'; Parameter = 'Expression'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
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
