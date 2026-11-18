param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaSql.PS\OmadaSql.PS.psm1')
)

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers\OmadaSqlTestHelper.ps1')
    Import-OmadaWebStub
    Get-Module -Name OmadaSql.PS -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $ModulePath -Force -ErrorAction Stop
}


Describe 'Get-OmadaSqlQueryHistory' -Tag 'Unit' {
    BeforeAll {
        $Script:Connection = Initialize-OmadaSqlTestConnection
        Mock Get-OmadaSqlHistoryEntry -ModuleName 'OmadaSql.PS' {
            [pscustomobject]@{ Id = $Id; Field = 'SQL Query'; NewValue = 'q' }
            [pscustomobject]@{ Id = $Id; Field = 'Name'; NewValue = 'n' }
            [pscustomobject]@{ Id = $Id; Field = $null; NewValue = $null }
        }
    }

    It 'Returns every entry by default' {
        @(Get-OmadaSqlQueryHistory -Id 101).Count | Should -Be 3
    }

    It 'Narrows to the given fields' {
        @(Get-OmadaSqlQueryHistory -Id 101 -Field 'SQL*').NewValue | Should -Be @('q')
    }

    It 'Takes the id from the pipeline' {
        @([pscustomobject]@{ Id = 7 }, [pscustomobject]@{ Id = 8 } | Get-OmadaSqlQueryHistory -Field 'Name').Id | Should -Be @(7, 8)
    }
}
