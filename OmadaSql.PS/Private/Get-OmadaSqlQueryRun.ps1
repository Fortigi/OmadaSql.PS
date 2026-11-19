function Get-OmadaSqlQueryRun {
    <#
    .SYNOPSIS
    What Invoke-OmadaSqlQuery runs: the statement targets, and the id of a saved object to execute
    directly when that is possible.

    .DESCRIPTION
    A saved object runs as it is only when nothing about the run differs from the object: one
    statement, no database name to remove and no -DataConnection override. Then DirectId is its id
    and it is never written. Otherwise its text runs through a temporary object, so the saved object
    is still never changed.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Context,

        [Parameter(Mandatory = $true)]
        [string]$ParameterSetName,

        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Parameter
    )

    $Saved = Get-OmadaSqlSavedQuery -Context $Context -ParameterSetName $ParameterSetName -Parameter $Parameter
    $Sql = Get-OmadaSqlRunText -ParameterSetName $ParameterSetName -Parameter $Parameter -Saved $Saved
    $DataConnection = $Parameter['DataConnection']
    if ($null -eq $DataConnection -and $null -ne $Saved) {
        $DataConnection = $Saved.DataConnectionId
    }
    $Target = Get-OmadaSqlExecutionPlan -Context $Context -Sql $Sql -DataConnection $DataConnection -RuleSeverity $Parameter['RuleSeverity'] -SkipValidation:([bool]$Parameter['SkipValidation'])
    $DirectId = 0
    if ($null -ne $Saved -and $null -eq $Parameter['DataConnection'] -and $Target.Count -eq 1 -and $Target[0].Text -eq $Sql.Trim()) {
        $DirectId = $Saved.Id
    }
    [pscustomobject]@{ Target = $Target; DirectId = $DirectId }
}

function Get-OmadaSqlSavedQuery {
    <#
    .SYNOPSIS
    The saved query object for the Id and Name parameter sets, or $null for ad-hoc SQL.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Context,

        [Parameter(Mandatory = $true)]
        [string]$ParameterSetName,

        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Parameter
    )

    $Raw = switch ($ParameterSetName) {
        'Id' { Get-OmadaSqlQueryData -Context $Context -Id $Parameter['Id'] }
        'Name' { @(Get-OmadaSqlQueryData -Context $Context -ExactName $Parameter['Name']) | Select-Object -First 1 }
        default { return $null }
    }
    if ($null -eq $Raw) {
        throw (New-OmadaSqlErrorRecord -Kind 'NotFound' -Message ("No SQL Troubleshooting object named '{0}' was found." -f $Parameter['Name']) -TargetObject $Parameter['Name'])
    }
    return ($Raw | ConvertTo-OmadaSqlQueryObject -BaseUrl $Context.Connection.BaseUrl)
}

function Get-OmadaSqlRunText {
    <#
    .SYNOPSIS
    The T-SQL text of a run: the saved object's query, -Query, or the -Path file read as UTF-8.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ParameterSetName,

        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Parameter,

        [AllowNull()]
        [pscustomobject]$Saved
    )

    $Text = switch ($ParameterSetName) {
        'Query' { [string]$Parameter['Query'] }
        'Path' { Get-Content -LiteralPath $Parameter['Path'] -Raw -Encoding UTF8 -ErrorAction Stop }
        default { $Saved.Query }
    }
    if ([string]::IsNullOrWhiteSpace($Text)) {
        throw (New-OmadaSqlErrorRecord -Kind 'InvalidArgument' -Message 'The query is empty.')
    }
    return $Text
}

function Invoke-OmadaSqlSavedStatement {
    <#
    .SYNOPSIS
    Executes a saved object as it is and returns its result, without writing the object.
    #>
    [CmdletBinding()]
    [OutputType('OmadaSql.StatementResult')]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Context,

        [Parameter(Mandatory = $true)]
        [long]$Id,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$Target
    )

    $Started = [System.Diagnostics.Stopwatch]::StartNew()
    $Rows = @()
    $ErrorRecord = $null
    try {
        $Rows = Invoke-OmadaSqlProducer -Context $Context -Id $Id
    }
    catch {
        $ErrorRecord = $_
    }
    New-OmadaSqlStatementResult -Target $Target -Rows $Rows -ErrorRecord $ErrorRecord -Elapsed $Started.Elapsed
}
