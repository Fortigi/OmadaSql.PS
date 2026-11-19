function Get-OmadaSqlQuery {
    <#
    .SYNOPSIS
    Gets SQL Troubleshooting objects from Omada.

    .DESCRIPTION
    Reads SQL Troubleshooting objects (C_P_SQLTROUBLESHOOTING) over OData: all of them, the ones
    whose name matches, or one by id. Every page of the OData list is read.

    Each result is an OmadaSql.Query object with Id, Name, Query (the SQL text), DataConnectionId and
    DataConnectionName, and the OData object as Omada returned it under Properties. Results can be
    piped to Set-OmadaSqlQuery, Remove-OmadaSqlQuery and Get-OmadaSqlQueryHistory.

    With -Detailed each object also carries its full change history, who created and last changed
    it and when (derived from that history), the owners when the object has explicit owners, and
    the name of its data connection.

    .PARAMETER Id
    The data object id of the SQL Troubleshooting object. Accepts pipeline input by property name.

    .PARAMETER Name
    Return only the objects whose name matches, wildcards allowed. Without wildcards the name is
    matched exactly by Omada; with wildcards every object is read and filtered locally.

    .PARAMETER IncludeDeleted
    Also return soft-deleted objects. Their Deleted property is $true.

    .PARAMETER Detailed
    Add the history, the creator and last editor, the owners and the data connection name. Costs one
    extra request per object, plus one for the data connection list.

    .PARAMETER Connection
    The connection to use, as returned by Connect-OmadaSql -PassThru. Defaults to the current one.

    .EXAMPLE
    Get-OmadaSqlQuery

    Lists every SQL Troubleshooting object that is not deleted.

    .EXAMPLE
    Get-OmadaSqlQuery -Name 'Daily*' | Format-Table Id, Name, DataConnectionName

    Lists the objects whose name starts with Daily.

    .EXAMPLE
    Get-OmadaSqlQuery -Id 1234567 -Detailed

    Shows one object with its history, creator, last editor and owners.

    .LINK
    Get-OmadaSqlQueryHistory

    .LINK
    https://github.com/Fortigi/OmadaSql.PS
    #>
    [CmdletBinding(DefaultParameterSetName = 'Name')]
    [OutputType('OmadaSql.Query')]
    param(
        [Parameter(ParameterSetName = 'Id', Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateRange(1, [long]::MaxValue)]
        [long]$Id,

        [Parameter(ParameterSetName = 'Name', Position = 0)]
        [SupportsWildcards()]
        [string]$Name = '*',

        [switch]$IncludeDeleted,

        [switch]$Detailed,

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
            $Raw = Get-OmadaSqlQueryData -Context $Context -Id $(if ($PSCmdlet.ParameterSetName -eq 'Id') { $Id } else { 0 }) -Name $Name -IncludeDeleted:$IncludeDeleted
            foreach ($Query in @($Raw | ConvertTo-OmadaSqlQueryObject -BaseUrl $Context.Connection.BaseUrl)) {
                if ($Detailed) {
                    Add-OmadaSqlQueryDetail -Context $Context -Query $Query
                }
                else {
                    $Query
                }
            }
        }
        catch {
            $PSCmdlet.ThrowTerminatingError($_)
        }
    }
}
