param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaSql.PS\OmadaSql.PS.psm1')
)

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers\OmadaSqlTestHelper.ps1')
    Import-OmadaWebStub
    Get-Module -Name OmadaSql.PS -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $ModulePath -Force -ErrorAction Stop
}


Describe 'New-OmadaSqlQuery' -Tag 'Unit' {
    BeforeEach {
        $Script:Connection = Initialize-OmadaSqlTestConnection
        Mock Get-OmadaSqlDataConnectionList -ModuleName 'OmadaSql.PS' { [pscustomobject]@{ Name = 'OISES'; Id = 1001 } }
        Mock Assert-OmadaSqlQueryNameAvailable -ModuleName 'OmadaSql.PS' { }
        Mock Invoke-OmadaSqlRequest -ModuleName 'OmadaSql.PS' { [pscustomobject]@{ Id = 321 } }
        Mock Get-OmadaSqlQueryData -ModuleName 'OmadaSql.PS' { New-OmadaSqlTestODataQuery -Id $Id -Name 'New one' }
    }

    It 'POSTs the name, the SQL and the resolved data connection, and returns the created object' {
        $Result = New-OmadaSqlQuery -Name 'New one' -Query 'SELECT [x] = 1' -DataConnection 'OISES'
        $Result.Id | Should -Be 321
        Should -Invoke Invoke-OmadaSqlRequest -ModuleName 'OmadaSql.PS' -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'POST' -and $Path -eq 'odata/dataobjects/C_P_SQLTROUBLESHOOTING' -and
            $Body.NAME -eq 'New one' -and $Body.C_QUERY -eq 'SELECT [x] = 1' -and $Body.C_SQLTROUBLESHOOTING_DATACONNECTION.Id -eq 1001
        }
        Should -Invoke Assert-OmadaSqlQueryNameAvailable -ModuleName 'OmadaSql.PS' -Times 1 -Exactly -ParameterFilter { $Name -eq 'New one' }
    }

    It 'Sends nothing with -WhatIf' {
        $null = New-OmadaSqlQuery -Name 'New one' -Query 'SELECT 1' -DataConnection 1001 -WhatIf
        Should -Invoke Invoke-OmadaSqlRequest -ModuleName 'OmadaSql.PS' -Times 0 -Exactly
    }

    It 'Sends nothing for an unknown data connection' {
        { New-OmadaSqlQuery -Name 'New one' -Query 'SELECT 1' -DataConnection 'Nope' } | Should -Throw -ErrorId 'OmadaSql.InvalidArgument,New-OmadaSqlQuery'
        Should -Invoke Invoke-OmadaSqlRequest -ModuleName 'OmadaSql.PS' -Times 0 -Exactly
    }

    It 'Fails with InvalidResult when Omada returns no id' {
        Mock Invoke-OmadaSqlRequest -ModuleName 'OmadaSql.PS' { [pscustomobject]@{ } }
        { New-OmadaSqlQuery -Name 'New one' -Query 'SELECT 1' -DataConnection 1001 } | Should -Throw -ErrorId 'OmadaSql.InvalidResult,New-OmadaSqlQuery'
    }
}

Describe 'New-OmadaSqlQuery parameter contract' -Tag 'Unit' {
    # Parameter declarations run no code a test could observe, so the mutation gate's mutants of
    # Mandatory, Position, pipeline binding and ValidateRange are caught only by asserting the contract.
    It '<Command> -<Parameter> <ParameterSet>' -ForEach @(
        @{ Command = 'New-OmadaSqlQuery'; Parameter = 'Name'; ParameterSet = ''; Mandatory = $true; Position = 0; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'New-OmadaSqlQuery'; Parameter = 'Query'; ParameterSet = ''; Mandatory = $true; Position = 1; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'New-OmadaSqlQuery'; Parameter = 'DataConnection'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
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
