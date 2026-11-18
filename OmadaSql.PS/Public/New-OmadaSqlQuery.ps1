function New-OmadaSqlQuery {
    <#
    .SYNOPSIS
    Creates a SQL Troubleshooting object in Omada.

    .DESCRIPTION
    Creates a C_P_SQLTROUBLESHOOTING object over OData with a name, the SQL text and the data
    connection it runs against, and returns it. A name that a live object already has is refused,
    as the SQL Troubleshooter does: the name is how people find a query.

    The SQL text is stored as given; it is not validated or run.

    .PARAMETER Name
    The name of the new object.

    .PARAMETER Query
    The SQL text.

    .PARAMETER DataConnection
    The data connection, by name (as Get-OmadaSqlDataConnection shows it) or by id.

    .PARAMETER Connection
    The connection to use, as returned by Connect-OmadaSql -PassThru. Defaults to the current one.

    .EXAMPLE
    New-OmadaSqlQuery -Name 'Identities per status' -Query 'SELECT [Status] = s.Name, [Count] = COUNT(*) FROM ...' -DataConnection 'OISES'

    Creates a query against the OISES data connection.

    .EXAMPLE
    New-OmadaSqlQuery -Name 'Daily export' -Query (Get-Content -Raw .\DailyExport.sql) -DataConnection 1001 -WhatIf

    Shows what would be created, without creating it.

    .EXAMPLE
    Get-OmadaSqlQuery -Name 'Daily export' -Connection $Test | ForEach-Object { New-OmadaSqlQuery -Name $_.Name -Query $_.Query -DataConnection $_.DataConnectionName -Connection $Production }

    Copies a query from a test tenant to a production tenant.

    .LINK
    Set-OmadaSqlQuery

    .LINK
    https://github.com/Fortigi/OmadaSql.PS
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType('OmadaSql.Query')]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory = $true, Position = 1)]
        [ValidateNotNullOrEmpty()]
        [string]$Query,

        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [object]$DataConnection,

        [object]$Connection
    )

    try {
        $Context = Get-OmadaSqlConnectionContext -Connection $Connection
        $Resolved = Resolve-OmadaSqlDataConnection -Context $Context -DataConnection $DataConnection
        Assert-OmadaSqlQueryNameAvailable -Context $Context -Name $Name

        if (-not $PSCmdlet.ShouldProcess(("'{0}' on {1}" -f $Name, $Context.Connection.BaseUrl), 'Create SQL Troubleshooting object')) {
            return
        }

        $Body = [ordered]@{
            NAME                                = $Name
            C_QUERY                             = $Query
            C_SQLTROUBLESHOOTING_DATACONNECTION = @{ Id = $Resolved.Id }
        }
        $Created = Invoke-OmadaSqlRequest -Context $Context -Method POST -Path $Script:OmadaSqlEntityPath -Body $Body
        $CreatedId = Get-OmadaSqlPropertyValue -InputObject $Created -Name 'Id'
        if ($null -eq $CreatedId) {
            throw (New-OmadaSqlErrorRecord -Kind 'InvalidResult' -Message ("Omada created '{0}' but returned no id." -f $Name))
        }
        Write-OmadaSqlLog -Message ("Created SQL Troubleshooting object {0}." -f $CreatedId)
        Get-OmadaSqlQueryData -Context $Context -Id ([long]$CreatedId) | ConvertTo-OmadaSqlQueryObject -BaseUrl $Context.Connection.BaseUrl
    }
    catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}
