function ConvertFrom-OmadaSqlDataConnectionHtml {
    <#
    .SYNOPSIS
    Parses the data connection options out of a SQL Troubleshooting object's edit page. Pure.

    .DESCRIPTION
    Omada has no OData endpoint that lists the data connections a SQL Troubleshooting object may
    use; the edit page (dataobjdlg.aspx) renders them as <option> elements with the data object id
    in 'value' and its UID in 'data-uid'. The pattern is OmadaSqlTroubleshooter's
    (Get-DataConnectionOptionList). Names are HTML-decoded and trimmed; a repeated id is kept once,
    in page order.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [AllowEmptyString()]
        [AllowNull()]
        [string]$Html
    )

    if ([string]::IsNullOrWhiteSpace($Html)) {
        return
    }

    $Seen = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($Match in [regex]::Matches($Html, '<option[^>]*?value="(\d+)"[^>]*?data-uid="([^"]*)"[^>]*>(.*?)</option>', [System.Text.RegularExpressions.RegexOptions]::Singleline)) {
        $Id = $Match.Groups[1].Value
        if (-not $Seen.Add($Id)) {
            continue
        }
        [pscustomobject]@{
            PSTypeName = 'OmadaSql.DataConnection'
            Name       = [System.Net.WebUtility]::HtmlDecode($Match.Groups[3].Value).Trim()
            Id         = [long]$Id
            UId        = $Match.Groups[2].Value
        }
    }
}
