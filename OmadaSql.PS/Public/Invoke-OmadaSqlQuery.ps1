function Invoke-OmadaSqlQuery {
    <#
    .SYNOPSIS
    Runs a SQL query on an Omada Identity Cloud tenant through SQL Troubleshooting.

    .DESCRIPTION
    Runs a saved SQL Troubleshooting object (-Id, -Name or from the pipeline) or ad-hoc T-SQL (-Query or
    -Path) and returns the result rows as objects, one property per column.

    The query is validated first (see Test-OmadaSqlQuery): a blocking finding stops it with an
    OmadaSql.ValidationFailed error before anything is sent. -SkipValidation sends it unchecked.

    A script runs statement by statement. A database name is the name of a data connection:
    [OISES].dbo.tblDataObject runs that statement against the data connection OISES, USE [OISES] does
    so for the statements after it, and the prefix and the USE are removed before the text is sent.
    Statements without one run against -DataConnection, or for a saved object its own data connection.

    Ad-hoc SQL runs through a temporary SQL Troubleshooting object named TMP_<profile id>_<n>, from a
    small pool of this user profile (see Get-OmadaSqlTempQuery). It is soft-deleted after the run and
    reused by the next one. Running ad-hoc SQL therefore also needs Create, Update and Delete on the
    SQL Troubleshooting OData object. A saved object is never changed: a single statement without a
    database name runs as it is; anything else runs its text through a temporary object.

    A statement that fails is reported as a non-terminating error and the next statement still runs;
    use -ErrorAction Stop to stop at the first. Omada returns at most 100 000 rows per statement; a
    larger result is an error rather than a truncated one.

    .PARAMETER Id
    The data object id of a saved SQL Troubleshooting object. Accepts pipeline input by property name,
    so the output of Get-OmadaSqlQuery can be piped in.

    .PARAMETER Name
    The exact name of a saved SQL Troubleshooting object.

    .PARAMETER Query
    The T-SQL text to run. Accepts pipeline input: a piped string is SQL text, a piped object with a
    numeric Id runs that saved object, and any other piped object is refused.

    .PARAMETER Path
    A file holding the T-SQL text to run, read as UTF-8.

    .PARAMETER DataConnection
    The data connection for statements that name none, by name or id (see Get-OmadaSqlDataConnection).
    For a saved object it replaces the object's own data connection for this run only.

    .PARAMETER RuleSeverity
    Overrides the severity of query rules, for example @{ OMD001 = 'Off' }. See Test-OmadaSqlQuery.

    .PARAMETER SkipValidation
    Send the query without checking it. Database names are still resolved when the query parses.

    .PARAMETER AsStatementResult
    Return one OmadaSql.StatementResult per statement (Ordinal, Line, Text, DataConnection, RowCount,
    Rows, Succeeded, Error, Elapsed) instead of the rows.

    .PARAMETER Connection
    The connection to use, as returned by Connect-OmadaSql -PassThru. Defaults to the current one.

    .EXAMPLE
    Invoke-OmadaSqlQuery -Query 'SELECT TOP 10 [Id] = Id, [Name] = DisplayName FROM dbo.tblDataObject' -DataConnection 'OISES'

    Runs ad-hoc SQL against the OISES data connection.

    .EXAMPLE
    Get-OmadaSqlQuery -Name 'Daily export' | Invoke-OmadaSqlQuery | Export-Csv -Path .\daily.csv -NoTypeInformation -Encoding UTF8

    Runs a saved query and writes its rows to a CSV file.

    .EXAMPLE
    Invoke-OmadaSqlQuery -Path .\Report.sql -AsStatementResult | Format-Table Ordinal, DataConnection, RowCount, Succeeded, Elapsed

    Runs a script whose statements name their own data connections and shows how each statement went.

    .LINK
    Test-OmadaSqlQuery

    .LINK
    https://github.com/Fortigi/OmadaSql.PS
    #>
    [CmdletBinding(DefaultParameterSetName = 'Query')]
    [OutputType('System.Management.Automation.PSCustomObject', 'OmadaSql.StatementResult')]
    param(
        [Parameter(ParameterSetName = 'Id', Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateRange(1, [long]::MaxValue)]
        [long]$Id,

        [Parameter(ParameterSetName = 'Name', Mandatory = $true)]
        [string]$Name,

        [Parameter(ParameterSetName = 'Query', Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [string]$Query,

        [Parameter(ParameterSetName = 'Path', Mandatory = $true)]
        [string]$Path,

        [object]$DataConnection,

        [hashtable]$RuleSeverity,

        [switch]$SkipValidation,

        [switch]$AsStatementResult,

        [object]$Connection
    )

    begin {
        try {
            $Context = Get-OmadaSqlConnectionContext -Connection $Connection
        }
        catch {
            $PSCmdlet.ThrowTerminatingError($_)
        }
    }

    process {
        try {
            $QueryInput = Resolve-OmadaSqlQueryInput -ParameterSetName $PSCmdlet.ParameterSetName -Parameter $PSBoundParameters -InputObject $_ -ExpectingInput:$MyInvocation.ExpectingInput
            $Run = Get-OmadaSqlQueryRun -Context $Context -ParameterSetName $QueryInput.ParameterSetName -Parameter $QueryInput.Parameter
            $Result = if ($Run.DirectId -gt 0) {
                Invoke-OmadaSqlSavedStatement -Context $Context -Id $Run.DirectId -Target $Run.Target[0]
            }
            else {
                Invoke-OmadaSqlStatementList -Context $Context -Target $Run.Target
            }
        }
        catch {
            $PSCmdlet.ThrowTerminatingError($_)
        }
        foreach ($Item in @($Result)) {
            if ($null -ne $Item.Error) {
                $PSCmdlet.WriteError((New-OmadaSqlErrorRecord -Kind ($Item.Error.FullyQualifiedErrorId -replace '^OmadaSql\.|,.*$', '') -Message ("Statement {0} (line {1}) failed: {2}" -f $Item.Ordinal, $Item.Line, $Item.Error.Exception.Message) -InnerException $Item.Error.Exception -TargetObject $Item.Text))
            }
            if ($AsStatementResult) {
                $Item
            }
            else {
                $Item.Rows
            }
        }
    }
}
