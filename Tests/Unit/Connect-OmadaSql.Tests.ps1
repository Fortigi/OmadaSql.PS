param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaSql.PS\OmadaSql.PS.psm1')
)

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers\OmadaSqlTestHelper.ps1')
    Import-OmadaWebStub
    Get-Module OmadaSql.PS | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Connect-OmadaSql' -Tag 'Unit' {
    BeforeEach {
        Disconnect-OmadaSql -All
        InModuleScope 'OmadaSql.PS' { $Script:OmadaSqlRestMethodParameterCache = $null }
    }

    It 'Verifies the connection by reading one SQL Troubleshooting object' {
        Mock Invoke-OmadaRestMethod -ModuleName 'OmadaSql.PS' { [pscustomobject]@{ value = @() } }

        $Connection = Connect-OmadaSql -Url 'https://tenant.omada.cloud/' -AuthenticationType OAuth -ClientId 'client' -OAuthCertificateThumbprint 'AB12' -EntraIdTenantId 'contoso' -PassThru

        $Connection.BaseUrl | Should -Be 'https://tenant.omada.cloud'
        $Connection.Verified | Should -BeTrue
        $Connection.ClientId | Should -Be 'client'
        $Connection.PSObject.TypeNames | Should -Contain 'OmadaSql.Connection'
        Should -Invoke Invoke-OmadaRestMethod -ModuleName 'OmadaSql.PS' -Times 1 -Exactly -ParameterFilter {
            [string]$Uri -eq 'https://tenant.omada.cloud/odata/dataobjects/C_P_SQLTROUBLESHOOTING?$top=1' -and
            $Method -eq 'GET' -and
            $AuthenticationType -eq 'OAuth' -and
            $OAuthCertificateThumbprint -eq 'AB12' -and
            $EntraIdTenantId -eq 'contoso' -and
            $SessionKey -eq 'OmadaSql.PS'
        }
    }

    It 'Makes the new connection current' {
        Mock Invoke-OmadaRestMethod -ModuleName 'OmadaSql.PS' { $null }

        $First = Connect-OmadaSql -Url 'https://one.omada.cloud' -PassThru
        $Second = Connect-OmadaSql -Url 'https://two.omada.cloud' -PassThru

        (Get-OmadaSqlConnection).Id | Should -Be $Second.Id
        @(Get-OmadaSqlConnection -All).Id | Should -Be @($First.Id, $Second.Id)
    }

    It 'Returns nothing without -PassThru' {
        Mock Invoke-OmadaRestMethod -ModuleName 'OmadaSql.PS' { $null }
        Connect-OmadaSql -Url 'https://tenant.omada.cloud' | Should -BeNullOrEmpty
    }

    It 'Never exposes the credential or certificate parameters on the connection object' {
        Mock Invoke-OmadaRestMethod -ModuleName 'OmadaSql.PS' { $null }
        $Credential = [System.Management.Automation.PSCredential]::new('client', (ConvertTo-SecureString -String 'super-secret' -AsPlainText -Force))

        $Connection = Connect-OmadaSql -Url 'https://tenant.omada.cloud' -AuthenticationType OAuth -Credential $Credential -PassThru

        $Connection.ClientId | Should -Be 'client'
        foreach ($Property in $Connection.PSObject.Properties) {
            $Property.Value | Should -Not -BeOfType [System.Management.Automation.PSCredential]
            $Property.Value | Should -Not -BeOfType [System.Security.SecureString]
        }
        ($Connection | ConvertTo-Json) | Should -Not -BeLike '*super-secret*'
    }

    It 'Skips the verification request with -SkipConnectionTest' {
        Mock Invoke-OmadaRestMethod -ModuleName 'OmadaSql.PS' { $null }

        $Connection = Connect-OmadaSql -Url 'https://tenant.omada.cloud' -SkipConnectionTest -PassThru

        $Connection.Verified | Should -BeFalse
        Should -Invoke Invoke-OmadaRestMethod -ModuleName 'OmadaSql.PS' -Times 0 -Exactly
    }

    It 'Passes NoInteractiveAuthentication on every request' {
        Mock Invoke-OmadaRestMethod -ModuleName 'OmadaSql.PS' { $null }

        Connect-OmadaSql -Url 'https://tenant.omada.cloud' -AuthenticationType Browser -NoInteractiveAuthentication

        Should -Invoke Invoke-OmadaRestMethod -ModuleName 'OmadaSql.PS' -Times 1 -Exactly -ParameterFilter { $NoInteractiveAuthentication -eq $true }
    }

    It 'Fails with EndpointNotEnabled, and keeps no connection, when the OData endpoint is missing' {
        Mock Invoke-OmadaRestMethod -ModuleName 'OmadaSql.PS' { throw (New-OmadaSqlTestHttpError -StatusCode 404 -Detail "Resource not found for the segment 'C_P_SQLTROUBLESHOOTING'.") }

        { Connect-OmadaSql -Url 'https://tenant.omada.cloud' } | Should -Throw -ErrorId 'OmadaSql.EndpointNotEnabled,Connect-OmadaSql'
        Get-OmadaSqlConnection -All | Should -BeNullOrEmpty
    }

    It 'Refuses an http URL before sending anything' {
        Mock Invoke-OmadaRestMethod -ModuleName 'OmadaSql.PS' { $null }

        { Connect-OmadaSql -Url 'http://tenant.omada.cloud' } | Should -Throw -ErrorId 'OmadaSql.InvalidArgument,Connect-OmadaSql'
        Should -Invoke Invoke-OmadaRestMethod -ModuleName 'OmadaSql.PS' -Times 0 -Exactly
    }

    It 'Refuses OAuth without a certificate or credential before sending anything' {
        Mock Invoke-OmadaRestMethod -ModuleName 'OmadaSql.PS' { $null }

        { Connect-OmadaSql -Url 'https://tenant.omada.cloud' -AuthenticationType OAuth -ClientId 'client' } | Should -Throw -ErrorId 'OmadaSql.InvalidArgument,Connect-OmadaSql'
        Should -Invoke Invoke-OmadaRestMethod -ModuleName 'OmadaSql.PS' -Times 0 -Exactly
    }
}
