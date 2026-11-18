function New-OmadaSqlRequestParameter {
    <#
    .SYNOPSIS
    Builds the Invoke-OmadaRestMethod parameters a connection sends on every request.

    .DESCRIPTION
    Copies the authentication parameters Connect-OmadaSql was called with, validates the OAuth
    combinations up front (so a scheduled task fails with a clear message instead of an identity
    provider error), and adds -NoInteractiveAuthentication when it is asked for and the installed
    OmadaWeb.PS supports it. Every key of -AdditionalParameter must be a parameter of the installed
    Invoke-OmadaRestMethod, and may not override what the module sets per request.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds an object in memory and changes no state.')]
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$BoundParameter,

        [Parameter(Mandatory = $true)]
        [string]$AuthenticationType,

        [Parameter(Mandatory = $true)]
        [string]$SessionKey,

        [hashtable]$AdditionalParameter = @{},

        [switch]$NoInteractiveAuthentication
    )

    $PassThroughName = @(
        'ClientId', 'OAuthCertificateThumbprint', 'OAuthCertificatePath', 'OAuthCertificatePassword', 'OAuthCertificate',
        'Credential', 'EntraIdTenantId', 'EntraApplicationIdUri', 'OAuthScope', 'OAuthUri'
    )

    $Parameter = @{
        AuthenticationType = $AuthenticationType
        SessionKey         = $SessionKey
    }
    foreach ($Name in $PassThroughName) {
        if ($BoundParameter.Contains($Name) -and $null -ne $BoundParameter[$Name]) {
            $Parameter[$Name] = $BoundParameter[$Name]
        }
    }
    if ($Parameter.ContainsKey('Credential') -and $Parameter.Credential -eq [System.Management.Automation.PSCredential]::Empty) {
        $Parameter.Remove('Credential')
    }

    Assert-OmadaSqlAuthenticationParameter -Parameter $Parameter -AuthenticationType $AuthenticationType

    if ($NoInteractiveAuthentication) {
        if (-not (Test-OmadaSqlRestMethodParameter -Name 'NoInteractiveAuthentication')) {
            throw (New-OmadaSqlErrorRecord -Kind 'InvalidArgument' -Message 'The installed OmadaWeb.PS does not support -NoInteractiveAuthentication. Update OmadaWeb.PS (Update-Module OmadaWeb.PS).')
        }
        $Parameter.NoInteractiveAuthentication = $true
    }

    Add-OmadaSqlAdditionalParameter -Parameter $Parameter -AdditionalParameter $AdditionalParameter -ReservedName ($PassThroughName + @('Uri', 'Method', 'Body', 'ContentType', 'AuthenticationType', 'SessionKey', 'ErrorAction', 'ForceAuthentication', 'NoInteractiveAuthentication'))

    return $Parameter
}

function Assert-OmadaSqlAuthenticationParameter {
    <#
    .SYNOPSIS
    Throws OmadaSql.InvalidArgument for an authentication parameter combination that cannot work.

    .DESCRIPTION
    OAuth needs either exactly one client certificate source together with -ClientId, or a client id
    and secret in -Credential. Windows and Basic need -Credential. Checked before any request, so an
    unattended run fails with the cause instead of an identity provider error.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Parameter,

        [Parameter(Mandatory = $true)]
        [string]$AuthenticationType
    )

    if ($AuthenticationType -in @('Windows', 'Basic')) {
        if (-not $Parameter.ContainsKey('Credential')) {
            throw (New-OmadaSqlErrorRecord -Kind 'InvalidArgument' -Message ("-AuthenticationType {0} needs -Credential." -f $AuthenticationType))
        }
        return
    }
    if ($AuthenticationType -ne 'OAuth') {
        return
    }

    $CertificateParameter = @(@('OAuthCertificateThumbprint', 'OAuthCertificatePath', 'OAuthCertificate') | Where-Object { $Parameter.ContainsKey($_) })
    if ($CertificateParameter.Count -gt 1) {
        throw (New-OmadaSqlErrorRecord -Kind 'InvalidArgument' -Message ("Use only one of -OAuthCertificateThumbprint, -OAuthCertificatePath and -OAuthCertificate (got {0})." -f ($CertificateParameter -join ', ')))
    }
    if ($CertificateParameter.Count -eq 1 -and -not $Parameter.ContainsKey('ClientId')) {
        throw (New-OmadaSqlErrorRecord -Kind 'InvalidArgument' -Message 'A client certificate needs -ClientId: with a certificate the client id is never taken from -Credential.')
    }
    if ($CertificateParameter.Count -eq 0 -and -not $Parameter.ContainsKey('Credential')) {
        throw (New-OmadaSqlErrorRecord -Kind 'InvalidArgument' -Message '-AuthenticationType OAuth needs a client certificate (-ClientId with -OAuthCertificateThumbprint, -OAuthCertificatePath or -OAuthCertificate) or a client id and secret in -Credential.')
    }
}

function Add-OmadaSqlAdditionalParameter {
    <#
    .SYNOPSIS
    Adds the -AdditionalParameter entries of Connect-OmadaSql to the request parameters.

    .DESCRIPTION
    Each name must be a parameter of the installed Invoke-OmadaRestMethod, and may not be one the
    module sets itself: those would silently override the connection or the request.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Parameter,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [hashtable]$AdditionalParameter,

        [Parameter(Mandatory = $true)]
        [string[]]$ReservedName
    )

    foreach ($Name in $AdditionalParameter.Keys) {
        if ($Name -in $ReservedName) {
            throw (New-OmadaSqlErrorRecord -Kind 'InvalidArgument' -Message ("-AdditionalParameter may not set '{0}': it is set by Connect-OmadaSql or per request." -f $Name))
        }
        if (-not (Test-OmadaSqlRestMethodParameter -Name $Name)) {
            throw (New-OmadaSqlErrorRecord -Kind 'InvalidArgument' -Message ("'{0}' in -AdditionalParameter is not a parameter of the installed Invoke-OmadaRestMethod." -f $Name))
        }
        $Parameter[$Name] = $AdditionalParameter[$Name]
    }
}
