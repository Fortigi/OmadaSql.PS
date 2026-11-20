function Get-OmadaSqlSchemaScope {
    <#
    .SYNOPSIS
    The query scopes of a statement: one per query specification, with the sources it sees and its columns.

    .DESCRIPTION
    A scope's Level list holds its own sources first, then those of each enclosing scope, so a
    correlated subquery resolves a name from the inside out as SQL Server does. A derived table in a
    FROM clause does not see the other sources of that FROM clause, except on the right of CROSS APPLY
    or OUTER APPLY. A column reference belongs to its innermost scope only. The date part of DATEADD, DATEDIFF, DATEDIFF_BIG, DATENAME,
    DATEPART and DATETRUNC is parsed as a column reference and is left out.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Fragment,

        [Parameter(Mandatory = $true)]
        [hashtable]$Model,

        [Parameter(Mandatory = $true)]
        [hashtable]$ScriptName
    )

    $State = @{
        Model      = $Model
        ScriptName = $ScriptName
        Scope      = [System.Collections.Generic.List[object]]::new()
        Seen       = [System.Collections.Generic.HashSet[object]]::new()
        Ignore     = [System.Collections.Generic.HashSet[object]]::new()
        Apply      = [System.Collections.Generic.HashSet[object]]::new()
    }
    Add-OmadaSqlSchemaScopeNode -Node $Fragment -Level ([System.Collections.Generic.List[object]]::new()) -Current $null -State $State
    return $State.Scope.ToArray()
}

function Add-OmadaSqlSchemaScopeNode {
    <#
    .SYNOPSIS
    Walks one fragment and its children, opening a scope at each query specification.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Node,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[object]]$Level,

        [AllowNull()]
        [object]$Current,

        [Parameter(Mandatory = $true)]
        [hashtable]$State
    )

    if (-not $State.Seen.Add($Node)) {
        return
    }
    switch ($Node.GetType().Name) {
        'QuerySpecification' {
            $Current = New-OmadaSqlSchemaScope -Specification $Node -Enclosing $Level -State $State
            $Level = $Current.Level
            $State.Scope.Add($Current)
        }
        'ColumnReferenceExpression' {
            if ($null -ne $Current -and (Test-OmadaSqlSchemaColumnReference -Node $Node -State $State)) {
                $Current.Column.Add($Node)
            }
            return
        }
        'FunctionCall' {
            Add-OmadaSqlDatePartIgnore -Node $Node -State $State
        }
        'UnqualifiedJoin' {
            if ($Node.UnqualifiedJoinType.ToString() -in 'CrossApply', 'OuterApply') {
                $null = $State.Apply.Add($Node.SecondTableReference)
            }
        }
        'QueryDerivedTable' {
            if ($null -ne $Current -and -not $State.Apply.Contains($Node)) {
                $Level = $Current.Enclosing
            }
        }
    }
    foreach ($Child in @(Get-OmadaSqlFragmentChild -Fragment $Node)) {
        Add-OmadaSqlSchemaScopeNode -Node $Child -Level $Level -Current $Current -State $State
    }
}

function Test-OmadaSqlSchemaColumnReference {
    <#
    .SYNOPSIS
    Whether a column reference names a table column: a regular column with a name, not a date part.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Node,

        [Parameter(Mandatory = $true)]
        [hashtable]$State
    )

    return (-not $State.Ignore.Contains($Node) -and $Node.ColumnType.ToString() -eq 'Regular' -and $null -ne $Node.MultiPartIdentifier)
}

function Add-OmadaSqlDatePartIgnore {
    <#
    .SYNOPSIS
    Marks the date part of a date function (DATEADD(day, ...)), which ScriptDom parses as a column reference.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Node,

        [Parameter(Mandatory = $true)]
        [hashtable]$State
    )

    if ($Node.FunctionName.Value -in 'DATEADD', 'DATEDIFF', 'DATEDIFF_BIG', 'DATENAME', 'DATEPART', 'DATETRUNC' -and $Node.Parameters.Count -gt 0) {
        $null = $State.Ignore.Add($Node.Parameters[0])
    }
}

function New-OmadaSqlSchemaScope {
    <#
    .SYNOPSIS
    One scope: the specification, its levels of sources (own first), its SELECT-list aliases and its columns.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds an object in memory and changes no state.')]
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Specification,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[object]]$Enclosing,

        [Parameter(Mandatory = $true)]
        [hashtable]$State
    )

    $Level = [System.Collections.Generic.List[object]]::new()
    $Level.Add([object[]]@(Get-OmadaSqlScopeSource -Specification $Specification -Model $State.Model -ScriptName $State.ScriptName))
    foreach ($Item in $Enclosing) {
        $Level.Add($Item)
    }
    $Alias = @{}
    foreach ($Element in @($Specification.SelectElements)) {
        $ColumnName = Get-OmadaSqlPropertyValue -InputObject $Element -Name 'ColumnName'
        if ($null -ne $ColumnName) {
            $Alias[[string]$ColumnName.Value] = $true
        }
    }
    [pscustomobject]@{
        Specification = $Specification
        Enclosing     = $Enclosing
        Level         = $Level
        Alias         = $Alias
        Column        = [System.Collections.Generic.List[object]]::new()
    }
}

