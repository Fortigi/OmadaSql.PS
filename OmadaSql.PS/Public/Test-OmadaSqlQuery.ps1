function Test-OmadaSqlQuery {
    <#
    .SYNOPSIS
    Checks a T-SQL query for syntax errors and for what SQL Troubleshooting cannot run.

    .DESCRIPTION
    Without -DataConnection nothing is sent to a tenant and no connection is needed. Parses the query
    with the bundled T-SQL parser (ScriptDom) and applies the query rules. Returns
    one OmadaSql.Diagnostic per finding: RuleId, Severity, Blocking, Line, Column, Message and
    Source. No output means the query is fine.

    Syntax errors are reported with RuleId SQL<number>. The rules:

      OMD001  Warning  Result column has no name (Omada returns no rows)
      OMD003  Info     Alias contains characters Omada replaces with an underscore
      OMD004  Error    Nameless column in a derived table, CTE or SELECT INTO
      OMD010  Error    INSERT, UPDATE, DELETE, MERGE or TRUNCATE TABLE
      OMD011  Error    CREATE, ALTER or DROP
      OMD012  Error    EXEC / EXECUTE / sp_executesql
      OMD013  Error    Temporary table
      OMD020  Error    Four-part (linked server) name
      OMD021  Error    More than one database in one statement

    With -DataConnection the table and column names are also checked against the schema of each
    statement's data connection (see Get-OmadaSqlSchema), read once per session:

      OMD030  Info     Table or view not in the schema
      OMD031  Info     Column not in the schema
      OMD032  Info     Ambiguous column (more than one table of the query has it)

    Schema findings are Info, so they never block: the schema is a cached copy. A query scope that
    reads from a derived table, a function, a CTE or a temporary table is not checked for columns.

    Error and Warning findings are blocking (Blocking = $true): a query with one should not be run.
    Info findings are not. Rules only run when the query has no syntax errors.

    A database name in a query is the name of a data connection: [OISES].dbo.tblDataObject runs
    against the data connection OISES. Without -DataConnection that is resolved when the query runs,
    not here.

    .PARAMETER Query
    The T-SQL text. Accepts pipeline input.

    .PARAMETER Path
    A file holding the T-SQL text, read as UTF-8.

    .PARAMETER RuleSeverity
    Overrides the severity of rules, for example @{ OMD001 = 'Error'; OMD003 = 'Off' }. Values are
    Error, Warning, Info and Off.

    .PARAMETER DataConnection
    Check the table and column names against the schema: of this data connection for statements that
    name none, and of the data connection a statement names itself otherwise. Needs a connection.

    .PARAMETER Connection
    The connection to use with -DataConnection, as returned by Connect-OmadaSql -PassThru. Defaults to
    the current one.

    .PARAMETER Quiet
    Return $true when the query has no blocking finding, $false otherwise, instead of the findings.

    .EXAMPLE
    Test-OmadaSqlQuery -Query 'SELECT COUNT(*) FROM dbo.tblDataObject'

    Reports OMD001: the COUNT(*) column has no name, so Omada would return no rows.

    .EXAMPLE
    Get-ChildItem .\Queries\*.sql | ForEach-Object { Test-OmadaSqlQuery -Path $_.FullName } | Format-Table RuleId, Severity, Line, Message

    Checks every query file in a folder.

    .EXAMPLE
    Test-OmadaSqlQuery -Query 'SELECT [Name] = o.DisplayNam FROM dbo.tblDataObject AS o' -DataConnection 'OISES'

    Also reports OMD031: tblDataObject has no column DisplayNam in the schema of OISES.

    .EXAMPLE
    if (Test-OmadaSqlQuery -Path .\Export.sql -RuleSeverity @{ OMD001 = 'Error' } -Quiet) { 'ok' }

    Treats a nameless column as an error and only reports whether the query would be allowed to run.

    .LINK
    https://github.com/Fortigi/OmadaSql.PS
    #>
    [CmdletBinding(DefaultParameterSetName = 'Query')]
    [OutputType('OmadaSql.Diagnostic', [bool])]
    param(
        [Parameter(ParameterSetName = 'Query', Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [AllowEmptyString()]
        [string]$Query,

        [Parameter(ParameterSetName = 'Path', Mandatory = $true)]
        [string]$Path,

        [hashtable]$RuleSeverity,

        [object]$DataConnection,

        [object]$Connection,

        [switch]$Quiet
    )

    process {
        try {
            if ($PSCmdlet.ParameterSetName -eq 'Path') {
                $Query = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 -ErrorAction Stop
            }
            $Result = Get-OmadaSqlDiagnostic -Sql ([string]$Query) -RuleSeverity $RuleSeverity
            $Diagnostic = @($Result.Diagnostic)
            if ($null -ne $DataConnection) {
                $Context = Get-OmadaSqlConnectionContext -Connection $Connection
                $Schema = @(Get-OmadaSqlSchemaDiagnostic -Context $Context -Statement $Result.Statement -Diagnostic $Diagnostic -DataConnection $DataConnection -RuleSeverity $RuleSeverity)
                $Diagnostic = @($Diagnostic + $Schema | Sort-Object -Property Line, Column, RuleId)
            }
            if ($Quiet) {
                return (@($Diagnostic | Where-Object { $_.Blocking }).Count -eq 0)
            }
            $Diagnostic
        }
        catch {
            $PSCmdlet.ThrowTerminatingError($_)
        }
    }
}
