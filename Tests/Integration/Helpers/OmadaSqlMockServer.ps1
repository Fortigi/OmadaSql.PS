<#
    A minimal stand-in for an Omada tenant, for the integration tests: an HttpListener on
    127.0.0.1 running in its own runspace in this process.

        . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers\OmadaSqlMockServer.ps1')
        $Server = Start-OmadaSqlMockServer
        Set-OmadaSqlMockRoute -Server $Server -Method GET -Path '/odata/x' -StatusCode 200 -Body '{"value":[]}'
        ...
        Stop-OmadaSqlMockServer -Server $Server

    A request without a route gets 200 with '{}', which also answers the site-root probe OmadaWeb.PS
    makes the first time it sees a base URL. Every request is recorded (method, path and query,
    content type, body as UTF-8 text) in $Server.Shared.Requests.

    A runspace rather than Start-ThreadJob: ThreadJob is not part of Windows PowerShell 5.1, and the
    tests run on both editions.
#>

function Start-OmadaSqlMockServer {
    $Shared = [hashtable]::Synchronized(@{
            Listener = $null
            Error    = $null
            Routes   = [hashtable]::Synchronized(@{})
            Requests = [System.Collections.ArrayList]::Synchronized([System.Collections.ArrayList]::new())
        })

    $Port = 0
    $PowerShell = $null
    $Handle = $null
    foreach ($Attempt in 1..5) {
        $Port = Get-Random -Minimum 20000 -Maximum 30000
        $Shared.Error = $null
        $Shared.Listener = $null
        $PowerShell = [powershell]::Create()
        $null = $PowerShell.AddScript({
                param($Port, $Shared)
                try {
                    $Listener = [System.Net.HttpListener]::new()
                    $Listener.Prefixes.Add(("http://127.0.0.1:{0}/" -f $Port))
                    $Listener.Start()
                    $Shared.Listener = $Listener
                }
                catch {
                    $Shared.Error = $_.Exception.Message
                    return
                }

                while ($Listener.IsListening) {
                    try {
                        $Context = $Listener.GetContext()
                    }
                    catch {
                        break
                    }

                    try {
                        $Reader = [System.IO.StreamReader]::new($Context.Request.InputStream, [System.Text.Encoding]::UTF8)
                        $RequestBody = $Reader.ReadToEnd()
                        $Reader.Dispose()
                        $PathAndQuery = $Context.Request.Url.PathAndQuery
                        $null = $Shared.Requests.Add([pscustomobject]@{
                                Method      = $Context.Request.HttpMethod
                                Path        = $PathAndQuery
                                ContentType = $Context.Request.ContentType
                                Body        = $RequestBody
                            })

                        $Route = $Shared.Routes[('{0} {1}' -f $Context.Request.HttpMethod, $PathAndQuery)]
                        if ($null -eq $Route) {
                            $Route = @{ StatusCode = 200; Body = '{}' }
                        }
                        $Bytes = [System.Text.Encoding]::UTF8.GetBytes([string]$Route.Body)
                        $Context.Response.StatusCode = [int]$Route.StatusCode
                        $Context.Response.ContentType = 'application/json; charset=utf-8'
                        $Context.Response.ContentLength64 = $Bytes.Length
                        $Context.Response.OutputStream.Write($Bytes, 0, $Bytes.Length)
                        $Context.Response.Close()
                    }
                    catch {
                        try {
                            $Context.Response.Abort()
                        }
                        catch {
                            $null = $_
                        }
                    }
                }
            }).AddArgument($Port).AddArgument($Shared)
        $Handle = $PowerShell.BeginInvoke()

        $Deadline = [System.Diagnostics.Stopwatch]::StartNew()
        while ($null -eq $Shared.Listener -and $null -eq $Shared.Error -and $Deadline.Elapsed.TotalSeconds -lt 15) {
            Start-Sleep -Milliseconds 50
        }
        if ($null -ne $Shared.Listener) {
            break
        }
        $PowerShell.Dispose()
        $PowerShell = $null
    }

    if ($null -eq $PowerShell) {
        throw ("The mock Omada server did not start: {0}" -f $Shared.Error)
    }

    return [pscustomobject]@{
        BaseUrl    = 'http://127.0.0.1:{0}' -f $Port
        Shared     = $Shared
        PowerShell = $PowerShell
        Handle     = $Handle
    }
}

function Set-OmadaSqlMockRoute {
    param(
        [Parameter(Mandatory = $true)]
        $Server,

        [Parameter(Mandatory = $true)]
        [string]$Method,

        [Parameter(Mandatory = $true)]
        [string]$Path,

        [int]$StatusCode = 200,

        [string]$Body = '{}'
    )

    $Server.Shared.Routes[('{0} {1}' -f $Method.ToUpperInvariant(), $Path)] = @{ StatusCode = $StatusCode; Body = $Body }
}

function Reset-OmadaSqlMockServer {
    param(
        [Parameter(Mandatory = $true)]
        $Server
    )

    $Server.Shared.Routes.Clear()
    $Server.Shared.Requests.Clear()
}

function Get-OmadaSqlMockRequest {
    param(
        [Parameter(Mandatory = $true)]
        $Server,

        [string]$Path
    )

    $Requests = @($Server.Shared.Requests.ToArray())
    if (-not [string]::IsNullOrEmpty($Path)) {
        $Requests = @($Requests | Where-Object { $_.Path -eq $Path })
    }
    return $Requests
}

function Stop-OmadaSqlMockServer {
    param(
        [Parameter(Mandatory = $true)]
        $Server
    )

    try {
        $Server.Shared.Listener.Stop()
        $Server.Shared.Listener.Close()
    }
    catch {
        $null = $_
    }
    try {
        $null = $Server.Handle.AsyncWaitHandle.WaitOne(5000)
        $Server.PowerShell.Dispose()
    }
    catch {
        $null = $_
    }
}
