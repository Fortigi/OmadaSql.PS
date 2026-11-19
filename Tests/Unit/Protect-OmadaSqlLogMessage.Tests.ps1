param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaSql.PS\OmadaSql.PS.psm1')
)

BeforeAll {
    Get-Module -Name OmadaSql.PS -All | Remove-Module -Force -ErrorAction SilentlyContinue
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

Describe 'Protect-OmadaSqlLogMessage parameter contract' -Tag 'Unit' {
    # Parameter declarations run no code a test could observe, so the mutation gate's mutants of
    # Mandatory, Position, pipeline binding and ValidateRange are caught only by asserting the contract.
    It '<Command> -<Parameter> <ParameterSet>' -ForEach @(
        @{ Command = 'Protect-OmadaSqlLogMessage'; Parameter = 'Message'; ParameterSet = ''; Mandatory = $false; Position = 0; ValueFromPipeline = $true; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
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
