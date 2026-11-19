function Get-OmadaSqlExportFormatTable {
    <#
    .SYNOPSIS
    The export format registry: name to OmadaSql.ExportFormat, with the built-in formats added on first use.

    .DESCRIPTION
    A format turns rows into text. Its ScriptBlock is called with the rows, the column names in
    order and the -Option hashtable: & $ScriptBlock $Row $Column $Option, and returns the text. Option
    lists the option names it accepts, so a misspelt option is an error rather than ignored.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    if ($null -eq $Script:OmadaSqlExportFormat) {
        $Table = @{}
        foreach ($Format in @(Get-OmadaSqlBuiltInExportFormat)) {
            $Table[$Format.Name] = $Format
        }
        $Script:OmadaSqlExportFormat = $Table
    }
    return $Script:OmadaSqlExportFormat
}

function Get-OmadaSqlBuiltInExportFormat {
    <#
    .SYNOPSIS
    The formats the module ships with.
    #>
    [CmdletBinding()]
    [OutputType('OmadaSql.ExportFormat')]
    param()

    New-OmadaSqlExportFormat -Name 'Csv' -Extension '.csv' -Option 'Delimiter', 'NoHeader' -BuiltIn -Description 'RFC 4180 CSV: every field quoted, a null value as an empty unquoted field, CRLF line ends. Options: Delimiter (default comma), NoHeader.' -ScriptBlock { param($Row, $Column, $Option) ConvertTo-OmadaSqlCsvText -Row $Row -Column $Column -Option $Option }
    New-OmadaSqlExportFormat -Name 'Json' -Extension '.json' -Option 'Compress' -BuiltIn -Description 'A JSON array with one object per row, columns in result order; dates as ISO 8601 text. Option: Compress.' -ScriptBlock { param($Row, $Column, $Option) ConvertTo-OmadaSqlJsonText -Row $Row -Column $Column -Option $Option }
    New-OmadaSqlExportFormat -Name 'Xml' -Extension '.xml' -BuiltIn -Description 'UTF-8 XML: <Result><Row><Field Name="column">value</Field></Row></Result>; a null value is a Field with Null="true".' -ScriptBlock { param($Row, $Column, $Option) ConvertTo-OmadaSqlXmlText -Row $Row -Column $Column }
    New-OmadaSqlExportFormat -Name 'Text' -Extension '.txt' -BuiltIn -Description 'A plain text table: one space between columns, a dashed line under the header, numeric columns right-aligned, NULL for a null value.' -ScriptBlock { param($Row, $Column, $Option) ConvertTo-OmadaSqlTableText -Row $Row -Column $Column }
    New-OmadaSqlExportFormat -Name 'SqlArray' -Extension '.sql' -BuiltIn -Description 'T-SQL literals: (v1, v2, ...) for one column, for an IN list; (VALUES (...), ...) AS t ([a], [b]) for more.' -ScriptBlock { param($Row, $Column, $Option) ConvertTo-OmadaSqlSqlArrayText -Row $Row -Column $Column }
    New-OmadaSqlExportFormat -Name 'PowerShellArray' -Extension '.ps1' -BuiltIn -Description 'PowerShell literals: @(v1, v2, ...) for one column; @([PSCustomObject]@{ ... }, ...) for more.' -ScriptBlock { param($Row, $Column, $Option) ConvertTo-OmadaSqlPowerShellArrayText -Row $Row -Column $Column }
}

function New-OmadaSqlExportFormat {
    <#
    .SYNOPSIS
    One OmadaSql.ExportFormat.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds an object in memory and changes no state.')]
    [CmdletBinding()]
    [OutputType('OmadaSql.ExportFormat')]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Extension,

        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,

        [AllowEmptyString()]
        [string]$Description = '',

        [string[]]$Option = @(),

        [switch]$BuiltIn
    )

    [pscustomobject]@{
        PSTypeName  = 'OmadaSql.ExportFormat'
        Name        = $Name
        Extension   = $Extension
        Description = $Description
        Option      = @($Option)
        BuiltIn     = [bool]$BuiltIn
        ScriptBlock = $ScriptBlock
    }
}

function Resolve-OmadaSqlExportFormat {
    <#
    .SYNOPSIS
    The format to export with: -Format by name, else the format whose extension -Path has, else Csv.
    #>
    [CmdletBinding()]
    [OutputType('OmadaSql.ExportFormat')]
    param(
        [AllowEmptyString()]
        [AllowNull()]
        [string]$Format,

        [AllowEmptyString()]
        [AllowNull()]
        [string]$Path
    )

    $Table = Get-OmadaSqlExportFormatTable
    $Known = (@($Table.Keys) | Sort-Object) -join ', '
    if (-not [string]::IsNullOrEmpty($Format)) {
        if (-not $Table.ContainsKey($Format)) {
            throw (New-OmadaSqlErrorRecord -Kind 'InvalidArgument' -Message ("Unknown export format '{0}'. Known formats: {1}." -f $Format, $Known) -TargetObject $Format)
        }
        return $Table[$Format]
    }
    if ([string]::IsNullOrEmpty($Path)) {
        return $Table['Csv']
    }
    $Extension = [System.IO.Path]::GetExtension($Path)
    $Match = @($Table.Values | Where-Object { $_.Extension -ne '' -and $_.Extension -eq $Extension } | Sort-Object -Property @{ Expression = { -not $_.BuiltIn } }, Name)
    if ($Match.Count -eq 0) {
        throw (New-OmadaSqlErrorRecord -Kind 'InvalidArgument' -Message ("No export format has the extension '{0}'. Use -Format; known formats: {1}." -f $Extension, $Known) -TargetObject $Path)
    }
    return $Match[0]
}

function Assert-OmadaSqlExportOption {
    <#
    .SYNOPSIS
    Throws OmadaSql.InvalidArgument for an option the format does not accept.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Format,

        [AllowNull()]
        [hashtable]$Option
    )

    if ($null -eq $Option) {
        return
    }
    foreach ($Key in @($Option.Keys)) {
        if (@($Format.Option | Where-Object { $_ -eq [string]$Key }).Count -eq 0) {
            $Accepted = if ($Format.Option.Count -gt 0) { $Format.Option -join ', ' } else { 'none' }
            throw (New-OmadaSqlErrorRecord -Kind 'InvalidArgument' -Message ("The {0} format has no option '{1}'. Options: {2}." -f $Format.Name, $Key, $Accepted) -TargetObject $Key)
        }
    }
}
