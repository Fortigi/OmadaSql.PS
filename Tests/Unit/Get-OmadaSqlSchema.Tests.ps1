param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaSql.PS\OmadaSql.PS.psm1')
)

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers\OmadaSqlTestHelper.ps1')
    Import-OmadaWebStub
    Get-Module -Name OmadaSql.PS -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Get-OmadaSqlSchema' -Tag 'Unit' {
    BeforeEach {
        $Script:Connection = Initialize-OmadaSqlTestConnection
        Mock Get-OmadaSqlDataConnectionList -ModuleName 'OmadaSql.PS' {
            [pscustomobject]@{ Name = 'OISES'; Id = 1001 }
            [pscustomobject]@{ Name = 'ODW'; Id = 1002 }
        }
        Mock Get-OmadaSqlSchemaData -ModuleName 'OmadaSql.PS' {
            [pscustomobject]@{ 'dbo.tblDataObject' = @('Id int'); 'dbo.tblAction' = @('Id int'); 'adhoc.viewX' = @('A int') }
        }
    }

    It 'Returns every table and view of a data connection, sorted by name' {
        @(Get-OmadaSqlSchema -DataConnection 'OISES').Name | Should -Be @('adhoc.viewX', 'dbo.tblAction', 'dbo.tblDataObject')
    }

    It 'Filters on the schema.table name with wildcards' {
        @(Get-OmadaSqlSchema 'OISES' -Name 'dbo.tblD*').Name | Should -Be @('dbo.tblDataObject')
    }

    It 'Reads each data connection piped in, once, and again with -Force' {
        $Tables = @(Get-OmadaSqlDataConnection | Get-OmadaSqlSchema)
        $Tables.Count | Should -Be 6
        @($Tables.DataConnection | Select-Object -Unique) | Should -Be @('OISES', 'ODW')
        $null = Get-OmadaSqlSchema -DataConnection 'OISES'
        Should -Invoke Get-OmadaSqlSchemaData -ModuleName 'OmadaSql.PS' -Times 2 -Exactly
        $null = Get-OmadaSqlSchema -DataConnection 'OISES' -Force
        Should -Invoke Get-OmadaSqlSchemaData -ModuleName 'OmadaSql.PS' -Times 3 -Exactly
    }

    It 'Fails with InvalidArgument for an unknown data connection' {
        { Get-OmadaSqlSchema -DataConnection 'Nope' } | Should -Throw -ErrorId 'OmadaSql.InvalidArgument,Get-OmadaSqlSchema'
    }

    It 'Fails with NotConnected without a connection' {
        Disconnect-OmadaSql -All
        { Get-OmadaSqlSchema -DataConnection 'OISES' } | Should -Throw -ErrorId 'OmadaSql.NotConnected,Get-OmadaSqlSchema'
    }
}

Describe 'Get-OmadaSqlSchema parameter contract' -Tag 'Unit' {
    # Parameter declarations run no code a test could observe, so the mutation gate's mutants of
    # Mandatory, Position, pipeline binding and ValidateRange are caught only by asserting the contract.
    It '<Command> -<Parameter> <ParameterSet>' -ForEach @(
        @{ Command = 'Get-OmadaSqlSchema'; Parameter = 'DataConnection'; ParameterSet = ''; Mandatory = $true; Position = 0; ValueFromPipeline = $true; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
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
