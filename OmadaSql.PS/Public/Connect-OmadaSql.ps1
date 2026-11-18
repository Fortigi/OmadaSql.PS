function Connect-OmadaSql {
    <#
    .SYNOPSIS
    Connects to an Omada Identity Cloud tenant for SQL Troubleshooting commands.

    .DESCRIPTION
    Creates a connection that the other OmadaSql.PS commands use, and makes it the current one.
    Sign-in and every request are handled by OmadaWeb.PS (Invoke-OmadaRestMethod), so every
    authentication type it supports can be used. For unattended runs use -AuthenticationType OAuth
    with a client certificate (-ClientId with -OAuthCertificateThumbprint, -OAuthCertificatePath or
    -OAuthCertificate), or with a client id and secret in -Credential.

    Unless -SkipConnectionTest is given, the connection is verified by reading one SQL
    Troubleshooting object over OData. That proves the sign-in works and that the
    C_P_SQLTROUBLESHOOTING OData endpoint is enabled, and fails with a specific error otherwise.

    Secrets passed here (the credential, the certificate, its password) are kept inside the module
    and are never part of the returned connection object.

    .PARAMETER Url
    The tenant base URL, for example https://tenant.omada.cloud. A URL copied from the browser is
    cut back to scheme and host. Only https is accepted.

    .PARAMETER AuthenticationType
    How OmadaWeb.PS signs in: OAuth (unattended, client credentials), Browser (interactive), WebView2
    (interactive), Integrated, Windows or Basic. Defaults to Browser. Integrated, Windows and Basic
    only apply to on-premises installations.

    .PARAMETER ClientId
    The application (client) id of the service principal, for -AuthenticationType OAuth with a
    certificate. For the client secret flow the client id is the user name of -Credential.

    .PARAMETER OAuthCertificateThumbprint
    Thumbprint of the client certificate in CurrentUser\My or LocalMachine\My, for -AuthenticationType OAuth.

    .PARAMETER OAuthCertificatePath
    Path to a .pfx or .p12 file holding the client certificate and private key, for -AuthenticationType OAuth.

    .PARAMETER OAuthCertificatePassword
    The password of the file in -OAuthCertificatePath, as a SecureString.

    .PARAMETER OAuthCertificate
    An already loaded client certificate with its private key, for -AuthenticationType OAuth.

    .PARAMETER Credential
    The client id and secret for -AuthenticationType OAuth with a secret, or the account for
    Windows and Basic authentication.

    .PARAMETER EntraIdTenantId
    The Entra ID tenant id or name, for -AuthenticationType OAuth.

    .PARAMETER EntraApplicationIdUri
    The application ID URI of the Omada enterprise application, when it differs from the tenant base URL.

    .PARAMETER OAuthScope
    A custom OAuth2 scope, for an identity provider other than Entra ID.

    .PARAMETER OAuthUri
    A custom OAuth2 token endpoint, for an identity provider other than Entra ID.

    .PARAMETER NoInteractiveAuthentication
    Never open a sign-in window. With Browser or WebView2 an existing session is reused and a
    missing or expired session fails with an OmadaSql.SessionExpired error. OAuth never signs in
    interactively, so the switch changes nothing there.

    .PARAMETER SessionKey
    Keeps OmadaWeb.PS sessions apart when several connections to the same tenant with the same
    authentication run side by side. Defaults to 'OmadaSql.PS', so a cached browser session is
    reused across runs.

    .PARAMETER AdditionalParameter
    Further Invoke-OmadaRestMethod parameters to pass on every request, for example
    @{ MaximumRetryCount = 5 } or @{ UserName = 'admin@contoso.com' }. Each name must be a parameter
    of the installed Invoke-OmadaRestMethod.

    .PARAMETER SkipConnectionTest
    Create the connection without the verification request.

    .PARAMETER PassThru
    Return the connection object. Without it the command returns nothing.

    .EXAMPLE
    Connect-OmadaSql -Url 'https://tenant.omada.cloud' -AuthenticationType OAuth -ClientId '00000000-0000-0000-0000-000000000000' -OAuthCertificateThumbprint 'A1B2C3D4E5F60718293A4B5C6D7E8F9012345678' -EntraIdTenantId 'contoso.onmicrosoft.com'

    Connects unattended with a client certificate from the certificate store, the form to use in a
    scheduled task.

    .EXAMPLE
    Connect-OmadaSql -Url 'https://tenant.omada.cloud'

    Connects interactively; a browser window opens when there is no cached session.

    .EXAMPLE
    $Production = Connect-OmadaSql -Url 'https://prod.omada.cloud' -AuthenticationType OAuth -Credential $ClientSecret -EntraIdTenantId 'contoso.onmicrosoft.com' -PassThru
    $Test = Connect-OmadaSql -Url 'https://test.omada.cloud' -AuthenticationType OAuth -Credential $ClientSecret -EntraIdTenantId 'contoso.onmicrosoft.com' -PassThru

    Connects to two tenants. The last connection is the current one; pass -Connection $Production to
    a command to use the other.

    .LINK
    https://github.com/Fortigi/OmadaSql.PS

    .LINK
    https://github.com/Fortigi/OmadaWeb.PS
    #>
    [CmdletBinding()]
    [OutputType('OmadaSql.Connection')]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Url,

        [ValidateSet('OAuth', 'Browser', 'WebView2', 'Integrated', 'Windows', 'Basic')]
        [string]$AuthenticationType = 'Browser',

        [string]$ClientId,

        [string]$OAuthCertificateThumbprint,

        [string]$OAuthCertificatePath,

        [System.Security.SecureString]$OAuthCertificatePassword,

        [System.Security.Cryptography.X509Certificates.X509Certificate2]$OAuthCertificate,

        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]
        $Credential = [System.Management.Automation.PSCredential]::Empty,

        [string]$EntraIdTenantId,

        [string]$EntraApplicationIdUri,

        [string]$OAuthScope,

        [string]$OAuthUri,

        [switch]$NoInteractiveAuthentication,

        [ValidateNotNullOrEmpty()]
        [string]$SessionKey = 'OmadaSql.PS',

        [hashtable]$AdditionalParameter = @{},

        [switch]$SkipConnectionTest,

        [switch]$PassThru
    )

    try {
        $BaseUrl = ConvertTo-OmadaSqlBaseUrl -Url $Url
        # Every authentication parameter is named explicitly, and only the ones the caller supplied
        # are passed on, so an unbound parameter never reaches Invoke-OmadaRestMethod as $null.
        $Candidate = [ordered]@{
            ClientId                   = $ClientId
            OAuthCertificateThumbprint = $OAuthCertificateThumbprint
            OAuthCertificatePath       = $OAuthCertificatePath
            OAuthCertificatePassword   = $OAuthCertificatePassword
            OAuthCertificate           = $OAuthCertificate
            Credential                 = $Credential
            EntraIdTenantId            = $EntraIdTenantId
            EntraApplicationIdUri      = $EntraApplicationIdUri
            OAuthScope                 = $OAuthScope
            OAuthUri                   = $OAuthUri
        }
        $SuppliedParameter = @{}
        foreach ($Name in $Candidate.Keys) {
            if ($PSBoundParameters.ContainsKey($Name)) {
                $SuppliedParameter[$Name] = $Candidate[$Name]
            }
        }
        $RequestParameter = New-OmadaSqlRequestParameter -BoundParameter $SuppliedParameter -AuthenticationType $AuthenticationType -SessionKey $SessionKey -AdditionalParameter $AdditionalParameter -NoInteractiveAuthentication:$NoInteractiveAuthentication

        $Connection = [pscustomobject]@{
            PSTypeName                  = 'OmadaSql.Connection'
            Id                          = [guid]::NewGuid().ToString('N')
            BaseUrl                     = $BaseUrl
            AuthenticationType          = $AuthenticationType
            ClientId                    = $(if ($PSBoundParameters.ContainsKey('ClientId')) { $ClientId } elseif ($Credential -ne [System.Management.Automation.PSCredential]::Empty -and $AuthenticationType -eq 'OAuth') { $Credential.UserName } else { $null })
            SessionKey                  = $SessionKey
            NoInteractiveAuthentication = [bool]$NoInteractiveAuthentication
            ConnectedAt                 = [datetime]::UtcNow
            Verified                    = $false
        }
        $Context = @{
            Connection       = $Connection
            RequestParameter = $RequestParameter
            ReadSucceeded    = $false
        }

        if (-not $SkipConnectionTest) {
            $null = Invoke-OmadaSqlRequest -Context $Context -Method GET -Path 'odata/dataobjects/C_P_SQLTROUBLESHOOTING?$top=1'
            $Connection.Verified = $true
        }

        $Script:OmadaSqlConnectionSequence++
        $Context.Sequence = $Script:OmadaSqlConnectionSequence
        $Script:OmadaSqlConnectionStore[$Connection.Id] = $Context
        $Script:OmadaSqlCurrentConnectionId = $Connection.Id
        Write-OmadaSqlLog -Message ("Connected to {0} with {1} (connection {2}, verified: {3})" -f $BaseUrl, $AuthenticationType, $Connection.Id, $Connection.Verified)

        if ($PassThru) {
            return $Connection
        }
    }
    catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}
