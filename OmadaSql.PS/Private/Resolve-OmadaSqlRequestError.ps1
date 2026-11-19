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
    $Detail = Get-OmadaSqlErrorDetail -ErrorRecord $ErrorRecord
    $UpperMethod = $Method.ToUpperInvariant()

    $KindParameter = @{
        StatusCode     = $StatusCode
        Detail         = $Detail
        Unauthorized   = (Test-OmadaSqlSessionExpiredError -ErrorRecord $ErrorRecord) -or $StatusCode -eq 401
        IsODataWrite   = $Uri -match '/odata/' -and $UpperMethod -in @('POST', 'PUT', 'PATCH', 'DELETE')
        ReadSucceeded  = $ReadSucceeded
    }
    $Kind = Get-OmadaSqlRequestErrorKind @KindParameter

    return [pscustomobject]@{
        Kind       = $Kind
        StatusCode = $StatusCode
        Message    = Get-OmadaSqlRequestErrorMessage -Kind $Kind -Method $UpperMethod -Uri $Uri -StatusCode $StatusCode -Detail $Detail
    }
}

function Get-OmadaSqlErrorDetail {
    <#
    .SYNOPSIS
    The most specific text a failed request carries: the response body when there is one.

    .DESCRIPTION
    Invoke-RestMethod puts the response body in ErrorDetails.Message; a wrapper may instead carry it
    in the exception or an inner exception. The response body comes first, followed by every distinct
    exception message in the chain, so a classification that looks for a phrase finds it wherever it
    ended up.

    PowerShell 7 re-serializes a JSON error body before it lands in ErrorDetails.Message, escaping
    characters such as the apostrophe as \u0027 (found by the integration tests). Those escapes are
    decoded, so the text reads, and matches, the same on both editions.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        $ErrorRecord
    )

    $Text = [System.Collections.Generic.List[string]]::new()
    if ($null -ne $ErrorRecord.ErrorDetails -and -not [string]::IsNullOrWhiteSpace($ErrorRecord.ErrorDetails.Message)) {
        $Text.Add([string]$ErrorRecord.ErrorDetails.Message)
    }
    $Exception = $ErrorRecord.Exception
    $Depth = 0
    while ($null -ne $Exception -and $Depth -lt 8) {
        $Depth++
        if (-not [string]::IsNullOrWhiteSpace($Exception.Message) -and -not $Text.Contains($Exception.Message)) {
            $Text.Add($Exception.Message)
        }
        $Exception = $Exception.InnerException
    }
    return [regex]::Replace(($Text -join ' | '), '\\u([0-9a-fA-F]{4})', { param($Match) [string][char][Convert]::ToInt32($Match.Groups[1].Value, 16) })
}

function Get-OmadaSqlRequestErrorKind {
    <#
    .SYNOPSIS
    The error kind of a failed request, from facts already extracted from the error.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()]
        [System.Nullable[int]]$StatusCode,

        [AllowEmptyString()]
        [string]$Detail,

        [bool]$Unauthorized,

        [bool]$IsODataWrite,

        [bool]$ReadSucceeded
    )

    # Matched on the two parts rather than on the exact sentence: the quoting around the segment
    # name differs between how Omada sends it and how each PowerShell edition reports it.
    if ($Detail -like '*Resource not found for the segment*C_P_SQLTROUBLESHOOTING*') {
        return 'EndpointNotEnabled'
    }
    if ($Unauthorized) {
        if ($IsODataWrite -and $ReadSucceeded) {
            return 'MissingPermission'
        }
        return 'SessionExpired'
    }
    if ($null -eq $StatusCode) {
        return 'RequestFailed'
    }

    $KindByStatusCode = @{ 403 = 'AccessDenied'; 404 = 'NotFound' }
    if ($KindByStatusCode.ContainsKey([int]$StatusCode)) {
        return $KindByStatusCode[[int]$StatusCode]
    }
    if ($StatusCode -ge 500) {
        return 'ServerError'
    }
    return 'RequestFailed'
}

function Get-OmadaSqlRequestErrorMessage {
    <#
    .SYNOPSIS
    The message for an error kind: what happened and, where there is one, what to do about it.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Kind,

        [Parameter(Mandatory = $true)]
        [string]$Method,

        [Parameter(Mandatory = $true)]
        [string]$Uri,

        [AllowNull()]
        [System.Nullable[int]]$StatusCode,

        [AllowEmptyString()]
        [string]$Detail
    )

    $HostName = ([System.Uri]$Uri).Host
    switch ($Kind) {
        'EndpointNotEnabled' {
            return "The OData endpoint for SQL Troubleshooting (C_P_SQLTROUBLESHOOTING) is not enabled on tenant '{0}'." -f $HostName
        }
        'MissingPermission' {
            $Permission = @{ POST = 'Create'; DELETE = 'Delete' }[$Method]
            if ($null -eq $Permission) {
                $Permission = 'Update'
            }
            return ("Omada refused {0} {1} (HTTP 401) although this connection read from tenant '{2}' successfully. Omada's OData answers a missing permission with 401, so the identity most likely lacks the '{3}' permission on the 'OData' auth element. " +
                "Running an existing query needs Read; an ad-hoc query needs Read, Create, Update and Delete. Signing in again will not help.") -f $Method, $Uri, $HostName, $Permission
        }
        'SessionExpired' {
            return "There is no valid session for tenant '{0}' (HTTP 401). Run Connect-OmadaSql again, or check the client id, certificate and the Omada mapping of the service principal." -f $HostName
        }
        'AccessDenied' {
            return "Access to {0} {1} was denied (HTTP 403): {2}" -f $Method, $Uri, $Detail
        }
        'NotFound' {
            return "{0} {1} was not found (HTTP 404): {2}" -f $Method, $Uri, $Detail
        }
        'ServerError' {
            return "Omada returned HTTP {0} for {1} {2}. A SQL error in SQL Troubleshooting is reported this way. Details: {3}" -f $StatusCode, $Method, $Uri, $Detail
        }
        default {
            return "The request {0} {1} failed: {2}" -f $Method, $Uri, $Detail
        }
    }
}
