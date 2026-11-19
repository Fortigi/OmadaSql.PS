param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaSql.PS\OmadaSql.PS.psm1')
)

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers\OmadaSqlTestHelper.ps1')
    Import-OmadaWebStub
    Get-Module -Name OmadaSql.PS -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'ConvertTo-OmadaSqlUnqualifiedText' -Tag 'Unit' {
    It 'Turns <Sql> into <Expected>' -ForEach @(
        @{ Sql = 'SELECT [Id] = Id FROM OISES.dbo.tblDataObject'; Expected = 'SELECT [Id] = Id FROM dbo.tblDataObject' }
        @{ Sql = 'SELECT [Id] = Id FROM [OISES].[dbo].[tblDataObject]'; Expected = 'SELECT [Id] = Id FROM [dbo].[tblDataObject]' }
        @{ Sql = 'SELECT [Id] = Id FROM OISES..tblDataObject'; Expected = 'SELECT [Id] = Id FROM tblDataObject' }
        @{ Sql = 'SELECT [a] = 1 FROM OISES.dbo.a JOIN OISES.dbo.b ON 1 = 1'; Expected = 'SELECT [a] = 1 FROM dbo.a JOIN dbo.b ON 1 = 1' }
        @{ Sql = "SELECT [a] = 'OISES.dbo.a' FROM dbo.a"; Expected = "SELECT [a] = 'OISES.dbo.a' FROM dbo.a" }
        @{ Sql = 'USE OISES'; Expected = '' }
    ) {
        $Statement = @(Get-OmadaSqlTestStatement -Sql $Sql)[0]
        InModuleScope 'OmadaSql.PS' -Parameters @{ Statement = $Statement; Expected = $Expected } {
            param($Statement, $Expected)
            ConvertTo-OmadaSqlUnqualifiedText -Statement $Statement | Should -BeExactly $Expected
        }
    }

    It 'Cuts on the offsets of a statement that is not the first in the script' {
        $Statement = @(Get-OmadaSqlTestStatement -Sql "SELECT [a] = 1;`nSELECT [b] = 2 FROM OISES.dbo.t")[1]
        InModuleScope 'OmadaSql.PS' -Parameters @{ Statement = $Statement } {
            param($Statement)
            ConvertTo-OmadaSqlUnqualifiedText -Statement $Statement | Should -BeExactly 'SELECT [b] = 2 FROM dbo.t'
        }
    }
}

Describe 'ConvertTo-OmadaSqlUnqualifiedText parameter contract' -Tag 'Unit' {
    # Parameter declarations run no code a test could observe, so the mutation gate's mutants of
    # Mandatory, Position, pipeline binding and ValidateRange are caught only by asserting the contract.
    It '<Command> -<Parameter> <ParameterSet>' -ForEach @(
        @{ Command = 'ConvertTo-OmadaSqlUnqualifiedText'; Parameter = 'Statement'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
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
