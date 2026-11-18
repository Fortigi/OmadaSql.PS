function Disconnect-OmadaSql {
    <#
    .SYNOPSIS
    Removes a connection made with Connect-OmadaSql.

    .DESCRIPTION
    Forgets the connection and the authentication parameters kept for it, so the module can no
    longer send requests with it. Without -Connection the current connection is removed; with -All
    every connection is.

    The OmadaWeb.PS session itself (a cached browser cookie, for instance) is not touched: it
    belongs to OmadaWeb.PS and can be cleared with Clear-OmadaWebCache.

    .PARAMETER Connection
    The connection to remove, as returned by Connect-OmadaSql -PassThru or Get-OmadaSqlConnection.
    Accepts pipeline input.

    .PARAMETER All
    Remove every connection.

    .EXAMPLE
    Disconnect-OmadaSql

    Removes the current connection.

    .EXAMPLE
    Get-OmadaSqlConnection -All | Disconnect-OmadaSql

    Removes every connection through the pipeline.

    .EXAMPLE
    Disconnect-OmadaSql -Connection $Test

    Removes one specific connection. When it was the current one, no connection is current afterwards.

    .LINK
    Connect-OmadaSql

    .LINK
    https://github.com/Fortigi/OmadaSql.PS
    #>
    [CmdletBinding(DefaultParameterSetName = 'Connection')]
    param(
        [Parameter(ParameterSetName = 'Connection', ValueFromPipeline = $true)]
        [object]$Connection,

        [Parameter(ParameterSetName = 'All', Mandatory = $true)]
        [switch]$All
    )

    process {
        try {
            if ($All) {
                $Count = $Script:OmadaSqlConnectionStore.Count
                $Script:OmadaSqlConnectionStore.Clear()
                $Script:OmadaSqlCurrentConnectionId = $null
                Write-OmadaSqlLog -Message ("Removed {0} connection(s)." -f $Count)
                return
            }

            $Context = Get-OmadaSqlConnectionContext -Connection $Connection
            $Id = $Context.Connection.Id
            $Script:OmadaSqlConnectionStore.Remove($Id)
            if ($Script:OmadaSqlCurrentConnectionId -eq $Id) {
                $Script:OmadaSqlCurrentConnectionId = $null
            }
            Write-OmadaSqlLog -Message ("Removed connection {0} to {1}." -f $Id, $Context.Connection.BaseUrl)
        }
        catch {
            $PSCmdlet.ThrowTerminatingError($_)
        }
    }
}
