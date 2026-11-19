function Get-OmadaSqlExportColumn {
    <#
    .SYNOPSIS
    The column names of a result, in order, taken from its first row as Omada returns every row with
    the same columns.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Row
    )

    if ($Row.Count -eq 0) {
        return , [string[]]@()
    }
    if ($Row[0] -is [System.Collections.IDictionary]) {
        return , [string[]]@($Row[0].Keys | ForEach-Object { [string]$_ })
    }
    return , [string[]]@($Row[0].PSObject.Properties | ForEach-Object { $_.Name })
}

function Format-OmadaSqlExportValue {
    <#
    .SYNOPSIS
    A value as culture-independent text, or $null for a null value.

    .DESCRIPTION
    Exports must read the same on every machine, so numbers use the invariant culture and dates ISO
    8601 (yyyy-MM-ddTHH:mm:ss.fff). Omada usually returns every value as text already.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Value -or $Value -is [System.DBNull]) {
        return $null
    }
    if ($Value -is [datetime]) {
        return $Value.ToString('yyyy-MM-ddTHH:mm:ss.fff', [System.Globalization.CultureInfo]::InvariantCulture)
    }
    if ($Value -is [datetimeoffset]) {
        return $Value.ToString('o', [System.Globalization.CultureInfo]::InvariantCulture)
    }
    if ($Value -is [double] -or $Value -is [single]) {
        return $Value.ToString('R', [System.Globalization.CultureInfo]::InvariantCulture)
    }
    if ($Value -is [System.IFormattable]) {
        return $Value.ToString($null, [System.Globalization.CultureInfo]::InvariantCulture)
    }
    return [string]$Value
}

function Get-OmadaSqlExportCell {
    <#
    .SYNOPSIS
    The value of one column of one row, from an object or a dictionary.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Row,

        [Parameter(Mandatory = $true)]
        [string]$Column
    )

    $Value = Get-OmadaSqlPropertyValue -InputObject $Row -Name $Column
    return , $Value
}

function ConvertTo-OmadaSqlCsvText {
    <#
    .SYNOPSIS
    CSV as RFC 4180 describes it, but separated by semicolons by default (as OmadaSqlTroubleshooter and
    Excel with many European regional settings expect): every field quoted, a null value as an empty
    unquoted field, CRLF between lines.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Row,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$Column,

        [AllowNull()]
        [hashtable]$Option
    )

    if ($null -eq $Option) {
        $Option = @{}
    }
    $Delimiter = Get-OmadaSqlCsvDelimiter -Option $Option
    $Line = [System.Collections.Generic.List[string]]::new()
    if (-not $Option['NoHeader'] -and $Column.Count -gt 0) {
        $Line.Add((($Column | ForEach-Object { ConvertTo-OmadaSqlCsvField -Text $_ }) -join $Delimiter))
    }
    foreach ($Item in $Row) {
        $Field = foreach ($Name in $Column) {
            ConvertTo-OmadaSqlCsvField -Text (Format-OmadaSqlExportValue -Value (Get-OmadaSqlExportCell -Row $Item -Column $Name))
        }
        $Line.Add((@($Field) -join $Delimiter))
    }
    return ($Line -join "`r`n")
}

function Get-OmadaSqlCsvDelimiter {
    <#
    .SYNOPSIS
    The Delimiter option: one character that is not a quote or a line break; a semicolon by default.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Option
    )

    if (-not $Option.ContainsKey('Delimiter')) {
        return ';'
    }
    $Delimiter = [string]$Option['Delimiter']
    if ($Delimiter.Length -ne 1 -or $Delimiter -in '"', "`r", "`n") {
        throw (New-OmadaSqlErrorRecord -Kind 'InvalidArgument' -Message ("The CSV Delimiter must be one character other than a double quote or a line break, not '{0}'." -f $Delimiter) -TargetObject $Delimiter)
    }
    return $Delimiter
}

function ConvertTo-OmadaSqlCsvField {
    <#
    .SYNOPSIS
    One CSV field: quoted with inner quotes doubled, or empty for $null.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()]
        [string]$Text
    )

    if ($null -eq $Text) {
        return ''
    }
    return '"{0}"' -f $Text.Replace('"', '""')
}

function ConvertTo-OmadaSqlJsonText {
    <#
    .SYNOPSIS
    A JSON array with one object per row, its properties in column order.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Row,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$Column,

        [AllowNull()]
        [hashtable]$Option
    )

    $List = [System.Collections.Generic.List[object]]::new()
    foreach ($Item in $Row) {
        $Object = [ordered]@{}
        foreach ($Name in $Column) {
            $Object[$Name] = ConvertTo-OmadaSqlJsonValue -Value (Get-OmadaSqlExportCell -Row $Item -Column $Name)
        }
        $List.Add($Object)
    }
    $Compress = $null -ne $Option -and [bool]$Option['Compress']
    return (ConvertTo-Json -InputObject $List.ToArray() -Depth 5 -Compress:$Compress)
}

function ConvertTo-OmadaSqlJsonValue {
    <#
    .SYNOPSIS
    A value as JSON should carry it: dates as ISO 8601 text (Windows PowerShell would write \/Date()\/), the rest as is.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [AllowNull()]
        [object]$Value
    )

    if ($Value -is [System.DBNull]) {
        return $null
    }
    if ($Value -is [datetime] -or $Value -is [datetimeoffset]) {
        return (Format-OmadaSqlExportValue -Value $Value)
    }
    return , $Value
}

