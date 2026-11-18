function Get-OmadaSqlHttpStatusCode {
    <#
    .SYNOPSIS
    The HTTP status code of a failed request, or $null when the error carries none.

    .DESCRIPTION
    Reads Exception.Response.StatusCode (PowerShell 7 and Windows PowerShell both expose it there
    for an HTTP error), and falls back to the status code in the message text, which is what an
    error that crossed a serialization boundary still has.
    #>
    [CmdletBinding()]
    [OutputType([System.Nullable[int]])]
    param(
        [AllowNull()]
        $ErrorRecord
    )

    if ($null -eq $ErrorRecord) {
        return $null
    }

    try {
        $Response = $ErrorRecord.Exception.Response
        if ($null -ne $Response -and $null -ne $Response.StatusCode) {
            return [int]$Response.StatusCode
        }
    }
    catch {
        Write-OmadaSqlLog -Message ("Could not read the response status code: {0}" -f $_.Exception.Message) -Level Debug
    }

    # PowerShell 7: "Response status code does not indicate success: 401 (Unauthorized)."
    # Windows PowerShell: "The remote server returned an error: (401) Unauthorized."
    $Match =[regex]::Match([string]$ErrorRecord.Exception.Message, 'status code does not indicate success:\s*(\d{3})|\(\s*(\d{3})\s*\)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($Match.Success) {
        foreach ($Group in @($Match.Groups[1], $Match.Groups[2])) {
            if ($Group.Success) {
                return [int]$Group.Value
            }
        }
    }

    return $null
}
