param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaSql.PS\OmadaSql.PS.psm1')
)

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers\OmadaSqlTestHelper.ps1')
    Import-OmadaWebStub
    Get-Module -Name OmadaSql.PS -All | Remove-Module -Force -ErrorAction SilentlyContinue
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

    It 'Does not pass on a parameter that was supplied as null' {
        InModuleScope 'OmadaSql.PS' {
            $Result = New-OmadaSqlRequestParameter -BoundParameter @{ EntraIdTenantId = $null; OAuthScope = 'scope' } -AuthenticationType 'Browser' -SessionKey 'key'
            $Result.ContainsKey('EntraIdTenantId') | Should -BeFalse
            $Result.OAuthScope | Should -Be 'scope'
        }
    }

    It 'Does not pass on a parameter it does not know' {
        InModuleScope 'OmadaSql.PS' {
            (New-OmadaSqlRequestParameter -BoundParameter @{ Uri = 'https://elsewhere.example.com' } -AuthenticationType 'Browser' -SessionKey 'key').ContainsKey('Uri') | Should -BeFalse
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

Describe 'Assert-OmadaSqlAuthenticationParameter' -Tag 'Unit' {
    It 'Accepts <Case>' -ForEach @(
        @{ Case = 'OAuth with a client id and one certificate source'; Type = 'OAuth'; Parameter = @{ ClientId = 'client'; OAuthCertificate = 'cert' } }
        @{ Case = 'OAuth with a credential'; Type = 'OAuth'; Parameter = @{ Credential = 'credential' } }
        @{ Case = 'Browser without anything'; Type = 'Browser'; Parameter = @{} }
        @{ Case = 'Integrated without anything'; Type = 'Integrated'; Parameter = @{} }
        @{ Case = 'Basic with a credential'; Type = 'Basic'; Parameter = @{ Credential = 'credential' } }
    ) {
        InModuleScope 'OmadaSql.PS' -Parameters @{ Type = $Type; Parameter = $Parameter } {
            param($Type, $Parameter)
            { Assert-OmadaSqlAuthenticationParameter -Parameter $Parameter -AuthenticationType $Type } | Should -Not -Throw
        }
    }

    It 'Accepts OAuth with a certificate and a credential, as long as there is a client id' {
        InModuleScope 'OmadaSql.PS' {
            { Assert-OmadaSqlAuthenticationParameter -Parameter @{ ClientId = 'client'; OAuthCertificateThumbprint = 'AB12'; Credential = 'credential' } -AuthenticationType 'OAuth' } | Should -Not -Throw
        }
    }
}

Describe 'Add-OmadaSqlAdditionalParameter' -Tag 'Unit' {
    BeforeEach {
        InModuleScope 'OmadaSql.PS' { $Script:OmadaSqlRestMethodParameterCache = $null }
    }

    It 'Adds every allowed entry and leaves the existing ones alone' {
        InModuleScope 'OmadaSql.PS' {
            $Parameter = @{ AuthenticationType = 'OAuth' }
            Add-OmadaSqlAdditionalParameter -Parameter $Parameter -AdditionalParameter @{ MaximumRetryCount = 2; UserName = 'admin' } -ReservedName @('Uri')
            $Parameter.MaximumRetryCount | Should -Be 2
            $Parameter.UserName | Should -Be 'admin'
            $Parameter.AuthenticationType | Should -Be 'OAuth'
        }
    }

    It 'Adds nothing for an empty table' {
        InModuleScope 'OmadaSql.PS' {
            $Parameter = @{ AuthenticationType = 'OAuth' }
            Add-OmadaSqlAdditionalParameter -Parameter $Parameter -AdditionalParameter @{} -ReservedName @('Uri')
            $Parameter.Count | Should -Be 1
        }
    }
}
