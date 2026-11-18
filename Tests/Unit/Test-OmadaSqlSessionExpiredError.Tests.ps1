param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaSql.PS\OmadaSql.PS.psm1')
)

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers\OmadaSqlTestHelper.ps1')
    Get-Module -Name OmadaSql.PS -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $ModulePath -Force -ErrorAction Stop
    $Script:ODataUri = 'https://tenant.omada.cloud/odata/dataobjects/C_P_SQLTROUBLESHOOTING'
}

Describe 'Test-OmadaSqlSessionExpiredError' -Tag 'Unit' {
    It 'Recognises the OmadaSessionExpired error id' {
        $ErrorRecord = New-OmadaSqlTestSessionExpiredError
        InModuleScope 'OmadaSql.PS' -Parameters @{ ErrorRecord = $ErrorRecord } {
            param($ErrorRecord)
            Test-OmadaSqlSessionExpiredError -ErrorRecord $ErrorRecord | Should -BeTrue
        }
    }

    It 'Recognises an AuthenticationException wrapped in another exception' {
        $Inner = [System.Security.Authentication.AuthenticationException]::new('expired')
        $ErrorRecord = [System.Management.Automation.ErrorRecord]::new([System.Exception]::new('outer', $Inner), 'Wrapped', [System.Management.Automation.ErrorCategory]::InvalidOperation, $null)
        InModuleScope 'OmadaSql.PS' -Parameters @{ ErrorRecord = $ErrorRecord } {
            param($ErrorRecord)
            Test-OmadaSqlSessionExpiredError -ErrorRecord $ErrorRecord | Should -BeTrue
        }
    }

    It 'Returns false for an ordinary error and for no error' {
        $ErrorRecord = New-OmadaSqlTestHttpError -StatusCode 500
        InModuleScope 'OmadaSql.PS' -Parameters @{ ErrorRecord = $ErrorRecord } {
            param($ErrorRecord)
            Test-OmadaSqlSessionExpiredError -ErrorRecord $ErrorRecord | Should -BeFalse
            Test-OmadaSqlSessionExpiredError -ErrorRecord $null | Should -BeFalse
        }
    }
}
