param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaSql.PS\OmadaSql.PS.psm1')
)

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers\OmadaSqlTestHelper.ps1')
    Import-OmadaWebStub
    Get-Module -Name OmadaSql.PS -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Get-OmadaSqlDatabaseReference' -Tag 'Unit' {
    It 'Finds <Case>' -ForEach @(
        @{ Case = 'a three-part name'; Sql = 'SELECT [Id] = Id FROM [OISES].dbo.tblDataObject'; Database = @('OISES'); Use = $null; FourPart = $false }
        @{ Case = 'the two-dot form'; Sql = 'SELECT [Id] = Id FROM OISES..tblDataObject'; Database = @('OISES'); Use = $null; FourPart = $false }
        @{ Case = 'a USE statement'; Sql = 'USE [ODW]'; Database = @('ODW'); Use = 'ODW'; FourPart = $false }
        @{ Case = 'one database written in two cases once'; Sql = 'SELECT [a] = 1 FROM oises.dbo.a JOIN OISES.dbo.b ON 1 = 1'; Database = @('oises'); Use = $null; FourPart = $false }
        @{ Case = 'two databases in order'; Sql = 'SELECT [a] = 1 FROM ODW.dbo.a JOIN OISES.dbo.b ON 1 = 1'; Database = @('ODW', 'OISES'); Use = $null; FourPart = $false }
        @{ Case = 'a four-part name'; Sql = 'SELECT [a] = 1 FROM srv.OISES.dbo.a'; Database = @('OISES'); Use = $null; FourPart = $true }
        @{ Case = 'nothing in a string or a comment'; Sql = "SELECT [a] = 'OISES.dbo.a' -- ODW.dbo.b"; Database = @(); Use = $null; FourPart = $false }
        @{ Case = 'nothing in a two-part name'; Sql = 'SELECT [a] = 1 FROM dbo.a'; Database = @(); Use = $null; FourPart = $false }
    ) {
        $Statement = @(Get-OmadaSqlTestStatement -Sql $Sql)[0]
        InModuleScope 'OmadaSql.PS' -Parameters @{ Fragment = $Statement.Fragment; Database = $Database; Use = $Use; FourPart = $FourPart } {
            param($Fragment, $Database, $Use, $FourPart)
            $Reference = Get-OmadaSqlDatabaseReference -Statement $Fragment
            (@($Reference.Database) -join ',') | Should -BeExactly (@($Database) -join ',')
            $Reference.UseDatabase | Should -Be $Use
            $Reference.FourPartName | Should -Be $FourPart
        }
    }
}

Describe 'Get-OmadaSqlDatabaseReference parameter contract' -Tag 'Unit' {
    # Parameter declarations run no code a test could observe, so the mutation gate's mutants of
    # Mandatory, Position, pipeline binding and ValidateRange are caught only by asserting the contract.
    It '<Command> -<Parameter> <ParameterSet>' -ForEach @(
        @{ Command = 'Get-OmadaSqlDatabaseReference'; Parameter = 'Statement'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
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
