param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaSql.PS\OmadaSql.PS.psm1')
)

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers\OmadaSqlTestHelper.ps1')
    Import-OmadaWebStub
    Get-Module -Name OmadaSql.PS -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $ModulePath -Force -ErrorAction Stop
}


Describe 'Get-OmadaSqlQueryChange' -Tag 'Unit' {
    BeforeAll {
        $Script:Current = [pscustomobject]@{ Name = 'Daily'; Query = 'SELECT 1'; DataConnectionId = 1001 }
    }

    It 'Returns an empty body when nothing differs' {
        InModuleScope 'OmadaSql.PS' -Parameters @{ Current = $Script:Current } {
            param($Current)
            (Get-OmadaSqlQueryChange -Current $Current -Desired @{ Name = 'Daily'; Query = 'SELECT 1'; DataConnectionId = 1001 }).Count | Should -Be 0
        }
    }

    It 'Sends only the fields that differ' {
        InModuleScope 'OmadaSql.PS' -Parameters @{ Current = $Script:Current } {
            param($Current)
            $Body = Get-OmadaSqlQueryChange -Current $Current -Desired @{ Name = 'Daily'; Query = 'SELECT 2'; DataConnectionId = 1002 }
            @($Body.Keys) | Should -Be @('C_QUERY', 'C_SQLTROUBLESHOOTING_DATACONNECTION')
            $Body.C_QUERY | Should -Be 'SELECT 2'
            $Body.C_SQLTROUBLESHOOTING_DATACONNECTION.Id | Should -Be 1002
        }
    }

    It 'Treats a change in case as a change, as the stored text does' {
        InModuleScope 'OmadaSql.PS' -Parameters @{ Current = $Script:Current } {
            param($Current)
            (Get-OmadaSqlQueryChange -Current $Current -Desired @{ Name = 'daily' }).NAME | Should -Be 'daily'
        }
    }

    It 'Leaves out a key that is not desired' {
        InModuleScope 'OmadaSql.PS' -Parameters @{ Current = $Script:Current } {
            param($Current)
            (Get-OmadaSqlQueryChange -Current $Current -Desired @{}).Count | Should -Be 0
        }
    }
}

Describe 'Update-OmadaSqlQueryObject' -Tag 'Unit' {
    BeforeEach {
        $Script:Connection = Initialize-OmadaSqlTestConnection
        Mock Invoke-OmadaSqlRequest -ModuleName 'OmadaSql.PS' { $null }
        Mock Assert-OmadaSqlQueryNameAvailable -ModuleName 'OmadaSql.PS' { }
    }

    It 'PUTs the body to the object and checks a new name' {
        InModuleScope 'OmadaSql.PS' {
            Update-OmadaSqlQueryObject -Context (Get-OmadaSqlConnectionContext) -Id 7 -Body ([ordered]@{ NAME = 'New' })
        }
        Should -Invoke Invoke-OmadaSqlRequest -ModuleName 'OmadaSql.PS' -Times 1 -Exactly -ParameterFilter { $Method -eq 'PUT' -and $Path -eq 'odata/dataobjects/C_P_SQLTROUBLESHOOTING(7)' -and $Body.NAME -eq 'New' }
        Should -Invoke Assert-OmadaSqlQueryNameAvailable -ModuleName 'OmadaSql.PS' -Times 1 -Exactly -ParameterFilter { $Name -eq 'New' -and $ExceptId -eq 7 }
    }

    It 'Does not check the name when it does not change' {
        InModuleScope 'OmadaSql.PS' {
            Update-OmadaSqlQueryObject -Context (Get-OmadaSqlConnectionContext) -Id 7 -Body ([ordered]@{ C_QUERY = 'SELECT 1' })
        }
        Should -Invoke Assert-OmadaSqlQueryNameAvailable -ModuleName 'OmadaSql.PS' -Times 0 -Exactly
    }
}

Describe 'Get-OmadaSqlQueryChange parameter contract' -Tag 'Unit' {
    # Parameter declarations run no code a test could observe, so the mutation gate's mutants of
    # Mandatory, Position, pipeline binding and ValidateRange are caught only by asserting the contract.
    It '<Command> -<Parameter> <ParameterSet>' -ForEach @(
        @{ Command = 'Get-OmadaSqlQueryChange'; Parameter = 'Current'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Get-OmadaSqlQueryChange'; Parameter = 'Desired'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Update-OmadaSqlQueryObject'; Parameter = 'Context'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Update-OmadaSqlQueryObject'; Parameter = 'Id'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Update-OmadaSqlQueryObject'; Parameter = 'Body'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
    ) {
        $Contract = Get-OmadaSqlParameterContract -CommandName $Command -ParameterName $Parameter -ParameterSetName $ParameterSet
        $Contract.Mandatory | Should -Be $Mandatory
        $Contract.Position | Should -Be $Position
        $Contract.ValueFromPipeline | Should -Be $ValueFromPipeline
        $Contract.ValueFromPipelineByPropertyName | Should -Be $ValueFromPipelineByPropertyName
        $Contract.RangeMin | Should -Be $RangeMin
        $Contract.RangeMax | Should -Be $RangeMax
    }
}
