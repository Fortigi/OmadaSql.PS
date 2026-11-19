function Get-OmadaSqlConnection {
    <#
    .SYNOPSIS
    Returns the current connection, or every connection.

    .DESCRIPTION
    Returns the connection objects made by Connect-OmadaSql: the tenant base URL, the
    authentication type, the client id when there is one, and whether the connection was verified.
    Secrets are never part of these objects. Returns nothing when there is no connection.

    .PARAMETER All
    Return every connection instead of only the current one.

    .EXAMPLE
    Get-OmadaSqlConnection

    Shows the connection commands use when no -Connection is passed.

    .EXAMPLE
    Get-OmadaSqlConnection -All | Format-Table BaseUrl, AuthenticationType, Verified

    Lists every connection in this session.

    .EXAMPLE
    if (-not (Get-OmadaSqlConnection)) { Connect-OmadaSql -Url 'https://tenant.omada.cloud' }

    Connects only when there is no current connection yet.

    .LINK
    Connect-OmadaSql

    .LINK
    https://github.com/Fortigi/OmadaSql.PS
    #>
    [CmdletBinding()]
    [OutputType('OmadaSql.Connection')]
    param(
        [switch]$All
    )

    if ($All) {
        foreach ($Context in @($Script:OmadaSqlConnectionStore.Values | Sort-Object -Property { $_.Sequence })) {
            $Context.Connection
        }
        return
    }

    if (-not [string]::IsNullOrWhiteSpace($Script:OmadaSqlCurrentConnectionId) -and $Script:OmadaSqlConnectionStore.ContainsKey($Script:OmadaSqlCurrentConnectionId)) {
        return $Script:OmadaSqlConnectionStore[$Script:OmadaSqlCurrentConnectionId].Connection
    }
}
