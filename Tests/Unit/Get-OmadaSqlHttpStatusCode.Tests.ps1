param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaSql.PS\OmadaSql.PS.psm1')
)

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers\OmadaSqlTestHelper.ps1')
    Get-Module OmadaSql.PS | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $ModulePath -Force -ErrorAction Stop
    $Script:ODataUri = 'https://tenant.omada.cloud/odata/dataobjects/C_P_SQLTROUBLESHOOTING'
}

Describe 'Get-OmadaSqlHttpStatusCode' -Tag 'Unit' {
    It 'Reads Exception.Response.StatusCode' {
        $ErrorRecord = New-OmadaSqlTestHttpError -StatusCode 418 -Message 'no code in this text'
        InModuleScope 'OmadaSql.PS' -Parameters @{ ErrorRecord = $ErrorRecord } {
            param($ErrorRecord)
            Get-OmadaSqlHttpStatusCode -ErrorRecord $ErrorRecord | Should -Be 418
        }
    }

    It 'Falls back to the <Edition> message format' -ForEach @(
        @{ Edition = 'PowerShell 7'; Message = 'Response status code does not indicate success: 401 (Unauthorized).'; Expected = 401 }
        @{ Edition = 'Windows PowerShell'; Message = 'The remote server returned an error: (403) Forbidden.'; Expected = 403 }
    ) {
        $ErrorRecord = [System.Management.Automation.ErrorRecord]::new([System.Exception]::new($Message), 'Test', [System.Management.Automation.ErrorCategory]::InvalidOperation, $null)
        InModuleScope 'OmadaSql.PS' -Parameters @{ ErrorRecord = $ErrorRecord; Expected = $Expected } {
            param($ErrorRecord, $Expected)
            Get-OmadaSqlHttpStatusCode -ErrorRecord $ErrorRecord | Should -Be $Expected
        }
    }

    It 'Returns null for an error without a status code, and for no error' {
        $ErrorRecord = [System.Management.Automation.ErrorRecord]::new([System.Exception]::new('boom'), 'Test', [System.Management.Automation.ErrorCategory]::InvalidOperation, $null)
        InModuleScope 'OmadaSql.PS' -Parameters @{ ErrorRecord = $ErrorRecord } {
            param($ErrorRecord)
            Get-OmadaSqlHttpStatusCode -ErrorRecord $ErrorRecord | Should -BeNullOrEmpty
            Get-OmadaSqlHttpStatusCode -ErrorRecord $null | Should -BeNullOrEmpty
        }
    }
}
