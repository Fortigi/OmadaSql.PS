function Get-OmadaSqlExportFormat {
    <#
    .SYNOPSIS
    Lists the formats Export-OmadaSqlResult can write.

    .DESCRIPTION
    Returns one OmadaSql.ExportFormat per format: Name, Extension (used when Export-OmadaSqlResult
    gets -Path without -Format), Description, Option (the option names it accepts), BuiltIn and
    ScriptBlock.

    .PARAMETER Name
    Only the formats whose name matches this pattern. Wildcards are supported.

    .EXAMPLE
    Get-OmadaSqlExportFormat | Format-Table Name, Extension, Option, Description -Wrap

    Shows every format and its options.

    .LINK
    Export-OmadaSqlResult

    .LINK
    https://github.com/Fortigi/OmadaSql.PS
    #>
    [CmdletBinding()]
    [OutputType('OmadaSql.ExportFormat')]
    param(
        [Parameter(Position = 0)]
        [SupportsWildcards()]
        [string]$Name = '*'
    )

    @((Get-OmadaSqlExportFormatTable).Values) | Where-Object { $_.Name -like $Name } | Sort-Object -Property Name
}
