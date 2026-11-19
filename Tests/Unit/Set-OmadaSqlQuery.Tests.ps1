param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaSql.PS\OmadaSql.PS.psm1')
)

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers\OmadaSqlTestHelper.ps1')
    Import-OmadaWebStub
    Get-Module -Name OmadaSql.PS -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $ModulePath -Force -ErrorAction Stop
}


Describe 'Set-OmadaSqlQuery' -Tag 'Unit' {
    BeforeEach {
        $Script:Connection = Initialize-OmadaSqlTestConnection
        Mock Get-OmadaSqlDataConnectionList -ModuleName 'OmadaSql.PS' { [pscustomobject]@{ Name = 'OISES'; Id = 1001 }; [pscustomobject]@{ Name = 'ODW'; Id = 1002 } }
        Mock Get-OmadaSqlQueryData -ModuleName 'OmadaSql.PS' { New-OmadaSqlTestODataQuery -Id $Id -Name 'Daily' -Query 'SELECT 1' -DataConnectionId 1001 }
        Mock Update-OmadaSqlQueryObject -ModuleName 'OmadaSql.PS' { }
    }

    It 'Sends only what differs' {
        Set-OmadaSqlQuery -Id 7 -Query 'SELECT 2' -DataConnection 'ODW' -Name 'Daily'
        Should -Invoke Update-OmadaSqlQueryObject -ModuleName 'OmadaSql.PS' -Times 1 -Exactly -ParameterFilter {
            $Id -eq 7 -and ((@($Body.Keys)) -join ',') -eq 'C_QUERY,C_SQLTROUBLESHOOTING_DATACONNECTION' -and $Body.C_SQLTROUBLESHOOTING_DATACONNECTION.Id -eq 1002
        }
    }

    It 'Sends nothing and returns nothing when nothing differs' {
        @(Set-OmadaSqlQuery -Id 7 -Query 'SELECT 1').Count | Should -Be 0
        Should -Invoke Update-OmadaSqlQueryObject -ModuleName 'OmadaSql.PS' -Times 0 -Exactly
    }

    It 'Still returns the unchanged object with -PassThru when nothing differs' {
        $Result = Set-OmadaSqlQuery -Id 7 -Query 'SELECT 1' -PassThru
        $Result.Id | Should -Be 7
        $Result.Query | Should -Be 'SELECT 1'
        Should -Invoke Update-OmadaSqlQueryObject -ModuleName 'OmadaSql.PS' -Times 0 -Exactly
    }

    It 'Sends nothing with -WhatIf' {
        Set-OmadaSqlQuery -Id 7 -Query 'SELECT 2' -WhatIf
        Should -Invoke Update-OmadaSqlQueryObject -ModuleName 'OmadaSql.PS' -Times 0 -Exactly
    }

    It 'Refuses a call without anything to change' {
        { Set-OmadaSqlQuery -Id 7 } | Should -Throw -ErrorId 'OmadaSql.InvalidArgument,Set-OmadaSqlQuery'
    }

    It 'Changes every piped object and returns them with -PassThru' {
        $Result = @([pscustomobject]@{ Id = 7 }, [pscustomobject]@{ Id = 8 } | Set-OmadaSqlQuery -Query 'SELECT 3' -PassThru)
        $Result.Id | Should -Be @(7, 8)
        Should -Invoke Update-OmadaSqlQueryObject -ModuleName 'OmadaSql.PS' -Times 2 -Exactly
    }
}

Describe 'Set-OmadaSqlQuery parameter contract' -Tag 'Unit' {
    # Parameter declarations run no code a test could observe, so the mutation gate's mutants of
    # Mandatory, Position, pipeline binding and ValidateRange are caught only by asserting the contract.
    It '<Command> -<Parameter> <ParameterSet>' -ForEach @(
        @{ Command = 'Set-OmadaSqlQuery'; Parameter = 'Id'; ParameterSet = ''; Mandatory = $true; Position = 0; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $true; RangeMin = '1'; RangeMax = '9223372036854775807' }
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
