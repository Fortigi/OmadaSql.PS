function Get-OmadaSqlValueKind {
    <#
    .SYNOPSIS
    What a value is for a literal: Null, Boolean, Number, DateTime or String.

    .DESCRIPTION
    Omada usually returns every value as text, so a string that is a canonical number (-12, 0, 3.50,
    not 007 or 1e5) counts as a Number: an id column then becomes an unquoted IN list. A float that is
    not finite has no literal and counts as a String.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Value -or $Value -is [System.DBNull]) {
        return 'Null'
    }
    switch ([System.Type]::GetTypeCode($Value.GetType()).ToString()) {
        'Boolean' { return 'Boolean' }
        'DateTime' { return 'DateTime' }
        { $_ -in 'SByte', 'Byte', 'Int16', 'UInt16', 'Int32', 'UInt32', 'Int64', 'UInt64', 'Decimal' } { return 'Number' }
        { $_ -in 'Single', 'Double' } { return $(if ([double]::IsNaN($Value) -or [double]::IsInfinity($Value)) { 'String' } else { 'Number' }) }
        'String' { return $(if ($Value -match '^-?(0|[1-9][0-9]*)(\.[0-9]+)?$') { 'Number' } else { 'String' }) }
    }
    return 'String'
}

function Get-OmadaSqlColumnKind {
    <#
    .SYNOPSIS
    The kind of a column: the one kind all its non-null values share, String for a mix, Null when all are null.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [AllowNull()]
        [object[]]$Value
    )

    $Kind = @($Value | ForEach-Object { Get-OmadaSqlValueKind -Value $_ } | Where-Object { $_ -ne 'Null' } | Select-Object -Unique)
    if ($Kind.Count -eq 0) {
        return 'Null'
    }
    if ($Kind.Count -eq 1) {
        return $Kind[0]
    }
    return 'String'
}

function ConvertTo-OmadaSqlSqlLiteral {
    <#
    .SYNOPSIS
    A value as a T-SQL literal, written as its column's kind.

    .DESCRIPTION
    NULL; a number unquoted; a boolean as 1 or 0; a date as 'yyyy-MM-ddTHH:mm:ss.fff'; anything else
    as a quoted string with ' doubled, with an N prefix when it holds a character outside ASCII.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()]
        [object]$Value,

        [Parameter(Mandatory = $true)]
        [string]$Kind
    )

    $Text = Format-OmadaSqlExportValue -Value $Value
    if ($null -eq $Text) {
        return 'NULL'
    }
    switch ($Kind) {
        'Number' { return $Text }
        'Boolean' { return $(if ([bool]$Value) { '1' } else { '0' }) }
        'DateTime' { return "'{0}'" -f $Text }
    }
    $Prefix = if ($Text -match '[^\x00-\x7F]') { 'N' } else { '' }
    return "{0}'{1}'" -f $Prefix, $Text.Replace("'", "''")
}

function ConvertTo-OmadaSqlPowerShellLiteral {
    <#
    .SYNOPSIS
    A value as a PowerShell literal, written as its column's kind.

    .DESCRIPTION
    $null; a number bare; $true or $false; a date as [datetime]'yyyy-MM-ddTHH:mm:ss.fff'; anything
    else as a single-quoted string, escaped as PowerShell itself does (which includes the typographic
    single quotes PowerShell also accepts as quote characters).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()]
        [object]$Value,

        [Parameter(Mandatory = $true)]
        [string]$Kind
    )

    $Text = Format-OmadaSqlExportValue -Value $Value
    if ($null -eq $Text) {
        return '$null'
    }
    switch ($Kind) {
        'Number' { return $Text }
        'Boolean' { return $(if ([bool]$Value) { '$true' } else { '$false' }) }
        'DateTime' { return "[datetime]'{0}'" -f $Text }
    }
    return "'{0}'" -f [System.Management.Automation.Language.CodeGeneration]::EscapeSingleQuotedStringContent($Text)
}

