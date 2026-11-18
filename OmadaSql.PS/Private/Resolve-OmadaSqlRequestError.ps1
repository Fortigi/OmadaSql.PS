function Resolve-OmadaSqlRequestError {
    <#
    .SYNOPSIS
    Classifies a failed Omada request and describes what the caller can do about it.

    .DESCRIPTION
    Pure: decides from the error, the request method and URI, and whether this connection already
    read from the tenant successfully. Kinds:

      EndpointNotEnabled  The C_P_SQLTROUBLESHOOTING OData endpoint does not exist on the tenant.
      MissingPermission   A write to /odata/ was refused with 401 (or the session-expired error
                          OmadaWeb.PS turns a 401 into) after a read succeeded. Omada's OData answers
                          a missing permission with 401, so signing in again does not help.
      SessionExpired      No usable session (OmadaWeb.PS -NoInteractiveAuthentication) or 401.
      AccessDenied        403.
      NotFound            404.
      ServerError         5xx. A SQL error in SQL Troubleshooting arrives as a generic 500.
      RequestFailed       Anything else.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        $ErrorRecord,

        [Parameter(Mandatory = $true)]
        [string]$Method,

        [Parameter(Mandatory = $true)]
        [string]$Uri,

        [bool]$ReadSucceeded = $false
    )

    $StatusCode = Get-OmadaSqlHttpStatusCode -ErrorRecord $ErrorRecord
    $SessionExpired = Test-OmadaSqlSessionExpiredError -ErrorRecord $ErrorRecord
    $Detail = [string]$ErrorRecord.Exception.Message
    if ($null -ne $ErrorRecord.ErrorDetails -and -not [string]::IsNullOrWhiteSpace($ErrorRecord.ErrorDetails.Message)) {
        $Detail = [string]$ErrorRecord.ErrorDetails.Message
    }
    $HostName = ([System.Uri]$Uri).Host
    $UpperMethod = $Method.ToUpperInvariant()
    $IsODataWrite = $Uri -match '/odata/' -and $UpperMethod -in @('POST', 'PUT', 'PATCH', 'DELETE')

    $Kind = 'RequestFailed'
    $Message = "The request {0} {1} failed: {2}" -f $UpperMethod, $Uri, $Detail

    if ($Detail -like "*Resource not found for the segment 'C_P_SQLTROUBLESHOOTING'*") {
        $Kind = 'EndpointNotEnabled'
        $Message = "The OData endpoint for SQL Troubleshooting (C_P_SQLTROUBLESHOOTING) is not enabled on tenant '{0}'." -f $HostName
    }
    elseif ($IsODataWrite -and $ReadSucceeded -and ($SessionExpired -or $StatusCode -eq 401)) {
        $Permission = switch ($UpperMethod) {
            'POST' { 'Create' }
            'DELETE' { 'Delete' }
            default { 'Update' }
        }
        $Kind = 'MissingPermission'
        $Message = ("Omada refused {0} {1} (HTTP 401) although this connection read from tenant '{2}' successfully. Omada's OData answers a missing permission with 401, so the identity most likely lacks the '{3}' permission on the 'OData' auth element. " +
            "Running an existing query needs Read; an ad-hoc query needs Read, Create, Update and Delete. Signing in again will not help.") -f $UpperMethod, $Uri, $HostName, $Permission
    }
    elseif ($SessionExpired -or $StatusCode -eq 401) {
        $Kind = 'SessionExpired'
        $Message = "There is no valid session for tenant '{0}' (HTTP 401). Run Connect-OmadaSql again, or check the client id, certificate and the Omada mapping of the service principal." -f $HostName
    }
    elseif ($StatusCode -eq 403) {
        $Kind = 'AccessDenied'
        $Message = "Access to {0} {1} was denied (HTTP 403): {2}" -f $UpperMethod, $Uri, $Detail
    }
    elseif ($StatusCode -eq 404) {
        $Kind = 'NotFound'
        $Message = "{0} {1} was not found (HTTP 404): {2}" -f $UpperMethod, $Uri, $Detail
    }
    elseif ($null -ne $StatusCode -and $StatusCode -ge 500) {
        $Kind = 'ServerError'
        $Message = "Omada returned HTTP {0} for {1} {2}. A SQL error in SQL Troubleshooting is reported this way. Details: {3}" -f $StatusCode, $UpperMethod, $Uri, $Detail
    }

    return [pscustomobject]@{
        Kind       = $Kind
        StatusCode = $StatusCode
        Message    = $Message
    }
}
