function Get-OmadaSqlSchema {
    <#
    .SYNOPSIS
    Lists the tables and views of a data connection, with their columns and data types.

    .DESCRIPTION
    Reads the schema SQL Troubleshooting offers its editor for the data connection and returns one
    OmadaSql.SchemaTable per table or view: DataConnection, Schema, Table, Name (schema.table) and
    Column, a list of OmadaSql.SchemaColumn (Name, Type).

    The schema is read once per connection and data connection and kept for the session; -Force reads
    it again, for example after the database changed. Test-OmadaSqlQuery -DataConnection uses the
    same cache to check table and column names.

    .PARAMETER DataConnection
    The data connection, by name or id, or an object from Get-OmadaSqlDataConnection (also from the
    pipeline).

    .PARAMETER Name
    Only tables and views whose schema.table name matches this pattern. Wildcards are supported.

    .PARAMETER Force
    Read the schema from the tenant again instead of using the cached copy.

    .PARAMETER Connection
    The connection to use, as returned by Connect-OmadaSql -PassThru. Defaults to the current one.

    .EXAMPLE
    Get-OmadaSqlSchema -DataConnection 'OISES' -Name 'dbo.tblData*'

    Lists the dbo tables whose name starts with tblData, with their columns.

    .EXAMPLE
    (Get-OmadaSqlSchema -DataConnection 'OISES' -Name 'dbo.tblDataObject').Column

    Shows the columns of one table and their data types.

    .EXAMPLE
    Get-OmadaSqlDataConnection | Get-OmadaSqlSchema -Force | Group-Object DataConnection

    Reads the schema of every data connection again and counts the tables per connection.

    .LINK
    Test-OmadaSqlQuery

    .LINK
    https://github.com/Fortigi/OmadaSql.PS
    #>
    [CmdletBinding()]
    [OutputType('OmadaSql.SchemaTable')]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [ValidateNotNull()]
        [object]$DataConnection,

        [SupportsWildcards()]
        [string]$Name = '*',

        [switch]$Force,

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
            $Model = Get-OmadaSqlSchemaModel -Context $Context -DataConnection $DataConnection -Force:$Force
            @($Model.Table.Values) | Where-Object { $_.Name -like $Name } | Sort-Object -Property Name
        }
        catch {
            $PSCmdlet.ThrowTerminatingError($_)
        }
    }
}
