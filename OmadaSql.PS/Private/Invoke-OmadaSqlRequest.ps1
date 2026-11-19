function Invoke-OmadaSqlRequest {
    <#
    .SYNOPSIS
    Sends one request to the tenant of a connection. Every request the module makes goes through here.

    .DESCRIPTION
    The single network seam: builds the Invoke-OmadaRestMethod call from the connection's stored
    parameters, a path relative to the tenant base URL, a method and an optional body, and turns a
    failure into an OmadaSql.<Kind> error (see Resolve-OmadaSqlRequestError). Unit tests mock
    Invoke-OmadaRestMethod, so nothing below it is ever reached in a test.

    A body that is not already a string is serialized with ConvertTo-Json -Depth 100, the maximum
    PowerShell 7 accepts: the default depth of 2, or any lower limit, silently truncates a nested
    body instead of failing. Some ASMX methods want a body that was serialized
    separately; pass those as a string. Either way the JSON is sent as UTF-8 bytes: Windows
    PowerShell 5.1 encodes a string body as ISO-8859-1 whatever charset the content type names, which
    turns query text outside Latin-1 into question marks (found by the integration tests).

    -Paged asks OmadaWeb.PS to follow @odata.nextLink until every page of an OData list is read;
    Omada caps a page at the tenant's ODataPageSizeLimit. It only applies to GET.

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
        [object]$Body,

        [switch]$Paged
    )

    $Uri = "{0}/{1}" -f $Context.Connection.BaseUrl, $Path.TrimStart('/')

    $Parameters = $Context.RequestParameter.Clone()
    $Parameters.Uri = $Uri
    $Parameters.Method = $Method
    $Parameters.ContentType = 'application/json; charset=utf-8'
    $Parameters.ErrorAction = 'Stop'
    if ($null -ne $Body) {
        $Json = $Body
        if ($Body -isnot [string]) {
            $Json = ConvertTo-Json -InputObject $Body -Depth 100 -Compress
        }
        $Parameters.Body = [System.Text.Encoding]::UTF8.GetBytes([string]$Json)
    }

    if ($Paged -and $Method -eq 'GET' -and (Test-OmadaSqlRestMethodParameter -Name 'Paged')) {
        $Parameters.Paged = $true
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
