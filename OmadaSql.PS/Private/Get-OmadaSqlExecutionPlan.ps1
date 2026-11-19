function Get-OmadaSqlExecutionPlan {
    <#
    .SYNOPSIS
    Turns a script into the statements to run, each with its data connection and the text to send.

    .DESCRIPTION
    Validates the script (blocking findings stop it, see Test-OmadaSqlQuery), splits it into
    statements and resolves database names to data connections. Nothing is sent to the tenant before
    every statement has a data connection.

    With -SkipValidation no rule runs. The script is still split and its database names resolved when
    it parses; a script the parser cannot read, or a parser that cannot be loaded, is sent as one
    statement to -DataConnection, exactly as written.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Context,

        [Parameter(Mandatory = $true)]
        [string]$Sql,

        [AllowNull()]
        [object]$DataConnection,

        [AllowNull()]
        [hashtable]$RuleSeverity,

        [switch]$SkipValidation
    )

    if ($SkipValidation) {
        $Statement = Get-OmadaSqlUncheckedStatement -Sql $Sql
    }
    else {
        $Result = Get-OmadaSqlDiagnostic -Sql $Sql -RuleSeverity $RuleSeverity
        Assert-OmadaSqlNoBlockingDiagnostic -Diagnostic $Result.Diagnostic
        $Statement = $Result.Statement
    }
    if ($null -eq $Statement) {
        $Target = @([pscustomobject]@{ PSTypeName = 'OmadaSql.StatementTarget'; Ordinal = 1; Line = 1; Text = $Sql; DataConnection = $null })
        if ($null -ne $DataConnection) {
            $Target[0].DataConnection = Resolve-OmadaSqlDataConnection -Context $Context -DataConnection $DataConnection
        }
    }
    else {
        $Target = @(Resolve-OmadaSqlStatementTarget -Context $Context -Statement @($Statement) -DataConnection $DataConnection)
    }
    foreach ($Item in $Target) {
        if ($null -eq $Item.DataConnection) {
            throw (New-OmadaSqlErrorRecord -Kind 'InvalidArgument' -Message ("Statement {0} (line {1}) has no data connection. Use -DataConnection, a USE statement or a [DataConnection].schema.table name." -f $Item.Ordinal, $Item.Line))
        }
    }
    return , $Target
}

function Get-OmadaSqlUncheckedStatement {
    <#
    .SYNOPSIS
    The statements of a script when validation is skipped, or $null to send the script as one statement.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Sql
    )

    try {
        $Parsed = ConvertTo-OmadaSqlScriptFragment -Sql $Sql
    }
    catch {
        Write-OmadaSqlLog -Message ("Validation skipped and the parser is unavailable; the script is sent as one statement: {0}" -f $_.Exception.Message)
        return $null
    }
    if (@($Parsed.ParseError).Count -gt 0) {
        return $null
    }
    return , @(Split-OmadaSqlStatement -Fragment $Parsed.Fragment -Sql $Sql)
}

function Assert-OmadaSqlNoBlockingDiagnostic {
    <#
    .SYNOPSIS
    Throws OmadaSql.ValidationFailed, listing them, when any diagnostic blocks execution.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Diagnostic
    )

    $Blocking = @($Diagnostic | Where-Object { $_.Blocking })
    if ($Blocking.Count -eq 0) {
        return
    }
    $Lines = @($Blocking | ForEach-Object { '  line {0}, column {1}: {2} {3}: {4}' -f $_.Line, $_.Column, $_.Severity, $_.RuleId, $_.Message })
    throw (New-OmadaSqlErrorRecord -Kind 'ValidationFailed' -Message ("The query was not sent: {0} blocking finding(s).`n{1}`nFix the query, change a rule with -RuleSeverity, or use -SkipValidation." -f $Blocking.Count, ($Lines -join "`n")))
}
