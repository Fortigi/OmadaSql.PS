function Get-OmadaSqlRuleContext {
    <#
    .SYNOPSIS
    What the query rules read: the parsed script, every statement node, the top-level statements, the
    query specifications whose result reaches Omada, and the scopes that must name every column.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Fragment,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Statement
    )

    $StatementType = [Microsoft.SqlServer.TransactSql.ScriptDom.TSqlStatement]
    [pscustomobject]@{
        Fragment                 = $Fragment
        TopStatement             = $Statement
        Statement                = @(Get-OmadaSqlFragmentDescendant -Fragment $Fragment | Where-Object { $StatementType.IsAssignableFrom($_.GetType()) })
        ResultQuerySpecification = @(Get-OmadaSqlResultScope -Statement $Statement)
        NamedScope               = @(Get-OmadaSqlNamedScope -Fragment $Fragment)
    }
}

function Get-OmadaSqlResultQuerySpecification {
    <#
    .SYNOPSIS
    The query specification whose SELECT list names the columns of a query expression, or $null.

    .DESCRIPTION
    For UNION, EXCEPT and INTERSECT the column names come from the first branch, so the first operand
    is followed. Parentheses are unwrapped.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$QueryExpression
    )

    $Current = $QueryExpression
    while ($null -ne $Current) {
        switch ($Current.GetType().Name) {
            'QuerySpecification' { return $Current }
            'BinaryQueryExpression' { $Current = $Current.FirstQueryExpression }
            'QueryParenthesisExpression' { $Current = $Current.QueryExpression }
            default { return $null }
        }
    }
    return $null
}

function Get-OmadaSqlResultScope {
    <#
    .SYNOPSIS
    The query specifications whose result set is returned to Omada: top-level SELECT statements only.

    .DESCRIPTION
    A nameless column only matters where the result reaches the client. A SELECT inside an IF, an
    INSERT ... SELECT, a subquery or a SELECT ... INTO (whose result goes to a table) does not count;
    flagging those would make the rule noise.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Statement
    )

    foreach ($Item in $Statement) {
        if ($Item.Fragment.GetType().Name -ne 'SelectStatement' -or $null -ne $Item.Fragment.Into) {
            continue
        }
        $Specification = Get-OmadaSqlResultQuerySpecification -QueryExpression $Item.Fragment.QueryExpression
        if ($null -ne $Specification) {
            $Specification
        }
    }
}

function Get-OmadaSqlNamedScope {
    <#
    .SYNOPSIS
    The query specifications where SQL Server requires every column to be named, with the reason.

    .DESCRIPTION
    A derived table, a common table expression without a column list and a SELECT ... INTO must name
    every column; SQL Server rejects the batch otherwise (Msg 8155). A CTE with a column list,
    WITH c (a, b) AS (...), names its columns there and is left out.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Fragment
    )

    $Node = @(Get-OmadaSqlFragmentDescendant -Fragment $Fragment -TypeName 'QueryDerivedTable', 'CommonTableExpression', 'SelectStatement' -IncludeSelf)
    foreach ($Item in $Node) {
        $Description = switch ($Item.GetType().Name) {
            'QueryDerivedTable' { 'derived table' }
            'CommonTableExpression' { if (@($Item.Columns).Count -eq 0) { 'common table expression' } }
            'SelectStatement' { if ($null -ne $Item.Into) { 'SELECT ... INTO' } }
        }
        if ($null -eq $Description) {
            continue
        }
        $Specification = Get-OmadaSqlResultQuerySpecification -QueryExpression $Item.QueryExpression
        if ($null -ne $Specification) {
            [pscustomobject]@{ QuerySpecification = $Specification; Description = $Description }
        }
    }
}
