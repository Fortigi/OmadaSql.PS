function Get-OmadaSqlDiagnostic {
    <#
    .SYNOPSIS
    Parses a script once and returns its syntax errors and rule findings, with the statements.

    .DESCRIPTION
    Syntax errors come first. The rules only run on a script that parsed cleanly: on a tree the
    parser had to recover, a rule would report on statements the user did not write.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Sql,

        [AllowNull()]
        [hashtable]$RuleSeverity
    )

    $Severity = Resolve-OmadaSqlRuleSeverity -RuleSeverity $RuleSeverity
    $Parsed = ConvertTo-OmadaSqlScriptFragment -Sql $Sql
    $Statement = @(Split-OmadaSqlStatement -Fragment $Parsed.Fragment -Sql $Sql)
    $Diagnostic = @(ConvertTo-OmadaSqlSyntaxDiagnostic -ParseError $Parsed.ParseError)
    if ($Diagnostic.Count -eq 0 -and $null -ne $Parsed.Fragment) {
        $Context = Get-OmadaSqlRuleContext -Fragment $Parsed.Fragment -Statement $Statement
        $Diagnostic = @(Get-OmadaSqlRuleDiagnostic -Context $Context -Severity $Severity)
    }
    [pscustomobject]@{
        Diagnostic    = $Diagnostic
        Statement     = $Statement
        ParserVersion = $Parsed.ParserVersion
    }
}

function Get-OmadaSqlRuleDiagnostic {
    <#
    .SYNOPSIS
    Runs every rule that is not Off and returns its findings, ordered by position.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Context,

        [Parameter(Mandatory = $true)]
        [hashtable]$Severity
    )

    $Finding = [System.Collections.Generic.List[object]]::new()
    foreach ($Rule in @(Get-OmadaSqlRule)) {
        if ($Severity[$Rule.Id] -eq 'Off') {
            continue
        }
        foreach ($Hit in @(& $Rule.Find $Context)) {
            $Finding.Add((New-OmadaSqlDiagnostic -RuleId $Rule.Id -Severity $Severity[$Rule.Id] -Line $Hit.Fragment.StartLine -Column $Hit.Fragment.StartColumn -Message $Hit.Message -Source 'Omada compatibility'))
        }
    }
    $Finding | Sort-Object -Property Line, Column, RuleId
}

function ConvertTo-OmadaSqlSyntaxDiagnostic {
    <#
    .SYNOPSIS
    Turns ScriptDom parse errors into diagnostics. A syntax error always blocks execution.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$ParseError
    )

    foreach ($Item in $ParseError) {
        New-OmadaSqlDiagnostic -RuleId ('SQL{0}' -f $Item.Number) -Severity 'Error' -Line $Item.Line -Column $Item.Column -Message $Item.Message -Source 'T-SQL syntax'
    }
}

function New-OmadaSqlDiagnostic {
    <#
    .SYNOPSIS
    One OmadaSql.Diagnostic. Blocking is true for Error and Warning: those stop execution unless
    -SkipValidation is used.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds an object in memory and changes no state.')]
    [CmdletBinding()]
    [OutputType('OmadaSql.Diagnostic')]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RuleId,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Error', 'Warning', 'Info')]
        [string]$Severity,

        [Parameter(Mandatory = $true)]
        [int]$Line,

        [Parameter(Mandatory = $true)]
        [int]$Column,

        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $true)]
        [string]$Source
    )

    [pscustomobject]@{
        PSTypeName = 'OmadaSql.Diagnostic'
        RuleId     = $RuleId
        Severity   = $Severity
        Blocking   = ($Severity -ne 'Info')
        Line       = $Line
        Column     = $Column
        Message    = $Message
        Source     = $Source
    }
}

function Resolve-OmadaSqlRuleSeverity {
    <#
    .SYNOPSIS
    The severity every rule runs at: its default, overridden by -RuleSeverity.

    .DESCRIPTION
    An override names a rule id and Error, Warning, Info or Off. An unknown id or value is an
    OmadaSql.InvalidArgument error rather than being ignored, so a typo cannot quietly leave a rule
    at a severity the caller meant to change.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [AllowNull()]
        [hashtable]$RuleSeverity
    )

    $Severity = @{}
    foreach ($Rule in @(Get-OmadaSqlRule) + @(Get-OmadaSqlSchemaRule)) {
        $Severity[$Rule.Id] = $Rule.Severity
    }
    if ($null -eq $RuleSeverity) {
        return $Severity
    }
    foreach ($Key in @($RuleSeverity.Keys)) {
        $Value = [string]$RuleSeverity[$Key]
        if (-not $Severity.ContainsKey([string]$Key)) {
            throw (New-OmadaSqlErrorRecord -Kind 'InvalidArgument' -Message ("Unknown rule '{0}' in -RuleSeverity. Known rules: {1}." -f $Key, ((@($Severity.Keys) | Sort-Object) -join ', ')) -TargetObject $Key)
        }
        if ($Value -notin 'Error', 'Warning', 'Info', 'Off') {
            throw (New-OmadaSqlErrorRecord -Kind 'InvalidArgument' -Message ("Severity '{0}' for rule '{1}' is not Error, Warning, Info or Off." -f $Value, $Key) -TargetObject $Value)
        }
        $Severity[[string]$Key] = $Value
    }
    return $Severity
}
