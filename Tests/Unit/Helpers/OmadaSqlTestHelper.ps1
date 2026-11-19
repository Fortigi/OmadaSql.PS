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
                [switch]$Paged,
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

function New-OmadaSqlTestODataQuery {
    # A C_P_SQLTROUBLESHOOTING object as OData returns it.
    param(
        [long]$Id = 101,
        [string]$Name = 'Daily export',
        [string]$Query = 'SELECT [Id] = 1',
        [long]$DataConnectionId = 1001,
        [string]$DataConnectionName = 'OISES',
        [bool]$Deleted = $false
    )
    [pscustomobject]@{
        Id                                  = $Id
        NAME                                = $Name
        DisplayName                         = $Name
        C_QUERY                             = $Query
        C_SQLTROUBLESHOOTING_DATACONNECTION = [pscustomobject]@{ Id = $DataConnectionId; DisplayName = $DataConnectionName }
        Deleted                             = $Deleted
    }
}

function Initialize-OmadaSqlTestConnection {
    # A current connection without any request: the stub answers nothing, -SkipConnectionTest sends nothing.
    Disconnect-OmadaSql -All
    Connect-OmadaSql -Url 'https://tenant.omada.cloud' -AuthenticationType OAuth -ClientId 'client' -OAuthCertificateThumbprint 'AB12' -SkipConnectionTest -PassThru
}

function Get-OmadaSqlParameterContract {
    <#
        The declared contract of one parameter, read from the loaded command: whether it is mandatory,
        its position, whether it binds from the pipeline, and its ValidateRange bounds as text.
        Parameter declarations are not code any test executes, so only an assertion on this contract
        can tell a test run apart from one where, say, Mandatory was flipped (the mutation gate
        mutates those lines too).
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$CommandName,

        [Parameter(Mandatory = $true)]
        [string]$ParameterName,

        [string]$ParameterSetName
    )

    $Command = & (Get-Module -Name 'OmadaSql.PS') { param($Name) Get-Command -Name $Name -CommandType Function } $CommandName
    $Parameter = $Command.Parameters[$ParameterName]
    if ($null -eq $Parameter) {
        throw ("{0} has no parameter {1}." -f $CommandName, $ParameterName)
    }
    $Attribute = @($Parameter.Attributes | Where-Object {
            $_ -is [System.Management.Automation.ParameterAttribute] -and
            ([string]::IsNullOrEmpty($ParameterSetName) -or $_.ParameterSetName -eq $ParameterSetName)
        })[0]
    $Range = @($Parameter.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateRangeAttribute] })
    [pscustomobject]@{
        Mandatory                       = [bool]$Attribute.Mandatory
        Position                        = $(if ($Attribute.Position -eq [int]::MinValue) { $null } else { $Attribute.Position })
        ValueFromPipeline               = [bool]$Attribute.ValueFromPipeline
        ValueFromPipelineByPropertyName = [bool]$Attribute.ValueFromPipelineByPropertyName
        RangeMin                        = $(if ($Range.Count -gt 0) { [string]$Range[0].MinRange } else { $null })
        RangeMax                        = $(if ($Range.Count -gt 0) { [string]$Range[0].MaxRange } else { $null })
    }
}

function Get-OmadaSqlTestStatement {
    # The top-level statements of a T-SQL script, parsed by the module's own parser (real ScriptDom).
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Sql
    )
    & (Get-Module -Name 'OmadaSql.PS') {
        param($Text)
        $Parsed = ConvertTo-OmadaSqlScriptFragment -Sql $Text
        Split-OmadaSqlStatement -Fragment $Parsed.Fragment -Sql $Text
    } $Sql
}
