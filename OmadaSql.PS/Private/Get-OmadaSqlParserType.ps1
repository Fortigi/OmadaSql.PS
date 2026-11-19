function Get-OmadaSqlParserType {
    <#
    .SYNOPSIS
    The newest TSqlNNNParser type the loaded ScriptDom assembly ships.

    .DESCRIPTION
    Found by reflection rather than written as a type literal, so moving the pinned package to a
    version with a newer grammar takes effect without a code change. The parsers are cumulative, so
    the newest is the most permissive: a query the tenant accepts is not flagged for syntax that an
    older grammar lacks. Resolved once per session.
    #>
    [CmdletBinding()]
    [OutputType([type])]
    param()

    if ($null -ne $Script:OmadaSqlParserType) {
        return $Script:OmadaSqlParserType
    }
    $Assembly = Import-OmadaSqlScriptDom
    $Script:OmadaSqlParserType = Select-OmadaSqlNewestParserType -Type $Assembly.GetExportedTypes()
    if ($null -eq $Script:OmadaSqlParserType) {
        throw (New-OmadaSqlErrorRecord -Kind 'ParserUnavailable' -Message ("The T-SQL parser assembly '{0}' contains no TSqlNNNParser type." -f $Assembly.FullName))
    }
    return $Script:OmadaSqlParserType
}

function Select-OmadaSqlNewestParserType {
    <#
    .SYNOPSIS
    From a list of types, the TSqlNNNParser with the highest number, or $null. Pure.

    .DESCRIPTION
    Sorted by the number, not by the name: 'TSql90Parser' sorts after 'TSql170Parser' as text.
    #>
    [CmdletBinding()]
    [OutputType([type])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [type[]]$Type
    )

    $Parser = @($Type | Where-Object { $_.Name -match '^TSql(\d+)Parser$' })
    if ($Parser.Count -eq 0) {
        return $null
    }
    return @($Parser | Sort-Object -Property @{ Expression = { [int]($_.Name -replace '^TSql(\d+)Parser$', '$1') } } -Descending)[0]
}
