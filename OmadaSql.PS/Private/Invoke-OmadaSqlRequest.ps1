function Invoke-OmadaSqlRequest {
    <#
    .SYNOPSIS
    Sends one request to the tenant of a connection. Every request the module makes goes through here.

    .DESCRIPTION
    The single network seam: builds the Invoke-OmadaRestMethod call from the connection's stored
    parameters, a path relative to the tenant base URL, a method and an optional body, and turns a
    failure into an OmadaSql.<Kind> error (see Resolve-OmadaSqlRequestError). Unit tests mock
    Invoke-OmadaRestMethod, so nothing below it is ever reached in a test.

    A body that is not already a string is serialized with ConvertTo-Json -Depth 20 (the default
    depth of 2 silently truncates nested bodies). It is sent as application/json with an explicit
    UTF-8 charset, so query text outside ASCII arrives intact on both PowerShell editions. Some ASMX
    methods want a body that was serialized separately; pass those as a string.

    The request body and the response are never written to the Verbose stream: both can hold query
    text and personal data. Only the method, the URI and the outcome are.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Context,

        [Parameter(Mandatory = $true)]
        [ValidateSet('GET', 'POST', 'PUT', 'PATCH', 'DELETE')]
        [string]$Method,

        [Parameter(Mandatory = $true)]
        [string]$Path,

        [AllowNull()]
        [object]$Body
    )

    $Uri = "{0}/{1}" -f $Context.Connection.BaseUrl, $Path.TrimStart('/')

    $Parameters = $Context.RequestParameter.Clone()
    $Parameters.Uri = $Uri
    $Parameters.Method = $Method
    $Parameters.ContentType = 'application/json; charset=utf-8'
    $Parameters.ErrorAction = 'Stop'
    if ($null -ne $Body) {
        if ($Body -is [string]) {
            $Parameters.Body = $Body
        }
        else {
            $Parameters.Body = ConvertTo-Json -InputObject $Body -Depth 20 -Compress
        }
    }

    Write-OmadaSqlLog -Message ("{0} {1}" -f $Method, $Uri)
    $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $Result = Invoke-OmadaRestMethod @Parameters
    }
    catch {
        $Failure = Resolve-OmadaSqlRequestError -ErrorRecord $_ -Method $Method -Uri $Uri -ReadSucceeded ([bool]$Context.ReadSucceeded)
        Write-OmadaSqlLog -Message ("{0} {1} failed after {2} ms: {3} (HTTP {4})" -f $Method, $Uri, $Stopwatch.ElapsedMilliseconds, $Failure.Kind, $Failure.StatusCode)
        throw (New-OmadaSqlErrorRecord -Kind $Failure.Kind -Message $Failure.Message -InnerException $_.Exception -TargetObject $Uri)
    }

    Write-OmadaSqlLog -Message ("{0} {1} succeeded in {2} ms" -f $Method, $Uri, $Stopwatch.ElapsedMilliseconds)
    if ($Method -eq 'GET') {
        $Context.ReadSucceeded = $true
    }
    return $Result
}
