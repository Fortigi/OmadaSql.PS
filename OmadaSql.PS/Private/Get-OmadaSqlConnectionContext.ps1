function Get-OmadaSqlConnectionContext {
    <#
    .SYNOPSIS
    Resolves the connection a command runs against: the one passed in, or the current one.

    .DESCRIPTION
    Returns the store entry (Connection, RequestParameter, ReadSucceeded) for the given connection
    object or id, or for the connection Connect-OmadaSql made current. Throws OmadaSql.NotConnected
    when there is none, or when the given connection was disconnected.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [AllowNull()]
        [object]$Connection
    )

    $Id = $null
    if ($null -ne $Connection) {
        if ($Connection -is [string]) {
            $Id = $Connection
        }
        elseif ($null -ne $Connection.PSObject.Properties['Id']) {
            $Id = [string]$Connection.Id
        }
        else {
            throw (New-OmadaSqlErrorRecord -Kind 'InvalidArgument' -Message 'The value passed to -Connection is not a connection returned by Connect-OmadaSql.' -TargetObject $Connection)
        }
    }
    else {
        $Id = $Script:OmadaSqlCurrentConnectionId
    }

    if ([string]::IsNullOrWhiteSpace($Id) -or -not $Script:OmadaSqlConnectionStore.ContainsKey($Id)) {
        throw (New-OmadaSqlErrorRecord -Kind 'NotConnected' -Message 'Not connected to Omada. Run Connect-OmadaSql first, or pass a connection with -Connection.')
    }

    return $Script:OmadaSqlConnectionStore[$Id]
}