function Get-OmadaSqlLiteralTable {
    <#
    .SYNOPSIS
    Every value of a result as a literal of the given language, one string array per row, columns in order.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Row,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$Column,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Sql', 'PowerShell')]
        [string]$Language
    )

    $Kind = @{}
    foreach ($Name in $Column) {
        $Value = [System.Collections.Generic.List[object]]::new()
        foreach ($Item in $Row) {
            $Value.Add((Get-OmadaSqlExportCell -Row $Item -Column $Name))
        }
        $Kind[$Name] = Get-OmadaSqlColumnKind -Value $Value.ToArray()
    }
    $Table = [System.Collections.Generic.List[object]]::new()
    foreach ($Item in $Row) {
        $Literal = [System.Collections.Generic.List[string]]::new()
        foreach ($Name in $Column) {
            $Cell = Get-OmadaSqlExportCell -Row $Item -Column $Name
            $Literal.Add($(if ($Language -eq 'Sql') { ConvertTo-OmadaSqlSqlLiteral -Value $Cell -Kind $Kind[$Name] } else { ConvertTo-OmadaSqlPowerShellLiteral -Value $Cell -Kind $Kind[$Name] }))
        }
        $Table.Add([string[]]$Literal.ToArray())
    }
    return , $Table.ToArray()
}

function ConvertTo-OmadaSqlSqlArrayText {
    <#
    .SYNOPSIS
    T-SQL literals: (v1, v2, ...) for one column, ready for IN; (VALUES (...), ...) AS t ([a], [b]) for more.

    .DESCRIPTION
    A result without rows has nothing to write and gives an empty string: an empty IN list is not
    valid T-SQL.
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

    if ($Row.Count -eq 0 -or $Column.Count -eq 0) {
        return ''
    }
    $Table = Get-OmadaSqlLiteralTable -Row $Row -Column $Column -Language 'Sql'
    if ($Column.Count -eq 1) {
        return "(`r`n{0}`r`n)" -f ((@($Table | ForEach-Object { '    ' + $_[0] })) -join ",`r`n")
    }
    $Line = @($Table | ForEach-Object { '    ({0})' -f ($_ -join ', ') })
    $Name = @($Column | ForEach-Object { '[{0}]' -f $_.Replace(']', ']]') })
    return "(VALUES`r`n{0}`r`n) AS t ({1})" -f ($Line -join ",`r`n"), ($Name -join ', ')
}

function ConvertTo-OmadaSqlPowerShellArrayText {
    <#
    .SYNOPSIS
    PowerShell literals: @(v1, v2, ...) for one column; @([PSCustomObject]@{ ... } ...) for more.
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

    if ($Row.Count -eq 0 -or $Column.Count -eq 0) {
        return '@()'
    }
    $Table = Get-OmadaSqlLiteralTable -Row $Row -Column $Column -Language 'PowerShell'
    if ($Column.Count -eq 1) {
        return "@(`r`n{0}`r`n)" -f ((@($Table | ForEach-Object { '    ' + $_[0] })) -join ",`r`n")
    }
    $Key = @($Column | ForEach-Object { Format-OmadaSqlPowerShellKey -Name $_ })
    $Line = foreach ($Literal in $Table) {
        $Pair = for ($Index = 0; $Index -lt $Key.Count; $Index++) { '{0} = {1}' -f $Key[$Index], $Literal[$Index] }
        '    [PSCustomObject]@{{ {0} }}' -f (@($Pair) -join '; ')
    }
    return "@(`r`n{0}`r`n)" -f (@($Line) -join "`r`n")
}

function Format-OmadaSqlPowerShellKey {
    <#
    .SYNOPSIS
    A hashtable key: bare when it is a simple name, else single-quoted.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Name
    )

    if ($Name -match '^[A-Za-z_][A-Za-z0-9_]*$') {
        return $Name
    }
    return "'{0}'" -f [System.Management.Automation.Language.CodeGeneration]::EscapeSingleQuotedStringContent($Name)
}
