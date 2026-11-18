function ConvertTo-OmadaSqlBaseUrl {
    <#
    .SYNOPSIS
    Normalises a tenant URL to the base URL every request is built on.

    .DESCRIPTION
    Accepts 'https://tenant.omada.cloud', with or without a trailing slash, and also a URL copied
    from the browser (a page or OData path), which is cut back to scheme, host and port. Only https
    is accepted: every request carries a session cookie or a bearer token.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url
    )

    $Parsed = $null
    if (-not [System.Uri]::TryCreate($Url.Trim(), [System.UriKind]::Absolute, [ref]$Parsed)) {
        throw (New-OmadaSqlErrorRecord -Kind 'InvalidArgument' -Message ("'{0}' is not an absolute URL. Use the tenant base URL, for example https://tenant.omada.cloud." -f $Url) -TargetObject $Url)
    }
    if ($Parsed.Scheme -ne [System.Uri]::UriSchemeHttps) {
        throw (New-OmadaSqlErrorRecord -Kind 'InvalidArgument' -Message ("'{0}' does not use https. Omada requests carry session cookies or tokens and are only sent over https." -f $Url) -TargetObject $Url)
    }

    return $Parsed.GetLeftPart([System.UriPartial]::Authority).TrimEnd('/')
}
