function Get-OmadaSqlRule {
    <#
    .SYNOPSIS
    The catalogue of query rules: what SQL Troubleshooting cannot run, or runs with a surprising result.

    .DESCRIPTION
    A rule is data, so a new Omada quirk costs a table entry and a test:
      Id        OMDnnn, the name used in -RuleSeverity and in every diagnostic
      Title     a short name
      Severity  the default: Error and Warning block execution, Info does not
      Find      the function that checks the rule: it takes the rule context
                (Get-OmadaSqlRuleContext) and returns @{ Fragment; Message } for every place it flags

    OMD001, OMD003, OMD004 and OMD010-OMD013 are taken over from OmadaSqlTroubleshooter, which
    numbered them. OMD020 and OMD021 are this module's: they report, before anything is sent, the
    database names Resolve-OmadaSqlStatementTarget would refuse.

    No rule enforces anything on the tenant. The tenant's permissions do; these rules explain the
    boundary before the query meets it, and -RuleSeverity or -SkipValidation overrules them.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    [pscustomobject]@{ Id = 'OMD001'; Title = 'Result column has no name'; Severity = 'Warning'; Find = 'Find-OmadaSqlNamelessResultColumn' }
    [pscustomobject]@{ Id = 'OMD003'; Title = 'Alias is renamed in the result'; Severity = 'Info'; Find = 'Find-OmadaSqlRenamedAlias' }
    [pscustomobject]@{ Id = 'OMD004'; Title = 'Nameless column in a derived table, CTE or SELECT INTO'; Severity = 'Error'; Find = 'Find-OmadaSqlNamelessScopedColumn' }
    [pscustomobject]@{ Id = 'OMD010'; Title = 'Data manipulation is not available'; Severity = 'Error'; Find = 'Find-OmadaSqlDataManipulation' }
    [pscustomobject]@{ Id = 'OMD011'; Title = 'Data definition is not available'; Severity = 'Error'; Find = 'Find-OmadaSqlDataDefinition' }
    [pscustomobject]@{ Id = 'OMD012'; Title = 'Stored procedures and dynamic SQL are not available'; Severity = 'Error'; Find = 'Find-OmadaSqlExecute' }
    [pscustomobject]@{ Id = 'OMD013'; Title = 'Temporary tables are not available'; Severity = 'Error'; Find = 'Find-OmadaSqlTemporaryTable' }
    [pscustomobject]@{ Id = 'OMD020'; Title = 'Four-part name'; Severity = 'Error'; Find = 'Find-OmadaSqlFourPartName' }
    [pscustomobject]@{ Id = 'OMD021'; Title = 'More than one database in one statement'; Severity = 'Error'; Find = 'Find-OmadaSqlCrossDatabase' }
}

function Find-OmadaSqlNamelessResultColumn {
    <#
    .SYNOPSIS
    OMD001: a result column without a name. Omada returns no rows for such a result set.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][pscustomobject]$Context)

    foreach ($Element in @($Context.ResultQuerySpecification | ForEach-Object { $_.SelectElements })) {
        if (Test-OmadaSqlSelectElementNameless -SelectElement $Element) {
            @{ Fragment = $Element; Message = ("This column has no name. Omada returns no rows for a result set with an unnamed column: the query runs, but the result is empty. Add an alias, for example AS [{0}]." -f (Get-OmadaSqlSuggestedColumnAlias -Expression $Element.Expression)) }
        }
    }
}

function Find-OmadaSqlRenamedAlias {
    <#
    .SYNOPSIS
    OMD003: an alias with characters Omada replaces by an underscore.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][pscustomobject]$Context)

    foreach ($Element in @($Context.ResultQuerySpecification | ForEach-Object { $_.SelectElements })) {
        # Only a scalar expression has a ColumnName; read StrictMode-safe so SELECT * passes through.
        $ColumnName = Get-OmadaSqlPropertyValue -InputObject $Element -Name 'ColumnName'
        if ($null -ne $ColumnName -and [string]$ColumnName.Value -match '[^A-Za-z0-9_\-]') {
            @{ Fragment = $ColumnName; Message = ("The alias '{0}' contains characters Omada replaces: every character outside A-Z, a-z, 0-9, _ and - becomes an underscore, so the column arrives under a different name." -f $ColumnName.Value) }
        }
    }
}

function Find-OmadaSqlNamelessScopedColumn {
    <#
    .SYNOPSIS
    OMD004: a nameless column where SQL Server requires a name (Msg 8155).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][pscustomobject]$Context)

    foreach ($Scope in $Context.NamedScope) {
        foreach ($Element in @($Scope.QuerySpecification.SelectElements)) {
            if (Test-OmadaSqlSelectElementNameless -SelectElement $Element) {
                @{ Fragment = $Element; Message = ("This column has no name, and SQL Server requires one in a {0} (Msg 8155): the statement fails. Add an alias, for example AS [{1}]." -f $Scope.Description, (Get-OmadaSqlSuggestedColumnAlias -Expression $Element.Expression)) }
            }
        }
    }
}

