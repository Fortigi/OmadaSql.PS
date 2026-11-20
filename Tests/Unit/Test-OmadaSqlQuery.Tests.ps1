param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaSql.PS\OmadaSql.PS.psm1')
)

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers\OmadaSqlTestHelper.ps1')
    Import-OmadaWebStub
    Get-Module -Name OmadaSql.PS -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Test-OmadaSqlQuery' -Tag 'Unit' {
    It 'Returns nothing for a query without findings' {
        @(Test-OmadaSqlQuery -Query 'SELECT [Id] = Id FROM dbo.tblDataObject').Count | Should -Be 0
    }

    It 'Returns the findings of a query, also from the pipeline' {
        $Diagnostic = @('SELECT COUNT(*) FROM dbo.t' | Test-OmadaSqlQuery)
        $Diagnostic.Count | Should -Be 1
        $Diagnostic[0].RuleId | Should -Be 'OMD001'
        $Diagnostic[0].PSObject.TypeNames[0] | Should -Be 'OmadaSql.Diagnostic'
    }

    It 'Reads the query from a file as UTF-8' {
        $Path = Join-Path $TestDrive 'query.sql'
        [System.IO.File]::WriteAllText($Path, ("SELECT [Bedrag {0}] = 1" -f [char]0x20AC), [System.Text.UTF8Encoding]::new($false))
        $Diagnostic = @(Test-OmadaSqlQuery -Path $Path)
        $Diagnostic[0].RuleId | Should -Be 'OMD003'
        $Diagnostic[0].Message | Should -BeLike ("*'Bedrag {0}'*" -f [char]0x20AC)
    }

    It 'Fails for a file that does not exist' {
        { Test-OmadaSqlQuery -Path (Join-Path $TestDrive 'missing.sql') } | Should -Throw
    }

    It 'With -Quiet returns <Expected> for <Case>' -ForEach @(
        @{ Case = 'a clean query'; Sql = 'SELECT [a] = 1'; Expected = $true }
        @{ Case = 'an Info finding only'; Sql = 'SELECT [a b] = 1'; Expected = $true }
        @{ Case = 'a Warning'; Sql = 'SELECT 1'; Expected = $false }
        @{ Case = 'a syntax error'; Sql = 'SELEC 1'; Expected = $false }
    ) {
        Test-OmadaSqlQuery -Query $Sql -Quiet | Should -Be $Expected
    }

    It 'Passes -RuleSeverity on' {
        Test-OmadaSqlQuery -Query 'SELECT 1' -RuleSeverity @{ OMD001 = 'Off' } -Quiet | Should -BeTrue
        { Test-OmadaSqlQuery -Query 'SELECT 1' -RuleSeverity @{ OMD999 = 'Off' } } | Should -Throw -ErrorId 'OmadaSql.InvalidArgument,Test-OmadaSqlQuery'
    }

    It 'Checks an empty query without findings' {
        @(Test-OmadaSqlQuery -Query '').Count | Should -Be 0
    }
}

Describe 'Test-OmadaSqlQuery -DataConnection' -Tag 'Unit' {
    BeforeEach {
        $Script:Connection = Initialize-OmadaSqlTestConnection
        Mock Get-OmadaSqlDataConnectionList -ModuleName 'OmadaSql.PS' { [pscustomobject]@{ Name = 'OISES'; Id = 1001 } }
        Mock Get-OmadaSqlSchemaData -ModuleName 'OmadaSql.PS' { [pscustomobject]@{ 'dbo.Person' = @('Id int') } }
    }

    It 'Adds the schema findings to the rule findings, in position order' {
        $Diagnostic = @(Test-OmadaSqlQuery -Query "SELECT [a] = Nope,`n COUNT(*) FROM dbo.Person" -DataConnection 'OISES')
        @($Diagnostic.RuleId) | Should -Be @('OMD031', 'OMD001')
        @($Diagnostic.Line) | Should -Be @(1, 2)
    }

    It 'Sorts findings on the same line by column' {
        $Diagnostic = @(Test-OmadaSqlQuery -Query 'SELECT [a] = Nope, COUNT(*) FROM dbo.Person' -DataConnection 'OISES')
        @($Diagnostic.RuleId) | Should -Be @('OMD031', 'OMD001')
    }

    It 'Keeps -Quiet true for schema findings, which are Info' {
        Test-OmadaSqlQuery -Query 'SELECT [a] = Nope FROM dbo.Person' -DataConnection 'OISES' -Quiet | Should -BeTrue
        Test-OmadaSqlQuery -Query 'SELECT [a] = Nope FROM dbo.Person' -DataConnection 'OISES' -RuleSeverity @{ OMD031 = 'Warning' } -Quiet | Should -BeFalse
    }

    It 'Reads no schema without -DataConnection' {
        @(Test-OmadaSqlQuery -Query 'SELECT [a] = Nope FROM dbo.Person').Count | Should -Be 0
        Should -Invoke Get-OmadaSqlSchemaData -ModuleName 'OmadaSql.PS' -Times 0 -Exactly
    }

    It 'Uses the connection given with -Connection' {
        $First = $Script:Connection
        $null = Connect-OmadaSql -Url 'https://other.omada.cloud' -AuthenticationType OAuth -ClientId 'client' -OAuthCertificateThumbprint 'AB12' -SkipConnectionTest -PassThru
        @(Test-OmadaSqlQuery -Query 'SELECT [a] = Nope FROM dbo.Person' -DataConnection 'OISES' -Connection $First).RuleId | Should -Be @('OMD031')
        $Cached = InModuleScope 'OmadaSql.PS' -Parameters @{ First = $First } {
            param($First)
            (Get-OmadaSqlConnectionContext -Connection $First).ContainsKey('SchemaCache')
            (Get-OmadaSqlConnectionContext).ContainsKey('SchemaCache')
        }
        $Cached | Should -Be @($true, $false)
    }

    It 'Fails with NotConnected for -DataConnection without a connection' {
        Disconnect-OmadaSql -All
        { Test-OmadaSqlQuery -Query 'SELECT [a] = 1' -DataConnection 'OISES' } | Should -Throw -ErrorId 'OmadaSql.NotConnected,Test-OmadaSqlQuery'
    }
}

Describe 'Test-OmadaSqlQuery parameter contract' -Tag 'Unit' {
    # Parameter declarations run no code a test could observe, so the mutation gate's mutants of
    # Mandatory, Position, pipeline binding and ValidateRange are caught only by asserting the contract.
    It '<Command> -<Parameter> <ParameterSet>' -ForEach @(
        @{ Command = 'Test-OmadaSqlQuery'; Parameter = 'Query'; ParameterSet = 'Query'; Mandatory = $true; Position = 0; ValueFromPipeline = $true; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Test-OmadaSqlQuery'; Parameter = 'Path'; ParameterSet = 'Path'; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
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
