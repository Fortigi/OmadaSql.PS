function Get-OmadaSqlDataConnection {
    <#
    .SYNOPSIS
    Lists the data connections SQL Troubleshooting queries can run against.

    .DESCRIPTION
    Reads the data connections the same way the Omada web UI and OmadaSqlTroubleshooter do: the
    'SQL Troubleshooting' view gives a SQL Troubleshooting object, and that object's edit page lists
    every data connection as an option. The list is cached per connection for the session; -Force
    reads it again.

    The view must contain at least one SQL Troubleshooting object, because the list is read from an
    object's edit page. On a tenant without any, create one in the Omada UI first.

    .PARAMETER Name
    Return only the data connections whose name matches, wildcards allowed.

    .PARAMETER Force
    Read the list from the tenant again instead of from the session cache.

    .PARAMETER Connection
    The connection to use, as returned by Connect-OmadaSql -PassThru. Defaults to the current one.

    .EXAMPLE
    Get-OmadaSqlDataConnection

    Lists every data connection with its name and id.

    .EXAMPLE
    Get-OmadaSqlDataConnection -Name 'OIS*'

    Lists the data connections whose name starts with OIS.

    .EXAMPLE
    Get-OmadaSqlDataConnection -Force -Connection $Test

    Reads the list again from the tenant of another connection.

    .LINK
    Connect-OmadaSql

    .LINK
    https://github.com/Fortigi/OmadaSql.PS
    #>
    [CmdletBinding()]
    [OutputType('OmadaSql.DataConnection')]
    param(
        [Parameter(Position = 0)]
        [SupportsWildcards()]
        [string]$Name = '*',

        [switch]$Force,

        [object]$Connection
    )

    try {
        $Context = Get-OmadaSqlConnectionContext -Connection $Connection
        $Cached = $null
        if ($Context.ContainsKey('DataConnectionCache')) {
            $Cached = $Context.DataConnectionCache
        }
        if ($Force -or $null -eq $Cached) {
            $Cached = @(Get-OmadaSqlDataConnectionList -Context $Context)
            $Context.DataConnectionCache = $Cached
        }
        $Cached | Where-Object { $_.Name -like $Name }
    }
    catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}
