function Get-OmadaSqlSchemaModel {
    <#
    .SYNOPSIS
    The schema of one data connection as a lookup model, read once per connection and cached.

    .DESCRIPTION
    The model is kept on the connection (Context.SchemaCache, keyed by data connection id) for as long
    as the connection exists, so Disconnect-OmadaSql drops it. -Force reads it again.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Context,

        [Parameter(Mandatory = $true)]
        [object]$DataConnection,

        [switch]$Force
    )

    $Resolved = Resolve-OmadaSqlDataConnection -Context $Context -DataConnection $DataConnection
    if (-not $Context.ContainsKey('SchemaCache')) {
        $Context.SchemaCache = @{}
    }
    $Key = [string]$Resolved.Id
    if ($Force -or -not $Context.SchemaCache.ContainsKey($Key)) {
        $Data = Get-OmadaSqlSchemaData -Context $Context -DataConnectionId ([long]$Resolved.Id)
        $Context.SchemaCache[$Key] = ConvertTo-OmadaSqlSchemaModel -Data $Data -DataConnection $Resolved
        Write-OmadaSqlLog -Message ("Read the schema of data connection {0}: {1} table(s) and view(s)." -f $Resolved.Name, $Context.SchemaCache[$Key].Table.Count)
    }
    return $Context.SchemaCache[$Key]
}

function Get-OmadaSqlSchemaData {
    <#
    .SYNOPSIS
    Reads the schema of a data connection (SyntaxHighlighting.asmx/GetSqlSchema) and returns its d object.

    .DESCRIPTION
    The same request the SQL Troubleshooting editor makes: POST with { connectionId }, the id sent as
    a string. The answer maps "schema.table" to a list of "ColumnName DataType" entries; views are in
    the same map.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Context,

        [Parameter(Mandatory = $true)]
        [long]$DataConnectionId
    )

    $Response = Invoke-OmadaSqlRequest -Context $Context -Method POST -Path 'webservice/SyntaxHighlighting.asmx/GetSqlSchema' -Body @{ connectionId = [string]$DataConnectionId }
    $Data = Get-OmadaSqlPropertyValue -InputObject $Response -Name 'd'
    if ($null -eq $Data) {
        throw (New-OmadaSqlErrorRecord -Kind 'InvalidResult' -Message ("Omada returned no schema for data connection {0}." -f $DataConnectionId))
    }
    return $Data
}

function ConvertTo-OmadaSqlSchemaModel {
    <#
    .SYNOPSIS
    Turns the GetSqlSchema answer into tables with columns and the lookups the schema rules use.

    .DESCRIPTION
    A key is split on its first dot into schema and table; a key without one has no schema and is
    skipped, as are blank column entries. A column entry is split on its first run of white space into
    name and type. Lookups are PowerShell hashtables, so they ignore case, as SQL Server does by
    default.

    Returns @{ DataConnection; Table = @{ 'schema.table' = OmadaSql.SchemaTable }; Column =
    @{ 'schema.table' = @{ column = type } }; ByName = @{ table = OmadaSql.SchemaTable[] } }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Data,

        [Parameter(Mandatory = $true)]
        [object]$DataConnection
    )

    $Model = @{ DataConnection = $DataConnection; Table = @{}; Column = @{}; ByName = @{} }
    foreach ($Entry in @(Get-OmadaSqlSchemaEntry -Data $Data)) {
        $Part = $Entry.Name.Split([char[]]'.', 2)
        if ($Part.Count -lt 2 -or $Part[0] -eq '' -or $Part[1] -eq '') {
            continue
        }
        $Table = New-OmadaSqlSchemaTable -Schema $Part[0] -Table $Part[1] -ColumnEntry $Entry.Value -DataConnectionName $DataConnection.Name
        $Model.Table[$Table.Name] = $Table
        $Model.Column[$Table.Name] = @{}
        foreach ($Column in $Table.Column) {
            $Model.Column[$Table.Name][$Column.Name] = $Column.Type
        }
        if (-not $Model.ByName.ContainsKey($Table.Table)) {
            $Model.ByName[$Table.Table] = [System.Collections.Generic.List[object]]::new()
        }
        $Model.ByName[$Table.Table].Add($Table)
    }
    return $Model
}

function Get-OmadaSqlSchemaEntry {
    <#
    .SYNOPSIS
    The name and value of every entry of the GetSqlSchema d object, whether it is a dictionary or an object.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Data
    )

    if ($Data -is [System.Collections.IDictionary]) {
        foreach ($Key in @($Data.Keys)) {
            [pscustomobject]@{ Name = [string]$Key; Value = $Data[$Key] }
        }
        return
    }
    foreach ($Property in @($Data.PSObject.Properties | Where-Object { $_.MemberType -eq 'NoteProperty' })) {
        [pscustomobject]@{ Name = $Property.Name; Value = $Property.Value }
    }
}

function New-OmadaSqlSchemaTable {
    <#
    .SYNOPSIS
    One OmadaSql.SchemaTable with its OmadaSql.SchemaColumn list, in the order Omada returned them.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds an object in memory and changes no state.')]
    [CmdletBinding()]
    [OutputType('OmadaSql.SchemaTable')]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Schema,

        [Parameter(Mandatory = $true)]
        [string]$Table,

        [AllowNull()]
        [object]$ColumnEntry,

        [Parameter(Mandatory = $true)]
        [string]$DataConnectionName
    )

    $Column = foreach ($Item in @($ColumnEntry)) {
        $Text = ([string]$Item).Trim()
        if ($Text -eq '') {
            continue
        }
        $Split = [regex]::Split($Text, '\s+', 2)
        [pscustomobject]@{
            PSTypeName = 'OmadaSql.SchemaColumn'
            Name       = $Split[0]
            Type       = $(if ($Split.Count -gt 1) { $Split[1].Trim() } else { '' })
        }
    }
    [pscustomobject]@{
        PSTypeName     = 'OmadaSql.SchemaTable'
        DataConnection = $DataConnectionName
        Schema         = $Schema
        Table          = $Table
        Name           = '{0}.{1}' -f $Schema, $Table
        Column         = @($Column)
    }
}
