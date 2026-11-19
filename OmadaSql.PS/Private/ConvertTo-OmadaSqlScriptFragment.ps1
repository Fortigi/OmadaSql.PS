function ConvertTo-OmadaSqlScriptFragment {
    <#
    .SYNOPSIS
    Parses a T-SQL script once and returns the syntax tree, the parse errors and the parser used.

    .DESCRIPTION
    Every later step (statement splitting, database names, the rules) reads the same tree, so the
    script is parsed here and nowhere else. ScriptDom recovers from errors, so a script with a
    syntax error still yields a tree; callers that need a trustworthy tree check ParseError.

    The parser runs with QUOTED_IDENTIFIER ON, the setting .NET clients (Omada's included) connect
    with: "x" is then an identifier, not a string, exactly as the tenant will read it.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Sql
    )

    $ParserType = Get-OmadaSqlParserType
    $Parser = $ParserType::new($true)
    $Errors = $null
    $Reader = [System.IO.StringReader]::new($Sql)
    try {
        $Fragment = $Parser.Parse($Reader, [ref]$Errors)
    }
    finally {
        $Reader.Dispose()
    }
    [pscustomobject]@{
        Fragment      = $Fragment
        ParseError    = @(@($Errors) | Where-Object { $null -ne $_ })
        ParserVersion = $ParserType.Name
    }
}
