function Invoke-OmadaSqlPagingRequest {
    <#
    .SYNOPSIS
    Calls Omada's jqGrid web service (GetPagingData) and returns its 'd' payload.

    .DESCRIPTION
    The same request OmadaSqlTroubleshooter builds in New-OmadaPagingRequest: views, the rows of a
    view, the history of a data object and query results all come from this one endpoint, with a
    different dataType. The body is built by New-OmadaSqlPagingRequestBody, which is pure.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Context,

        [Parameter(Mandatory = $true)]
        [string]$DataType,

        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$DataTypeArgument,

        [string]$SearchString,

        [ValidateRange(1, 100000)]
        [int]$Rows = 1000,

        [string]$SortField,

        [ValidateSet('asc', 'desc')]
        [string]$SortOrder = 'asc'
    )

    $Body = New-OmadaSqlPagingRequestBody -DataType $DataType -DataTypeArgument $DataTypeArgument -SearchString $SearchString -Rows $Rows -SortField $SortField -SortOrder $SortOrder
    $Response = Invoke-OmadaSqlRequest -Context $Context -Method POST -Path 'WebService/JQGridPopulationWebService.asmx/GetPagingData' -Body $Body
    if ($null -eq $Response -or $null -eq $Response.PSObject.Properties['d']) {
        throw (New-OmadaSqlErrorRecord -Kind 'InvalidResult' -Message ("GetPagingData ({0}) returned no 'd' payload." -f $DataType))
    }
    return $Response.d
}

function New-OmadaSqlPagingRequestBody {
    <#
    .SYNOPSIS
    The GetPagingData request body. Pure.

    .DESCRIPTION
    Field for field what the Omada web UI sends. A search sorts by name, as the UI does; otherwise
    -SortField decides (the history uses 'when'). 'nd' is the jqGrid cache-busting value: the current
    time in Unix milliseconds, as the UI's jqGrid sends it (new Date().getTime()).
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds an object in memory and changes no state.')]
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DataType,

        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$DataTypeArgument,

        [string]$SearchString,

        [int]$Rows = 1000,

        [string]$SortField,

        [string]$SortOrder = 'asc'
    )

    $HasSearch = -not [string]::IsNullOrWhiteSpace($SearchString)
    $Sort = $null
    if ($HasSearch) {
        $Sort = 'name'
    }
    elseif (-not [string]::IsNullOrWhiteSpace($SortField)) {
        $Sort = $SortField
    }

    return [ordered]@{
        _search      = $false
        nd           = [System.DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
        rows         = $Rows
        page         = 1
        sidx         = $Sort
        sord         = $SortOrder
        searchField  = $null
        searchString = $(if ($HasSearch) { $SearchString } else { $null })
        searchOper   = $null
        filters      = $null
        dataType     = $DataType
        dataTypeArgs = $DataTypeArgument
    }
}
