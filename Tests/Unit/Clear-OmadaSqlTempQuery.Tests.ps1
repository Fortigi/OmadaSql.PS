param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaSql.PS\OmadaSql.PS.psm1')
)

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers\OmadaSqlTestHelper.ps1')
    Import-OmadaWebStub
    Get-Module -Name OmadaSql.PS -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Clear-OmadaSqlTempQuery' -Tag 'Unit' {
    BeforeAll {
        $Script:Connection = Initialize-OmadaSqlTestConnection
    }

    BeforeEach {
        Mock Get-OmadaSqlTempQueryObject -ModuleName 'OmadaSql.PS' {
            [pscustomobject]@{ Id = 1; Name = 'TMP_a_1'; Deleted = $false; Leased = $false }
            [pscustomobject]@{ Id = 2; Name = 'TMP_a_2'; Deleted = $true; Leased = $false }
            [pscustomobject]@{ Id = 3; Name = 'TMP_a_3'; Deleted = $false; Leased = $true }
        }
        Mock Invoke-OmadaSqlRequest -ModuleName 'OmadaSql.PS' { }
    }

    It 'Soft-deletes live objects, skips deleted and leased ones, and purges nothing' {
        $Done = @(Clear-OmadaSqlTempQuery -Confirm:$false)
        @($Done.Id) | Should -Be @(1)
        $Done[0].Action | Should -Be 'Delete'
        Should -Invoke Invoke-OmadaSqlRequest -ModuleName 'OmadaSql.PS' -Times 1 -Exactly -ParameterFilter { $Method -eq 'DELETE' -and $Path -eq 'odata/dataobjects/C_P_SQLTROUBLESHOOTING(1)' }
        Should -Invoke Invoke-OmadaSqlRequest -ModuleName 'OmadaSql.PS' -Times 0 -Exactly -ParameterFilter { $Path -like '*Purge*' }
    }

    It 'With -Purge deletes live objects first, then purges every object that is not leased' {
        $Done = @(Clear-OmadaSqlTempQuery -Purge -All -Confirm:$false)
        @($Done.Action) | Should -Be @('Delete and purge', 'Purge')
        Should -Invoke Invoke-OmadaSqlRequest -ModuleName 'OmadaSql.PS' -Times 1 -Exactly -ParameterFilter { $Method -eq 'DELETE' }
        Should -Invoke Invoke-OmadaSqlRequest -ModuleName 'OmadaSql.PS' -Times 1 -Exactly -ParameterFilter { $Path -eq 'WebService/DataObjectWebService.asmx/PurgeDataObject' -and $Body -eq '{"id":1}' }
        Should -Invoke Invoke-OmadaSqlRequest -ModuleName 'OmadaSql.PS' -Times 1 -Exactly -ParameterFilter { $Path -eq 'WebService/DataObjectWebService.asmx/PurgeDataObject' -and $Body -eq '{"id":2}' }
        Should -Invoke Get-OmadaSqlTempQueryObject -ModuleName 'OmadaSql.PS' -Times 1 -Exactly -ParameterFilter { $All }
    }

    It 'Changes nothing with -WhatIf' {
        $null = Clear-OmadaSqlTempQuery -Purge -WhatIf
        Should -Invoke Invoke-OmadaSqlRequest -ModuleName 'OmadaSql.PS' -Times 0 -Exactly
    }

    It 'Asks for confirmation at High impact' {
        (Get-Command Clear-OmadaSqlTempQuery).ScriptBlock.Attributes | Where-Object { $_ -is [System.Management.Automation.CmdletBindingAttribute] } |
            ForEach-Object { [string]$_.ConfirmImpact } | Should -Be 'High'
    }
}
