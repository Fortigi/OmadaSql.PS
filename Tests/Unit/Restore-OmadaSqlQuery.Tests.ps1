param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaSql.PS\OmadaSql.PS.psm1')
)

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers\OmadaSqlTestHelper.ps1')
    Import-OmadaWebStub
    Get-Module -Name OmadaSql.PS -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $ModulePath -Force -ErrorAction Stop
}


Describe 'Restore-OmadaSqlQuery' -Tag 'Unit' {
    BeforeEach {
        $Script:Connection = Initialize-OmadaSqlTestConnection
        Mock Invoke-OmadaSqlRequest -ModuleName 'OmadaSql.PS' { [pscustomobject]@{ d = $null } }
        Mock Get-OmadaSqlQueryData -ModuleName 'OmadaSql.PS' { New-OmadaSqlTestODataQuery -Id $Id }
    }

    It 'Calls UndeleteDataObject with the id as a JSON string, and returns the object' {
        (Restore-OmadaSqlQuery -Id 7).Id | Should -Be 7
        Should -Invoke Invoke-OmadaSqlRequest -ModuleName 'OmadaSql.PS' -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'POST' -and $Path -eq 'WebService/DataObjectWebService.asmx/UndeleteDataObject' -and $Body -eq '{"id":7}'
        }
        Should -Invoke Get-OmadaSqlQueryData -ModuleName 'OmadaSql.PS' -Times 1 -Exactly -ParameterFilter { $Id -eq 7 -and $IncludeDeleted }
    }

    It 'Sends nothing with -WhatIf' {
        $null = Restore-OmadaSqlQuery -Id 7 -WhatIf
        Should -Invoke Invoke-OmadaSqlRequest -ModuleName 'OmadaSql.PS' -Times 0 -Exactly
    }
}
