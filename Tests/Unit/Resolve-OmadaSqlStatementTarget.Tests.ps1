param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaSql.PS\OmadaSql.PS.psm1')
)

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers\OmadaSqlTestHelper.ps1')
    Import-OmadaWebStub
    Get-Module -Name OmadaSql.PS -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Resolve-OmadaSqlStatementTarget' -Tag 'Unit' {
    BeforeAll {
        $Script:Connection = Initialize-OmadaSqlTestConnection
    }

    BeforeEach {
        Mock Resolve-OmadaSqlDataConnection -ModuleName 'OmadaSql.PS' { [pscustomobject]@{ Name = [string]$DataConnection; Id = 1 } }
    }

    It 'Runs every statement against -DataConnection when none names a database' {
        $Statement = @(Get-OmadaSqlTestStatement -Sql "SELECT [a] = 1;`nSELECT [b] = 2")
        $Target = InModuleScope 'OmadaSql.PS' -Parameters @{ Statement = $Statement } {
            param($Statement)
            @(Resolve-OmadaSqlStatementTarget -Context (Get-OmadaSqlConnectionContext) -Statement $Statement -DataConnection 'OISES')
        }
        $Target.Count | Should -Be 2
        @($Target.DataConnection.Name) | Should -Be @('OISES', 'OISES')
        @($Target.Ordinal) | Should -Be @(1, 2)
        @($Target.Line) | Should -Be @(1, 2)
        $Target[0].Text | Should -Be 'SELECT [a] = 1;'
        $Target[0].PSObject.TypeNames | Should -Contain 'OmadaSql.StatementTarget'
    }

    It 'Leaves the data connection empty when nothing chooses one' {
        $Statement = @(Get-OmadaSqlTestStatement -Sql 'SELECT [a] = 1')
        $Target = InModuleScope 'OmadaSql.PS' -Parameters @{ Statement = $Statement } {
            param($Statement)
            @(Resolve-OmadaSqlStatementTarget -Context (Get-OmadaSqlConnectionContext) -Statement $Statement)
        }
        $Target[0].DataConnection | Should -BeNullOrEmpty
        Should -Invoke Resolve-OmadaSqlDataConnection -ModuleName 'OmadaSql.PS' -Times 0 -Exactly
    }

    It 'Applies a USE to the statements after it, and runs nothing for the USE itself' {
        $Statement = @(Get-OmadaSqlTestStatement -Sql "SELECT [a] = 1;`nUSE ODW;`nSELECT [b] = 2;`nSELECT [c] = 3")
        $Target = InModuleScope 'OmadaSql.PS' -Parameters @{ Statement = $Statement } {
            param($Statement)
            @(Resolve-OmadaSqlStatementTarget -Context (Get-OmadaSqlConnectionContext) -Statement $Statement -DataConnection 'OISES')
        }
        @($Target.Ordinal) | Should -Be @(1, 3, 4)
        @($Target.DataConnection.Name) | Should -Be @('OISES', 'ODW', 'ODW')
    }

    It 'Binds a three-part name to its own statement only, and removes the prefix' {
        $Statement = @(Get-OmadaSqlTestStatement -Sql "SELECT [a] = 1 FROM ODW.dbo.t;`nSELECT [b] = 2")
        $Target = InModuleScope 'OmadaSql.PS' -Parameters @{ Statement = $Statement } {
            param($Statement)
            @(Resolve-OmadaSqlStatementTarget -Context (Get-OmadaSqlConnectionContext) -Statement $Statement -DataConnection 'OISES')
        }
        @($Target.DataConnection.Name) | Should -Be @('ODW', 'OISES')
        $Target[0].Text | Should -Be 'SELECT [a] = 1 FROM dbo.t;'
    }

    It 'Refuses <Case> before resolving anything after it' -ForEach @(
        @{ Case = 'a four-part name'; Sql = "SELECT [a] = 1;`nSELECT [b] = 1 FROM srv.OISES.dbo.t"; Message = '*Statement 2 (line 2)*four-part*' }
        @{ Case = 'two databases in one statement'; Sql = 'SELECT [a] = 1 FROM ODW.dbo.a JOIN OISES.dbo.b ON 1 = 1'; Message = '*more than one database (ODW, OISES)*' }
    ) {
        $Statement = @(Get-OmadaSqlTestStatement -Sql $Sql)
        $Caught = InModuleScope 'OmadaSql.PS' -Parameters @{ Statement = $Statement } {
            param($Statement)
            try {
                $null = @(Resolve-OmadaSqlStatementTarget -Context (Get-OmadaSqlConnectionContext) -Statement $Statement)
                $null
            }
            catch { $_ }
        }
        $Caught.FullyQualifiedErrorId | Should -Be 'OmadaSql.InvalidArgument'
        $Caught.Exception.Message | Should -BeLike $Message
    }
}

Describe 'Resolve-OmadaSqlStatementTarget parameter contract' -Tag 'Unit' {
    # Parameter declarations run no code a test could observe, so the mutation gate's mutants of
    # Mandatory, Position, pipeline binding and ValidateRange are caught only by asserting the contract.
    It '<Command> -<Parameter> <ParameterSet>' -ForEach @(
        @{ Command = 'Resolve-OmadaSqlStatementTarget'; Parameter = 'Context'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Resolve-OmadaSqlStatementTarget'; Parameter = 'Statement'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Assert-OmadaSqlSingleDatabase'; Parameter = 'Statement'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Assert-OmadaSqlSingleDatabase'; Parameter = 'Reference'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
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
