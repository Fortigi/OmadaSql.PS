function Get-OmadaSqlSchemaRule {
    <#
    .SYNOPSIS
    The catalogue of schema rules: table and column names checked against the data connection's schema.

    .DESCRIPTION
    These rules need the schema of a data connection, so they only run when Test-OmadaSqlQuery is
    given -DataConnection. They default to Info, which never blocks: the schema is a cached copy, and
    a name it does not know can still exist on the server. -RuleSeverity changes them like any rule.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    [pscustomobject]@{ Id = 'OMD030'; Title = 'Table or view not in the schema'; Severity = 'Info' }
    [pscustomobject]@{ Id = 'OMD031'; Title = 'Column not in the schema'; Severity = 'Info' }
    [pscustomobject]@{ Id = 'OMD032'; Title = 'Ambiguous column'; Severity = 'Info' }
}

function Get-OmadaSqlSchemaDiagnostic {
    <#
    .SYNOPSIS
    Checks the table and column names of every statement against the schema of its data connection.

    .DESCRIPTION
    Runs only on a script without syntax errors and without the database-name findings (OMD020,
    OMD021) that keep its statements from being bound to a data connection. A statement without a
    data connection is not checked. Each data connection's schema is read once per connection.
    #>
    [CmdletBinding()]
    [OutputType('OmadaSql.Diagnostic')]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Context,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Statement,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Diagnostic,

        [AllowNull()]
        [object]$DataConnection,

        [AllowNull()]
        [hashtable]$RuleSeverity
    )

    if (@($Diagnostic | Where-Object { $_.Source -eq 'T-SQL syntax' -or $_.RuleId -in 'OMD020', 'OMD021' }).Count -gt 0) {
        Write-OmadaSqlLog -Message 'Schema rules skipped: the script has syntax or database-name findings.'
        return
    }
    $Severity = Resolve-OmadaSqlRuleSeverity -RuleSeverity $RuleSeverity
    if (@(Get-OmadaSqlSchemaRule | Where-Object { $Severity[$_.Id] -ne 'Off' }).Count -eq 0) {
        return
    }
    $ScriptName = Get-OmadaSqlScriptDefinedName -Statement $Statement
    foreach ($Target in @(Resolve-OmadaSqlStatementTarget -Context $Context -Statement $Statement -DataConnection $DataConnection)) {
        if ($null -eq $Target.DataConnection) {
            continue
        }
        $Item = @($Statement | Where-Object { $_.Ordinal -eq $Target.Ordinal })[0]
        $Model = Get-OmadaSqlSchemaModel -Context $Context -DataConnection $Target.DataConnection
        foreach ($Hit in @(Find-OmadaSqlSchemaFinding -Fragment $Item.Fragment -Model $Model -ScriptName $ScriptName)) {
            if ($Severity[$Hit.RuleId] -ne 'Off') {
                New-OmadaSqlDiagnostic -RuleId $Hit.RuleId -Severity $Severity[$Hit.RuleId] -Line $Hit.Fragment.StartLine -Column $Hit.Fragment.StartColumn -Message $Hit.Message -Source 'Schema'
            }
        }
    }
}

function Get-OmadaSqlScriptDefinedName {
    <#
    .SYNOPSIS
    The table names the script defines itself: CTE names, SELECT ... INTO targets and CREATE TABLE names.

    .DESCRIPTION
    A one-part reference to one of these is not looked up in the schema: it is not there.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Statement
    )

    $Name = @{}
    foreach ($Item in $Statement) {
        foreach ($Node in @(Get-OmadaSqlFragmentDescendant -Fragment $Item.Fragment -IncludeSelf -TypeName 'CommonTableExpression', 'SelectStatement', 'CreateTableStatement')) {
            $Defined = switch ($Node.GetType().Name) {
                'CommonTableExpression' { $Node.ExpressionName.Value }
                'SelectStatement' { if ($null -ne $Node.Into) { $Node.Into.BaseIdentifier.Value } }
                default { $Node.SchemaObjectName.BaseIdentifier.Value }
            }
            if ($null -ne $Defined) {
                $Name[[string]$Defined] = $true
            }
        }
    }
    return $Name
}

