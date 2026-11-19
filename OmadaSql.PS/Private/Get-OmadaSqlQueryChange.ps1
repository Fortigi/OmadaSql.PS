function Get-OmadaSqlQueryChange {
    <#
    .SYNOPSIS
    The OData PUT body for a SQL Troubleshooting object: only the fields that differ. Pure.

    .DESCRIPTION
    -Desired may hold Name, Query and DataConnectionId; a key that is absent is left alone. Names and
    query text are compared exactly (case and whitespace matter to the object and its history); the
    data connection is compared by id. An empty body means nothing has to be sent.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Current,

        [Parameter(Mandatory = $true)]
        [hashtable]$Desired
    )

    $Body = [ordered]@{}
    if ($Desired.ContainsKey('Name') -and -not [string]::Equals([string]$Desired.Name, [string]$Current.Name, [System.StringComparison]::Ordinal)) {
        $Body.NAME = [string]$Desired.Name
    }
    if ($Desired.ContainsKey('Query') -and -not [string]::Equals([string]$Desired.Query, [string]$Current.Query, [System.StringComparison]::Ordinal)) {
        $Body.C_QUERY = [string]$Desired.Query
    }
    if ($Desired.ContainsKey('DataConnectionId') -and [string]$Desired.DataConnectionId -ne [string]$Current.DataConnectionId) {
        $Body.C_SQLTROUBLESHOOTING_DATACONNECTION = @{ Id = [long]$Desired.DataConnectionId }
    }
    return $Body
}

function Update-OmadaSqlQueryObject {
    <#
    .SYNOPSIS
    Sends a change body to a SQL Troubleshooting object, refusing a new name another live object has.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Private: the calling public command (Set-OmadaSqlQuery) asks ShouldProcess.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Context,

        [Parameter(Mandatory = $true)]
        [long]$Id,

        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Body
    )

    if ($Body.Contains('NAME')) {
        Assert-OmadaSqlQueryNameAvailable -Context $Context -Name $Body.NAME -ExceptId $Id
    }
    $null = Invoke-OmadaSqlRequest -Context $Context -Method PUT -Path ('{0}({1})' -f $Script:OmadaSqlEntityPath, $Id) -Body $Body
    Write-OmadaSqlLog -Message ("Changed {0} of SQL Troubleshooting object {1}." -f (@($Body.Keys) -join ', '), $Id)
}
