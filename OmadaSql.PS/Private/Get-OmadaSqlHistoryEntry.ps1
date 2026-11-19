function Get-OmadaSqlHistoryEntry {
    <#
    .SYNOPSIS
    Reads the history of one data object, newest first, as OmadaSql.HistoryEntry objects.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Context,

        [Parameter(Mandatory = $true)]
        [long]$Id
    )

    $Argument = [ordered]@{
        dataObjectId = $Id
        propertyId   = 0
        userId       = 0
    }
    $Data = Invoke-OmadaSqlPagingRequest -Context $Context -DataType 'DataObjectHistory' -DataTypeArgument $Argument -Rows 100000 -SortField 'when' -SortOrder 'desc'
    $Rows = @()
    if ($null -ne $Data.PSObject.Properties['Rows']) {
        $Rows = @($Data.Rows)
    }
    $Rows | ConvertFrom-OmadaSqlHistoryRow -Id $Id
}
