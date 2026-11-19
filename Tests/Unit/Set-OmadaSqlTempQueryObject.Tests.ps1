param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaSql.PS\OmadaSql.PS.psm1')
)

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers\OmadaSqlTestHelper.ps1')
    Import-OmadaWebStub
    Get-Module -Name OmadaSql.PS -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Set-OmadaSqlTempQueryObject' -Tag 'Unit' {
    BeforeAll {
        $Script:Connection = Initialize-OmadaSqlTestConnection
    }

    BeforeEach {
        Mock Update-OmadaSqlQueryObject -ModuleName 'OmadaSql.PS' { }
    }

    It 'Creates the object when no object has the name, and returns its id' {
        Mock Get-OmadaSqlQueryData -ModuleName 'OmadaSql.PS' { }
        Mock Invoke-OmadaSqlRequest -ModuleName 'OmadaSql.PS' { [pscustomobject]@{ Id = 77 } }
        InModuleScope 'OmadaSql.PS' {
            Set-OmadaSqlTempQueryObject -Context (Get-OmadaSqlConnectionContext) -Name 'TMP_x_1' -Text 'SELECT 1' -DataConnectionId 1001 | Should -Be 77
        }
        Should -Invoke Get-OmadaSqlQueryData -ModuleName 'OmadaSql.PS' -Times 1 -Exactly -ParameterFilter { $ExactName -eq 'TMP_x_1' -and $IncludeDeleted }
        Should -Invoke Invoke-OmadaSqlRequest -ModuleName 'OmadaSql.PS' -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'POST' -and $Path -eq 'odata/dataobjects/C_P_SQLTROUBLESHOOTING' -and $Body.NAME -eq 'TMP_x_1' -and $Body.C_QUERY -eq 'SELECT 1' -and $Body.C_SQLTROUBLESHOOTING_DATACONNECTION.Id -eq 1001
        }
        Should -Invoke Update-OmadaSqlQueryObject -ModuleName 'OmadaSql.PS' -Times 0 -Exactly
    }

    It 'Restores a deleted object and then updates it' {
        Mock Get-OmadaSqlQueryData -ModuleName 'OmadaSql.PS' { New-OmadaSqlTestODataQuery -Id 55 -Name 'TMP_x_1' -Deleted $true }
        Mock Invoke-OmadaSqlRequest -ModuleName 'OmadaSql.PS' { }
        InModuleScope 'OmadaSql.PS' {
            Set-OmadaSqlTempQueryObject -Context (Get-OmadaSqlConnectionContext) -Name 'TMP_x_1' -Text 'SELECT 2' -DataConnectionId 1002 | Should -Be 55
        }
        Should -Invoke Invoke-OmadaSqlRequest -ModuleName 'OmadaSql.PS' -Times 1 -Exactly -ParameterFilter { $Path -eq 'WebService/DataObjectWebService.asmx/UndeleteDataObject' -and $Body -eq '{"id":55}' }
        Should -Invoke Update-OmadaSqlQueryObject -ModuleName 'OmadaSql.PS' -Times 1 -Exactly -ParameterFilter { $Id -eq 55 -and $Body.C_QUERY -eq 'SELECT 2' -and $Body.C_SQLTROUBLESHOOTING_DATACONNECTION.Id -eq 1002 -and $Body.NAME -eq 'TMP_x_1' }
    }

    It 'Updates a live object without restoring it' {
        Mock Get-OmadaSqlQueryData -ModuleName 'OmadaSql.PS' { New-OmadaSqlTestODataQuery -Id 55 -Name 'TMP_x_1' }
        Mock Invoke-OmadaSqlRequest -ModuleName 'OmadaSql.PS' { }
        InModuleScope 'OmadaSql.PS' {
            $null = Set-OmadaSqlTempQueryObject -Context (Get-OmadaSqlConnectionContext) -Name 'TMP_x_1' -Text 'SELECT 2' -DataConnectionId 1002
        }
        Should -Invoke Invoke-OmadaSqlRequest -ModuleName 'OmadaSql.PS' -Times 0 -Exactly
        Should -Invoke Update-OmadaSqlQueryObject -ModuleName 'OmadaSql.PS' -Times 1 -Exactly
    }

    It 'Only updates when the id is already known, as for the second statement of a run' {
        Mock Get-OmadaSqlQueryData -ModuleName 'OmadaSql.PS' { throw 'must not look up' }
        InModuleScope 'OmadaSql.PS' {
            Set-OmadaSqlTempQueryObject -Context (Get-OmadaSqlConnectionContext) -Name 'TMP_x_1' -Text 'SELECT 3' -DataConnectionId 1001 -Id 1 | Should -Be 1
        }
        Should -Invoke Update-OmadaSqlQueryObject -ModuleName 'OmadaSql.PS' -Times 1 -Exactly -ParameterFilter { $Id -eq 1 }
    }
}

Describe 'Remove-OmadaSqlTempQueryObject' -Tag 'Unit' {
    BeforeAll {
        $Script:Connection = Initialize-OmadaSqlTestConnection
    }

    It 'Soft-deletes the object' {
        Mock Invoke-OmadaSqlRequest -ModuleName 'OmadaSql.PS' { }
        InModuleScope 'OmadaSql.PS' { Remove-OmadaSqlTempQueryObject -Context (Get-OmadaSqlConnectionContext) -Id 55 }
        Should -Invoke Invoke-OmadaSqlRequest -ModuleName 'OmadaSql.PS' -Times 1 -Exactly -ParameterFilter { $Method -eq 'DELETE' -and $Path -eq 'odata/dataobjects/C_P_SQLTROUBLESHOOTING(55)' }
    }

    It 'Logs a failure instead of throwing it' {
        Mock Invoke-OmadaSqlRequest -ModuleName 'OmadaSql.PS' { throw 'gone' }
        Mock Write-OmadaSqlLog -ModuleName 'OmadaSql.PS' { }
        InModuleScope 'OmadaSql.PS' { { Remove-OmadaSqlTempQueryObject -Context (Get-OmadaSqlConnectionContext) -Id 55 } | Should -Not -Throw }
        Should -Invoke Write-OmadaSqlLog -ModuleName 'OmadaSql.PS' -Times 1 -Exactly -ParameterFilter { $Message -like '*object 55*gone*' }
    }
}

Describe 'Set-OmadaSqlTempQueryObject parameter contract' -Tag 'Unit' {
    # Parameter declarations run no code a test could observe, so the mutation gate's mutants of
    # Mandatory, Position, pipeline binding and ValidateRange are caught only by asserting the contract.
    It '<Command> -<Parameter> <ParameterSet>' -ForEach @(
        @{ Command = 'Set-OmadaSqlTempQueryObject'; Parameter = 'Context'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Set-OmadaSqlTempQueryObject'; Parameter = 'Name'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Set-OmadaSqlTempQueryObject'; Parameter = 'Text'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Set-OmadaSqlTempQueryObject'; Parameter = 'DataConnectionId'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Remove-OmadaSqlTempQueryObject'; Parameter = 'Context'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Remove-OmadaSqlTempQueryObject'; Parameter = 'Id'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
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
