function ConvertTo-OmadaSqlODataFilter {
    <#
    .SYNOPSIS
    Builds a URL-safe OData $filter query option from 'property eq value' pairs, joined with 'and'.

    .DESCRIPTION
    String values are quoted as OData literals, a single quote doubled (OData's escape), and the
    whole expression is percent-encoded, so a name containing a quote, '&', '#' or '+' is sent as
    data instead of breaking the URL or the filter. OmadaSqlTroubleshooter inserts the name
    unescaped, which this deliberately does not repeat.

    Only 'and' is used: Omada's OData is expected to treat 'or' as 'and' without an error.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.Specialized.OrderedDictionary]$Equal,

        [string[]]$Raw = @()
    )

    $Clause = [System.Collections.Generic.List[string]]::new()
    foreach ($Name in $Equal.Keys) {
        $Value = $Equal[$Name]
        if ($Value -is [string]) {
            $Literal = "'{0}'" -f $Value.Replace("'", "''")
        }
        elseif ($Value -is [bool]) {
            $Literal = ([string]$Value).ToLowerInvariant()
        }
        else {
            $Literal = [string]$Value
        }
        $Clause.Add(('{0} eq {1}' -f $Name, $Literal))
    }
    foreach ($Expression in $Raw) {
        $Clause.Add($Expression)
    }

    return '$filter=' + [System.Uri]::EscapeDataString(($Clause -join ' and '))
}
