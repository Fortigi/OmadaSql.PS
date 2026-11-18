param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaSql.PS\OmadaSql.PS.psm1')
)

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers\OmadaSqlTestHelper.ps1')
    Import-OmadaWebStub
    Get-Module -Name OmadaSql.PS -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $ModulePath -Force -ErrorAction Stop
}


Describe 'Remove-OmadaSqlQuery' -Tag 'Unit' {
    BeforeEach {
        $Script:Connection = Initialize-OmadaSqlTestConnection
        Mock Invoke-OmadaSqlRequest -ModuleName 'OmadaSql.PS' { $null }
    }

    It 'DELETEs the object over OData' {
        Remove-OmadaSqlQuery -Id 7 -Confirm:$false
        Should -Invoke Invoke-OmadaSqlRequest -ModuleName 'OmadaSql.PS' -Times 1 -Exactly -ParameterFilter { $Method -eq 'DELETE' -and $Path -eq 'odata/dataobjects/C_P_SQLTROUBLESHOOTING(7)' }
    }

    It 'Deletes every piped object' {
        [pscustomobject]@{ Id = 7 }, [pscustomobject]@{ Id = 8 } | Remove-OmadaSqlQuery -Confirm:$false
        Should -Invoke Invoke-OmadaSqlRequest -ModuleName 'OmadaSql.PS' -Times 2 -Exactly
    }

    It 'Sends nothing with -WhatIf' {
        Remove-OmadaSqlQuery -Id 7 -WhatIf
        Should -Invoke Invoke-OmadaSqlRequest -ModuleName 'OmadaSql.PS' -Times 0 -Exactly
    }

    It 'Declares a medium confirm impact, as the delete can be undone' {
        (Get-Command -Name Remove-OmadaSqlQuery).ScriptBlock.Attributes.Where({ $_ -is [System.Management.Automation.CmdletBindingAttribute] })[0].ConfirmImpact | Should -Be 'Medium'
    }
}
