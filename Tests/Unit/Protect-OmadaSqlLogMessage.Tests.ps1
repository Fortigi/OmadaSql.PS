param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaSql.PS\OmadaSql.PS.psm1')
)

BeforeAll {
    Get-Module OmadaSql.PS | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Protect-OmadaSqlLogMessage' -Tag 'Unit' {
    It 'Masks <Name>' -ForEach @(
        @{ Name = 'a bearer token'; Message = 'Authorization: Bearer abcdefghijklmnop'; Secret = 'abcdefghijklmnop' }
        @{ Name = 'a JWT'; Message = 'token eyJhbGciOi.eyJzdWIiOiIx.c2lnbmF0dXJl here'; Secret = 'eyJzdWIiOiIx' }
        @{ Name = 'a JSON secret member'; Message = '{"client_secret":"s3cr3t-value"}'; Secret = 's3cr3t-value' }
        @{ Name = 'a key=value password'; Message = 'connect password=Hunter2;'; Secret = 'Hunter2' }
        @{ Name = 'a Set-Cookie value'; Message = 'Set-Cookie: oisauthtoken=abc123def'; Secret = 'abc123def' }
    ) {
        InModuleScope 'OmadaSql.PS' -Parameters @{ Message = $Message; Secret = $Secret } {
            param($Message, $Secret)
            $Result = Protect-OmadaSqlLogMessage -Message $Message
            $Result | Should -Not -BeLike "*$Secret*"
            $Result | Should -BeLike '*REDACTED*'
        }
    }

    It 'Leaves an ordinary message unchanged' {
        InModuleScope 'OmadaSql.PS' {
            Protect-OmadaSqlLogMessage -Message 'GET https://tenant.omada.cloud/odata/dataobjects/C_P_SQLTROUBLESHOOTING?$top=1' |
                Should -Be 'GET https://tenant.omada.cloud/odata/dataobjects/C_P_SQLTROUBLESHOOTING?$top=1'
        }
    }

    It 'Returns null and empty input as it came' {
        InModuleScope 'OmadaSql.PS' {
            Protect-OmadaSqlLogMessage -Message '' | Should -Be ''
            Protect-OmadaSqlLogMessage -Message $null | Should -BeNullOrEmpty
        }
    }
}