function ConvertTo-OmadaSqlXmlText {
    <#
    .SYNOPSIS
    UTF-8 XML: <Result><Row><Field Name="column">value</Field>...</Row>...</Result>.

    .DESCRIPTION
    A column name goes in an attribute, so any name is valid XML. A null value is an empty Field with
    Null="true", so it differs from an empty string.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Row,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$Column
    )

    $Settings = [System.Xml.XmlWriterSettings]::new()
    $Settings.Indent = $true
    $Settings.NewLineChars = "`r`n"
    $Settings.Encoding = [System.Text.UTF8Encoding]::new($false)
    $Stream = [System.IO.MemoryStream]::new()
    $Writer = [System.Xml.XmlWriter]::Create($Stream, $Settings)
    try {
        $Writer.WriteStartDocument()
        $Writer.WriteStartElement('Result')
        foreach ($Item in $Row) {
            $Writer.WriteStartElement('Row')
            foreach ($Name in $Column) {
                Write-OmadaSqlXmlField -Writer $Writer -Name $Name -Text (Format-OmadaSqlExportValue -Value (Get-OmadaSqlExportCell -Row $Item -Column $Name))
            }
            $Writer.WriteEndElement()
        }
        $Writer.WriteEndElement()
        $Writer.WriteEndDocument()
        $Writer.Flush()
        return [System.Text.Encoding]::UTF8.GetString($Stream.ToArray())
    }
    finally {
        $Writer.Dispose()
        $Stream.Dispose()
    }
}

function Write-OmadaSqlXmlField {
    <#
    .SYNOPSIS
    Writes one Field element.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Xml.XmlWriter]$Writer,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [AllowNull()]
        [string]$Text
    )

    $Writer.WriteStartElement('Field')
    $Writer.WriteAttributeString('Name', $Name)
    if ($null -eq $Text) {
        $Writer.WriteAttributeString('Null', 'true')
    }
    else {
        $Writer.WriteString($Text)
    }
    $Writer.WriteEndElement()
}

function ConvertTo-OmadaSqlTableText {
    <#
    .SYNOPSIS
    A plain text table, as SQL Server Management Studio shows results as text.

    .DESCRIPTION
    Columns are as wide as their name or longest value and separated by one space, with a dashed line
    under the header. A column whose values are all numbers is right-aligned. A null value shows as
    NULL; a line break or tab in a value becomes a space. The last column is not padded.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Row,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$Column
    )

    if ($Column.Count -eq 0) {
        return ''
    }
    $Layout = @(foreach ($Name in $Column) { New-OmadaSqlTableColumn -Row $Row -Name $Name })
    $Line = [System.Collections.Generic.List[string]]::new()
    $Line.Add((Join-OmadaSqlTableLine -Layout $Layout -Cell @($Layout | ForEach-Object { $_.Name })))
    $Line.Add((@($Layout | ForEach-Object { '-' * $_.Width }) -join ' '))
    for ($Index = 0; $Index -lt $Row.Count; $Index++) {
        $Line.Add((Join-OmadaSqlTableLine -Layout $Layout -Cell @($Layout | ForEach-Object { $_.Text[$Index] })))
    }
    return ($Line -join "`r`n")
}

function New-OmadaSqlTableColumn {
    <#
    .SYNOPSIS
    The layout of one text table column: its cell texts in row order, its width and its alignment.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds an object in memory and changes no state.')]
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Row,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $Value = [System.Collections.Generic.List[object]]::new()
    $Text = [System.Collections.Generic.List[string]]::new()
    $Width = $Name.Length
    foreach ($Item in $Row) {
        $Cell = Get-OmadaSqlExportCell -Row $Item -Column $Name
        $Value.Add($Cell)
        $Text.Add((ConvertTo-OmadaSqlTableCell -Value $Cell))
        $Width = [System.Math]::Max($Width, $Text[$Text.Count - 1].Length)
    }
    [pscustomobject]@{
        Name    = $Name
        Text    = $Text
        Width   = $Width
        Numeric = (Get-OmadaSqlColumnKind -Value $Value.ToArray()) -eq 'Number'
    }
}

function ConvertTo-OmadaSqlTableCell {
    <#
    .SYNOPSIS
    The text of one table cell: NULL for a null value, line breaks and tabs as spaces.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()]
        [object]$Value
    )

    $Text = Format-OmadaSqlExportValue -Value $Value
    if ($null -eq $Text) {
        return 'NULL'
    }
    return ($Text -replace "`r`n|`r|`n|`t", ' ')
}

function Join-OmadaSqlTableLine {
    <#
    .SYNOPSIS
    One line of the text table, each cell padded to its column's width and alignment.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Layout,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string[]]$Cell
    )

    $Part = for ($Index = 0; $Index -lt $Layout.Count; $Index++) {
        if ($Layout[$Index].Numeric) {
            $Cell[$Index].PadLeft($Layout[$Index].Width)
        }
        elseif ($Index -lt $Layout.Count - 1) {
            $Cell[$Index].PadRight($Layout[$Index].Width)
        }
        else {
            $Cell[$Index]
        }
    }
    return (@($Part) -join ' ')
}