function Get-OmadaSqlScopeSource {
    <#
    .SYNOPSIS
    The sources of a query specification's FROM clause, joins flattened: Name, Entry and Opaque.

    .DESCRIPTION
    A source is named by its alias, else by its table name. A source is opaque when the schema cannot
    say which columns it has: anything but a table or view name, or a name the schema does not
    resolve to exactly one table.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Specification,

        [Parameter(Mandatory = $true)]
        [hashtable]$Model,

        [Parameter(Mandatory = $true)]
        [hashtable]$ScriptName
    )

    $From = Get-OmadaSqlPropertyValue -InputObject $Specification -Name 'FromClause'
    if ($null -eq $From) {
        return
    }
    foreach ($Reference in @($From.TableReferences | ForEach-Object { Get-OmadaSqlTableReferenceLeaf -Reference $_ })) {
        $Alias = Get-OmadaSqlPropertyValue -InputObject $Reference -Name 'Alias'
        $Name = if ($null -ne $Alias) { [string]$Alias.Value } else { $null }
        $Entry = $null
        if ($Reference.GetType().Name -eq 'NamedTableReference') {
            $Entry = (Resolve-OmadaSqlSchemaReference -Reference $Reference -Model $Model -ScriptName $ScriptName).Entry
            if ($null -eq $Name) {
                $Name = [string]$Reference.SchemaObject.BaseIdentifier.Value
            }
        }
        [pscustomobject]@{ Name = $Name; Entry = $Entry; Opaque = ($null -eq $Entry) }
    }
}

function Get-OmadaSqlTableReferenceLeaf {
    <#
    .SYNOPSIS
    The table references a FROM item joins, with joins and parenthesised joins flattened.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Reference
    )

    switch ($Reference.GetType().Name) {
        'JoinParenthesisTableReference' { Get-OmadaSqlTableReferenceLeaf -Reference $Reference.Join }
        { $_ -in 'QualifiedJoin', 'UnqualifiedJoin' } {
            Get-OmadaSqlTableReferenceLeaf -Reference $Reference.FirstTableReference
            Get-OmadaSqlTableReferenceLeaf -Reference $Reference.SecondTableReference
        }
        default { $Reference }
    }
}

function Resolve-OmadaSqlSchemaReference {
    <#
    .SYNOPSIS
    Looks a table name up in the schema. Entry is the table, or $null; Missing is $true only when the
    schema shows the name does not exist.

    .DESCRIPTION
    Not looked up, so neither found nor missing: a four-part (linked server) name, a temporary table
    or table variable, and a one-part name the script defines itself. For a three-part name the
    database is the statement's data connection, so the last two parts are used. A name without a
    schema resolves to the one schema that has it, else to dbo; in several other schemas it is
    ambiguous, which is not reported as missing.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Reference,

        [Parameter(Mandatory = $true)]
        [hashtable]$Model,

        [Parameter(Mandatory = $true)]
        [hashtable]$ScriptName
    )

    $Identifier = @($Reference.SchemaObject.Identifiers | ForEach-Object { [string]$_.Value })
    if (-not (Test-OmadaSqlSchemaLookup -Identifier $Identifier -ScriptName $ScriptName)) {
        return [pscustomobject]@{ Entry = $null; Missing = $false }
    }
    if ($Identifier.Count -gt 1) {
        $Entry = $Model.Table[('{0}.{1}' -f $Identifier[-2], $Identifier[-1])]
        return [pscustomobject]@{ Entry = $Entry; Missing = ($null -eq $Entry) }
    }
    $Candidate = @($Model.ByName[$Identifier[0]] | Where-Object { $null -ne $_ })
    if ($Candidate.Count -eq 0) {
        return [pscustomobject]@{ Entry = $null; Missing = $true }
    }
    if ($Candidate.Count -gt 1) {
        $Candidate = @($Candidate | Where-Object { $_.Schema -eq 'dbo' })
    }
    $Entry = $null
    if ($Candidate.Count -eq 1) {
        $Entry = $Candidate[0]
    }
    return [pscustomobject]@{ Entry = $Entry; Missing = $false }
}

function Test-OmadaSqlSchemaLookup {
    <#
    .SYNOPSIS
    Whether a table name is looked up in the schema: one to three parts, not a temporary table or table
    variable, and not a one-part name the script defines.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$Identifier,

        [Parameter(Mandatory = $true)]
        [hashtable]$ScriptName
    )

    if ($Identifier.Count -eq 0 -or $Identifier.Count -gt 3) {
        return $false
    }
    $Table = $Identifier[-1]
    if ($Table.StartsWith('#') -or $Table.StartsWith('@')) {
        return $false
    }
    return -not ($Identifier.Count -eq 1 -and $ScriptName.ContainsKey($Table))
}
