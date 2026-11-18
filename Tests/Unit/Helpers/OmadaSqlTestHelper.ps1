<#
    Shared helpers for the unit tests. Dot-source from a test file's BeforeAll:

        . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers\OmadaSqlTestHelper.ps1')

    Import-OmadaWebStub replaces OmadaWeb.PS with an in-memory module of the same name whose
    Invoke-OmadaRestMethod declares, statically, the parameters this module passes. The real command
    adds its parameters through DynamicParam (some of them depending on the Edge profiles on the
    machine), which makes Pester mocks of it depend on the machine they run on. Tests mock the stub
    instead, with -ModuleName OmadaSql.PS, so every call the module makes is intercepted and the
    parameter filters can read each parameter by name.

    New-OmadaSqlTestHttpError builds the ErrorRecord an HTTP failure produces, with an exception
    whose Response.StatusCode is set, and optionally ErrorDetails (where Invoke-RestMethod puts the
    response body).
#>

if (-not ('OmadaSqlPSTests.FakeHttpException' -as [type])) {
    Add-Type -TypeDefinition @'
namespace OmadaSqlPSTests
{
    public class FakeResponse
    {
        public int StatusCode { get; set; }
    }

    public class FakeHttpException : System.Exception
    {
        public FakeHttpException(string message, int statusCode) : base(message)
        {
            Response = new FakeResponse { StatusCode = statusCode };
        }

        public FakeResponse Response { get; private set; }
    }
}
'@
}

function Import-OmadaWebStub {
    Get-Module -Name 'OmadaWeb.PS' -All | Remove-Module -Force -ErrorAction SilentlyContinue
    $Stub = New-Module -Name 'OmadaWeb.PS' -ScriptBlock {
        function Invoke-OmadaRestMethod {
            [CmdletBinding()]
            param(
                [System.Uri]$Uri,
                [string]$Method,
                [object]$Body,
                [string]$ContentType,
                [string]$AuthenticationType,
                [string]$SessionKey,
                [string]$ClientId,
                [string]$OAuthCertificateThumbprint,
                [string]$OAuthCertificatePath,
                [System.Security.SecureString]$OAuthCertificatePassword,
                [System.Security.Cryptography.X509Certificates.X509Certificate2]$OAuthCertificate,
                [System.Management.Automation.PSCredential]$Credential,
                [string]$EntraIdTenantId,
                [string]$EntraApplicationIdUri,
                [string]$OAuthScope,
                [string]$OAuthUri,
                [switch]$NoInteractiveAuthentication,
                [switch]$ForceAuthentication,
                [int]$MaximumRetryCount,
                [string]$UserName
            )
            throw 'The OmadaWeb.PS test stub was called without a mock. Mock Invoke-OmadaRestMethod -ModuleName OmadaSql.PS in the test.'
        }
        Export-ModuleMember -Function 'Invoke-OmadaRestMethod'
    }
    $Stub | Import-Module -Global -Force
}

function New-OmadaSqlTestHttpError {
    param(
        [Parameter(Mandatory = $true)]
        [int]$StatusCode,

        [string]$Message = ('Response status code does not indicate success: {0}.' -f $StatusCode),

        [string]$Detail
    )

    $Exception = [OmadaSqlPSTests.FakeHttpException]::new($Message, $StatusCode)
    $ErrorRecord = [System.Management.Automation.ErrorRecord]::new($Exception, 'WebCmdletWebResponseException', [System.Management.Automation.ErrorCategory]::InvalidOperation, $null)
    if (-not [string]::IsNullOrEmpty($Detail)) {
        $ErrorRecord.ErrorDetails = [System.Management.Automation.ErrorDetails]::new($Detail)
    }
    return $ErrorRecord
}

function New-OmadaSqlTestSessionExpiredError {
    $Exception = [System.Security.Authentication.AuthenticationException]::new('There is no valid Omada session.')
    return [System.Management.Automation.ErrorRecord]::new($Exception, 'OmadaSessionExpired,Invoke-OmadaRestMethod', [System.Management.Automation.ErrorCategory]::AuthenticationError, $null)
}