function Find-OmadaSqlSchemaFinding {
    <#
    .SYNOPSIS
    The schema findings of one statement: unknown tables (OMD030), then unknown or ambiguous columns.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Fragment,

        [Parameter(Mandatory = $true)]
        [hashtable]$Model,

        [Parameter(Mandatory = $true)]
        [hashtable]$ScriptName
    )

    foreach ($Reference in @(Get-OmadaSqlFragmentDescendant -Fragment $Fragment -IncludeSelf -TypeName 'NamedTableReference')) {
        if ((Resolve-OmadaSqlSchemaReference -Reference $Reference -Model $Model -ScriptName $ScriptName).Missing) {
            $Written = (@($Reference.SchemaObject.Identifiers) | ForEach-Object { $_.Value }) -join '.'
            @{ RuleId = 'OMD030'; Fragment = $Reference; Message = ("'{0}' is not in the schema of data connection '{1}'. Check the name, or read the schema again with Get-OmadaSqlSchema -Force if the database changed." -f $Written, $Model.DataConnection.Name) }
        }
    }
    foreach ($Scope in @(Get-OmadaSqlSchemaScope -Fragment $Fragment -Model $Model -ScriptName $ScriptName)) {
        Find-OmadaSqlSchemaColumnFinding -Scope $Scope -Model $Model
    }
}

function Find-OmadaSqlSchemaColumnFinding {
    <#
    .SYNOPSIS
    The column findings of one query scope, or none when a source of the scope cannot be resolved.

    .DESCRIPTION
    A derived table, a function, a CTE, a temporary table or an unknown table hides which columns it
    has (it is opaque), so a scope with one among its own sources is not checked: a guess would be
    noise. In an enclosing scope an opaque source only stops the names that could come from it. An
    unqualified name that is an alias of the SELECT list (used in ORDER BY) is not a table column.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Scope,

        [Parameter(Mandatory = $true)]
        [hashtable]$Model
    )

    if (@($Scope.Level[0] | Where-Object { $_.Opaque }).Count -gt 0) {
        return
    }
    foreach ($Column in $Scope.Column) {
        $Identifier = @($Column.MultiPartIdentifier.Identifiers | ForEach-Object { $_.Value })
        $Message = if ($Identifier.Count -eq 1) {
            Test-OmadaSqlUnqualifiedColumn -Scope $Scope -Model $Model -Name $Identifier[0]
        }
        else {
            Test-OmadaSqlQualifiedColumn -Scope $Scope -Model $Model -Qualifier $Identifier[-2] -Name $Identifier[-1]
        }
        if ($null -ne $Message) {
            @{ RuleId = $Message.RuleId; Fragment = $Column; Message = $Message.Text }
        }
    }
}

function Test-OmadaSqlUnqualifiedColumn {
    <#
    .SYNOPSIS
    OMD031 or OMD032 for a column without a table name, resolved from the innermost scope outward.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Scope,

        [Parameter(Mandatory = $true)]
        [hashtable]$Model,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if ($Scope.Alias.ContainsKey($Name)) {
        return $null
    }
    foreach ($Level in $Scope.Level) {
        $Owner = @($Level | Where-Object { -not $_.Opaque -and $Model.Column[$_.Entry.Name].ContainsKey($Name) })
        if ($Owner.Count -gt 1) {
            return @{ RuleId = 'OMD032'; Text = ("Column '{0}' is ambiguous: {1} tables in this query have a column with that name ({2}). Qualify it with a table name or alias." -f $Name, $Owner.Count, (($Owner | ForEach-Object { $_.Name }) -join ', ')) }
        }
        if ($Owner.Count -eq 1 -or @($Level | Where-Object { $_.Opaque }).Count -gt 0) {
            return $null
        }
    }
    return @{ RuleId = 'OMD031'; Text = ("Column '{0}' is not on any table of this query in the schema of data connection '{1}'. Check the name, or read the schema again with Get-OmadaSqlSchema -Force if the database changed." -f $Name, $Model.DataConnection.Name) }
}

function Test-OmadaSqlQualifiedColumn {
    <#
    .SYNOPSIS
    OMD031 for a column whose table or alias is known but does not have it. An unknown qualifier is left alone.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Scope,

        [Parameter(Mandatory = $true)]
        [hashtable]$Model,

        [Parameter(Mandatory = $true)]
        [string]$Qualifier,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    foreach ($Level in $Scope.Level) {
        $Source = @($Level | Where-Object { $_.Name -eq $Qualifier })
        if ($Source.Count -eq 0) {
            continue
        }
        if ($Source[0].Opaque -or $Model.Column[$Source[0].Entry.Name].ContainsKey($Name)) {
            return $null
        }
        return @{ RuleId = 'OMD031'; Text = ("Column '{0}' is not on '{1}' in the schema of data connection '{2}'. Check the name, or read the schema again with Get-OmadaSqlSchema -Force if the database changed." -f $Name, $Source[0].Entry.Name, $Model.DataConnection.Name) }
    }
    return $null
}
