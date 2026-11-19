function Invoke-OmadaSqlProducer {
    <#
    .SYNOPSIS
    Executes a SQL Troubleshooting object (GetPagingData, SqlDataProducer) and returns its rows.

    .DESCRIPTION
    Omada returns at most one page of 100 000 rows. Whether it serves a second page is not known yet,
    so a result whose record count exceeds the rows returned is an OmadaSql.InvalidResult error rather
    than a silently truncated result.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Context,

        [Parameter(Mandatory = $true)]
        [long]$Id
    )

    $Page = Invoke-OmadaSqlPagingRequest -Context $Context -DataType 'SqlDataProducer' -DataTypeArgument @{ targetId = $Id } -Rows 100000
    $Rows = @(Get-OmadaSqlPropertyValue -InputObject $Page -Name 'Rows' | Where-Object { $null -ne $_ })
    $Records = Get-OmadaSqlPropertyValue -InputObject $Page -Name 'Records'
    if ($null -ne $Records -and [long]$Records -gt $Rows.Count) {
        throw (New-OmadaSqlErrorRecord -Kind 'InvalidResult' -Message ("The query matched {0} rows and Omada returned {1}. Narrow the query; a result larger than one page is not read." -f $Records, $Rows.Count))
    }
    return , $Rows
}
