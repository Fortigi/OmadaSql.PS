function Get-OmadaSqlDataConnectionList {
    <#
    .SYNOPSIS
    Reads the data connections from the tenant: view lookup, view rows, then one object's edit page.

    .DESCRIPTION
    Column 'c-13' of the SQL Troubleshooting view holds the data object id of the query (the column
    mapping OmadaSqlTroubleshooter uses, DataobjdlgAspxAttributeMapping.SqlQueryDoId). It depends on
    the layout of the standard view; a tenant that changed the view may need a different column.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Context
    )

    $Views = Invoke-OmadaSqlPagingRequest -Context $Context -DataType 'Views' -DataTypeArgument @{ OwnerShipType = 'Both' } -SearchString 'SQL Troubleshooting'
    $View = @($Views.Rows | Where-Object { $null -ne $_ -and $_.Name -eq 'SQL Troubleshooting' }) | Select-Object -First 1
    if ($null -eq $View) {
        throw (New-OmadaSqlErrorRecord -Kind 'NotFound' -Message ("The 'SQL Troubleshooting' view was not found on tenant '{0}'." -f $Context.Connection.BaseUrl))
    }

    $DataTypeArgument = [ordered]@{
        viewId          = [string]$View.Id
        pageQueryString = '{0}/dataobjlst.aspx?view={1}' -f $Context.Connection.BaseUrl, $View.Id
        readOnlyMode    = $false
        countRows       = $false
    }
    $Rows = Invoke-OmadaSqlPagingRequest -Context $Context -DataType 'DataObjects' -DataTypeArgument $DataTypeArgument
    $ObjectRows = @($Rows.Rows | Where-Object { $null -ne $_ -and $null -ne $_.PSObject.Properties['c-13'] })
    if ($ObjectRows.Count -eq 0) {
        throw (New-OmadaSqlErrorRecord -Kind 'NotFound' -Message "The 'SQL Troubleshooting' view contains no SQL Troubleshooting object, so the data connections cannot be read. Create one in the Omada UI first.")
    }
    $FirstRow = $ObjectRows[0]

    $Html = Invoke-OmadaSqlRequest -Context $Context -Method GET -Path ('dataobjdlg.aspx?DOID={0}' -f $FirstRow.'c-13')
    $Connections = @(ConvertFrom-OmadaSqlDataConnectionHtml -Html ([string]$Html))
    if ($Connections.Count -eq 0) {
        throw (New-OmadaSqlErrorRecord -Kind 'InvalidResult' -Message 'The SQL Troubleshooting edit page listed no data connections.')
    }
    return $Connections
}

function Resolve-OmadaSqlDataConnection {
    <#
    .SYNOPSIS
    Turns a data connection given by name, id or object into the data connection object.

    .DESCRIPTION
    A number, or a string of digits, is taken as the id; anything else as the name (case-insensitive,
    exact). An unknown value fails with the list of available names, so a typo is visible at once.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Context,

        [Parameter(Mandatory = $true)]
        [object]$DataConnection
    )

    if ($null -ne $DataConnection.PSObject.Properties['Id'] -and $DataConnection -isnot [string]) {
        $DataConnection = $DataConnection.Id
    }

    $Available = @(Get-OmadaSqlDataConnection -Connection $Context.Connection)
    $Text = ([string]$DataConnection).Trim()
    if ($Text -match '^\d+$') {
        $Match = @($Available | Where-Object { $_.Id -eq [long]$Text })
    }
    else {
        $Match = @($Available | Where-Object { $_.Name -eq $Text })
    }

    if ($Match.Count -eq 0) {
        throw (New-OmadaSqlErrorRecord -Kind 'InvalidArgument' -Message ("Data connection '{0}' not found. Available: {1}." -f $Text, (($Available | ForEach-Object { $_.Name } | Sort-Object) -join ', ')) -TargetObject $DataConnection)
    }
    return $Match[0]
}