function Find-OmadaSqlDataManipulation {
    <#
    .SYNOPSIS
    OMD010: INSERT, UPDATE, DELETE, MERGE or TRUNCATE TABLE, anywhere in the script.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][pscustomobject]$Context)

    $Keyword = @{ InsertStatement = 'INSERT'; UpdateStatement = 'UPDATE'; DeleteStatement = 'DELETE'; MergeStatement = 'MERGE'; TruncateTableStatement = 'TRUNCATE TABLE' }
    foreach ($Statement in $Context.Statement) {
        $Name = $Statement.GetType().Name
        if ($Keyword.ContainsKey($Name)) {
            @{ Fragment = $Statement; Message = ("SQL Troubleshooting has read access only. {0} cannot run; use a SELECT to inspect the data." -f $Keyword[$Name]) }
        }
    }
}

function Find-OmadaSqlDataDefinition {
    <#
    .SYNOPSIS
    OMD011: CREATE, ALTER or DROP. Matched on the statement kind, never on the text.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][pscustomobject]$Context)

    foreach ($Statement in $Context.Statement) {
        if ($Statement.GetType().Name -match '^(Create|Alter|Drop)\w*Statement$') {
            @{ Fragment = $Statement; Message = 'SQL Troubleshooting has read access only. Creating, altering or dropping database objects cannot run; use a SELECT to inspect the data.' }
        }
    }
}

function Find-OmadaSqlExecute {
    <#
    .SYNOPSIS
    OMD012: EXEC, EXECUTE or sp_executesql.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][pscustomobject]$Context)

    foreach ($Statement in $Context.Statement) {
        if ($Statement.GetType().Name -eq 'ExecuteStatement') {
            @{ Fragment = $Statement; Message = 'Stored procedures cannot be executed from SQL Troubleshooting, so EXEC, EXECUTE and sp_executesql are unavailable.' }
        }
    }
}

function Find-OmadaSqlTemporaryTable {
    <#
    .SYNOPSIS
    OMD013: a #temporary table, read, written or created.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][pscustomobject]$Context)

    foreach ($Item in @(Get-OmadaSqlFragmentDescendant -Fragment $Context.Fragment -TypeName 'SchemaObjectName')) {
        if ($Item.BaseIdentifier.Value.StartsWith('#')) {
            @{ Fragment = $Item; Message = 'Temporary tables are not available. Use a common table expression (WITH ... AS (...)) instead.' }
        }
    }
}

function Find-OmadaSqlFourPartName {
    <#
    .SYNOPSIS
    OMD020: a four-part (linked server) name.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][pscustomobject]$Context)

    foreach ($Item in $Context.TopStatement) {
        if ((Get-OmadaSqlDatabaseReference -Statement $Item.Fragment).FourPartName) {
            @{ Fragment = $Item.Fragment; Message = 'Four-part (linked server) names are not supported: a query runs against one data connection, which cannot reach another server.' }
        }
    }
}

function Find-OmadaSqlCrossDatabase {
    <#
    .SYNOPSIS
    OMD021: more than one database in one statement.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][pscustomobject]$Context)

    foreach ($Item in $Context.TopStatement) {
        $Database = @((Get-OmadaSqlDatabaseReference -Statement $Item.Fragment).Database)
        if ($Database.Count -gt 1) {
            @{ Fragment = $Item.Fragment; Message = ("This statement addresses more than one database ({0}). A statement runs against one data connection; split it into one statement per database." -f ($Database -join ', ')) }
        }
    }
}

function Test-OmadaSqlSelectElementNameless {
    <#
    .SYNOPSIS
    Whether a SELECT element produces a result column without a name.

    .DESCRIPTION
    A scalar expression without an alias is nameless unless it is a plain column reference, which is
    named by the column. SELECT * takes its names from the table and is not flagged.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$SelectElement
    )

    if ($null -eq $SelectElement -or $SelectElement.GetType().Name -ne 'SelectScalarExpression') {
        return $false
    }
    if ($null -ne $SelectElement.ColumnName) {
        return $false
    }
    return ($SelectElement.Expression.GetType().Name -ne 'ColumnReferenceExpression')
}

function Get-OmadaSqlSuggestedColumnAlias {
    <#
    .SYNOPSIS
    An alias to suggest for a nameless column: the function name, Value for a literal or conversion,
    Case for a CASE, else Column. Only characters Omada keeps.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Expression
    )

    $Suggestion = switch -Regex ($Expression.GetType().Name) {
        '^FunctionCall$' { [string]$Expression.FunctionName.Value; break }
        '(Literal|^ConvertCall|^CastCall|^ScalarSubquery)$' { 'Value'; break }
        'CaseExpression$' { 'Case'; break }
        default { 'Column' }
    }
    return ($Suggestion -replace '[^A-Za-z0-9_\-]', '_')
}
