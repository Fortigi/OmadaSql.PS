function ConvertTo-OmadaSqlUnqualifiedText {
    <#
    .SYNOPSIS
    The text of one statement with its database prefixes removed, or '' for a USE statement.

    .DESCRIPTION
    Once the database has been resolved to a data connection the prefix has done its job, and it must
    not reach the tenant: SQL Troubleshooting runs the text against the connection of the query
    object, where [OISES].dbo.tblDataObject would name a database the connection may not be allowed
    to cross into. The edits are made on the parser's offsets, so a prefix-looking text inside a
    string or a comment is never touched.

    For [Db].[Schema].[Table] the prefix runs up to the schema, leaving [Schema].[Table]. For the
    two-dot form [Db]..[Table] the schema is empty, so the prefix runs up to the table and removes
    "[Db].." whole.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Statement
    )

    if ($Statement.Fragment.GetType().Name -eq 'UseStatement') {
        return ''
    }
    $Span = [System.Collections.Generic.List[object]]::new()
    foreach ($Name in @(Get-OmadaSqlFragmentDescendant -Fragment $Statement.Fragment -TypeName 'SchemaObjectName' -IncludeSelf)) {
        if ($null -eq $Name.DatabaseIdentifier -or $Name.DatabaseIdentifier.Value -eq '') {
            continue
        }
        $End = $Name.BaseIdentifier.StartOffset
        if ($null -ne $Name.SchemaIdentifier -and $Name.SchemaIdentifier.Value -ne '') {
            $End = $Name.SchemaIdentifier.StartOffset
        }
        $Span.Add([pscustomobject]@{ Start = $Name.StartOffset - $Statement.StartOffset; Length = $End - $Name.StartOffset })
    }
    $Text = [System.Text.StringBuilder]::new($Statement.Text)
    foreach ($Item in @($Span | Sort-Object -Property Start -Descending)) {
        $null = $Text.Remove($Item.Start, $Item.Length)
    }
    return $Text.ToString()
}
