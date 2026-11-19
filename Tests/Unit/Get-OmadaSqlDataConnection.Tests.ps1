param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaSql.PS\OmadaSql.PS.psm1')
)

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers\OmadaSqlTestHelper.ps1')
    Import-OmadaWebStub
    Get-Module -Name OmadaSql.PS -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $ModulePath -Force -ErrorAction Stop
}


Describe 'Get-OmadaSqlDataConnection' -Tag 'Unit' {
    BeforeEach {
        $Script:Connection = Initialize-OmadaSqlTestConnection
        Mock Get-OmadaSqlDataConnectionList -ModuleName 'OmadaSql.PS' {
            [pscustomobject]@{ Name = 'OISES'; Id = 1001 }
            [pscustomobject]@{ Name = 'ODW'; Id = 1002 }
        }
    }

    It 'Returns every data connection, and filters by name with wildcards' {
        @(Get-OmadaSqlDataConnection).Count | Should -Be 2
        @(Get-OmadaSqlDataConnection -Name 'OIS*').Id | Should -Be @(1001)
    }

    It 'Reads the list once per connection and again with -Force' {
        $null = Get-OmadaSqlDataConnection
        $null = Get-OmadaSqlDataConnection -Name 'ODW'
        Should -Invoke Get-OmadaSqlDataConnectionList -ModuleName 'OmadaSql.PS' -Times 1 -Exactly

        $null = Get-OmadaSqlDataConnection -Force
        Should -Invoke Get-OmadaSqlDataConnectionList -ModuleName 'OmadaSql.PS' -Times 2 -Exactly
    }

    It 'Fails with NotConnected without a connection' {
        Disconnect-OmadaSql -All
        { Get-OmadaSqlDataConnection } | Should -Throw -ErrorId 'OmadaSql.NotConnected,Get-OmadaSqlDataConnection'
    }
}

Describe 'Get-OmadaSqlDataConnection parameter contract' -Tag 'Unit' {
    # Parameter declarations run no code a test could observe, so the mutation gate's mutants of
    # Mandatory, Position, pipeline binding and ValidateRange are caught only by asserting the contract.
    It '<Command> -<Parameter> <ParameterSet>' -ForEach @(
        @{ Command = 'Get-OmadaSqlDataConnection'; Parameter = 'Name'; ParameterSet = ''; Mandatory = $false; Position = 0; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
    ) {
        $Contract = Get-OmadaSqlParameterContract -CommandName $Command -ParameterName $Parameter -ParameterSetName $ParameterSet
        $Contract.Mandatory | Should -Be $Mandatory
        # Only a declared position is part of the contract: without one PowerShell numbers the
        # parameters of an advanced function in declaration order, which no mutant can change.
        if ($null -ne $Position) {
            $Contract.Position | Should -Be $Position
        }
        $Contract.ValueFromPipeline | Should -Be $ValueFromPipeline
        $Contract.ValueFromPipelineByPropertyName | Should -Be $ValueFromPipelineByPropertyName
        $Contract.RangeMin | Should -Be $RangeMin
        $Contract.RangeMax | Should -Be $RangeMax
    }
}
