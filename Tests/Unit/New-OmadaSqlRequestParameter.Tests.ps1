param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaSql.PS\OmadaSql.PS.psm1')
)

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers\OmadaSqlTestHelper.ps1')
    Import-OmadaWebStub
    Get-Module OmadaSql.PS | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'New-OmadaSqlRequestParameter' -Tag 'Unit' {
    BeforeEach {
        InModuleScope 'OmadaSql.PS' { $Script:OmadaSqlRestMethodParameterCache = $null }
    }

    It 'Passes the certificate parameters on for OAuth' {
        InModuleScope 'OmadaSql.PS' {
            $Result = New-OmadaSqlRequestParameter -BoundParameter @{ ClientId = 'client'; OAuthCertificateThumbprint = 'AB12'; EntraIdTenantId = 'contoso' } -AuthenticationType 'OAuth' -SessionKey 'key'
            $Result.AuthenticationType | Should -Be 'OAuth'
            $Result.SessionKey | Should -Be 'key'
            $Result.ClientId | Should -Be 'client'
            $Result.OAuthCertificateThumbprint | Should -Be 'AB12'
            $Result.EntraIdTenantId | Should -Be 'contoso'
            $Result.ContainsKey('NoInteractiveAuthentication') | Should -BeFalse
        }
    }

    It 'Accepts the client secret flow with only a credential' {
        InModuleScope 'OmadaSql.PS' {
            $Credential = [System.Management.Automation.PSCredential]::new('client', (ConvertTo-SecureString -String 'secret' -AsPlainText -Force))
            $Result = New-OmadaSqlRequestParameter -BoundParameter @{ Credential = $Credential } -AuthenticationType 'OAuth' -SessionKey 'key'
            $Result.Credential.UserName | Should -Be 'client'
        }
    }

    It 'Drops an empty credential' {
        InModuleScope 'OmadaSql.PS' {
            $Result = New-OmadaSqlRequestParameter -BoundParameter @{ Credential = [System.Management.Automation.PSCredential]::Empty } -AuthenticationType 'Browser' -SessionKey 'key'
            $Result.ContainsKey('Credential') | Should -BeFalse
        }
    }

    It 'Refuses OAuth <Case>' -ForEach @(
        @{ Case = 'without a certificate or credential'; Bound = @{ ClientId = 'client' } }
        @{ Case = 'with a certificate but no client id'; Bound = @{ OAuthCertificateThumbprint = 'AB12' } }
        @{ Case = 'with two certificate sources'; Bound = @{ ClientId = 'client'; OAuthCertificateThumbprint = 'AB12'; OAuthCertificatePath = 'C:\cert.pfx' } }
    ) {
        InModuleScope 'OmadaSql.PS' -Parameters @{ Bound = $Bound } {
            param($Bound)
            { New-OmadaSqlRequestParameter -BoundParameter $Bound -AuthenticationType 'OAuth' -SessionKey 'key' } | Should -Throw -ErrorId 'OmadaSql.InvalidArgument'
        }
    }

    It 'Refuses <Type> without a credential' -ForEach @(
        @{ Type = 'Windows' }
        @{ Type = 'Basic' }
    ) {
        InModuleScope 'OmadaSql.PS' -Parameters @{ Type = $Type } {
            param($Type)
            { New-OmadaSqlRequestParameter -BoundParameter @{} -AuthenticationType $Type -SessionKey 'key' } | Should -Throw -ErrorId 'OmadaSql.InvalidArgument'
        }
    }

    It 'Adds NoInteractiveAuthentication when the installed OmadaWeb.PS supports it' {
        InModuleScope 'OmadaSql.PS' {
            (New-OmadaSqlRequestParameter -BoundParameter @{} -AuthenticationType 'Browser' -SessionKey 'key' -NoInteractiveAuthentication).NoInteractiveAuthentication | Should -BeTrue
        }
    }

    It 'Refuses NoInteractiveAuthentication when the installed OmadaWeb.PS lacks it' {
        InModuleScope 'OmadaSql.PS' {
            $Script:OmadaSqlRestMethodParameterCache = @('Uri', 'Method')
            { New-OmadaSqlRequestParameter -BoundParameter @{} -AuthenticationType 'Browser' -SessionKey 'key' -NoInteractiveAuthentication } | Should -Throw -ErrorId 'OmadaSql.InvalidArgument'
        }
    }

    It 'Passes an additional Invoke-OmadaRestMethod parameter on' {
        InModuleScope 'OmadaSql.PS' {
            (New-OmadaSqlRequestParameter -BoundParameter @{} -AuthenticationType 'Browser' -SessionKey 'key' -AdditionalParameter @{ MaximumRetryCount = 5 }).MaximumRetryCount | Should -Be 5
        }
    }

    It 'Refuses an additional parameter that <Case>' -ForEach @(
        @{ Case = 'Invoke-OmadaRestMethod does not have'; Additional = @{ NotAParameter = 1 } }
        @{ Case = 'the module sets per request'; Additional = @{ Uri = 'https://elsewhere.example.com' } }
        @{ Case = 'would override the authentication'; Additional = @{ AuthenticationType = 'None' } }
    ) {
        InModuleScope 'OmadaSql.PS' -Parameters @{ Additional = $Additional } {
            param($Additional)
            { New-OmadaSqlRequestParameter -BoundParameter @{} -AuthenticationType 'Browser' -SessionKey 'key' -AdditionalParameter $Additional } | Should -Throw -ErrorId 'OmadaSql.InvalidArgument'
        }
    }
}
