function Test-OmadaSqlSessionExpiredError {
    <#
    .SYNOPSIS
    Whether an error is OmadaWeb.PS reporting that there is no usable session.

    .DESCRIPTION
    With -NoInteractiveAuthentication, OmadaWeb.PS raises a terminating error instead of signing in
    when there is no session or the server answers 401. Its FullyQualifiedErrorId starts with
    'OmadaSessionExpired' and its exception is a System.Security.Authentication.AuthenticationException
    (documented on OmadaWeb.PS's -NoInteractiveAuthentication). The exception chain is walked because
    the error can arrive wrapped.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [AllowNull()]
        $ErrorRecord
    )

    if ($null -eq $ErrorRecord) {
        return $false
    }

    if ([string]$ErrorRecord.FullyQualifiedErrorId -like 'OmadaSessionExpired*') {
        return $true
    }

    $Exception = $ErrorRecord.Exception
    $Depth = 0
    while ($null -ne $Exception -and $Depth -lt 16) {
        $Depth++
        foreach ($TypeName in @($Exception.PSObject.TypeNames)) {
            if ($TypeName -eq 'System.Security.Authentication.AuthenticationException' -or $TypeName -eq 'Deserialized.System.Security.Authentication.AuthenticationException') {
                return $true
            }
        }
        $Exception = $Exception.InnerException
    }

    return $false
}
