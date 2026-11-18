function ConvertTo-OmadaSqlQueryObject {
    <#
    .SYNOPSIS
    Turns a C_P_SQLTROUBLESHOOTING OData object into the module's OmadaSql.Query object. Pure.

    .DESCRIPTION
    Names the fields the way a PowerShell user expects (Name, Query, DataConnectionId), keeps the
    tenant base URL so a piped object can be acted on again, and keeps the OData object as it came
    under Properties, so nothing Omada returned is lost. Missing properties become $null rather than
    an error: which properties OData returns depends on the tenant configuration.

    The data connection reference is read as an object (Id, DisplayName or Name) and also accepted
    as a bare id, because both shapes have been observed in the reference implementations.
    #>
    [CmdletBinding()]
    [OutputType('OmadaSql.Query')]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [object]$InputObject,

        [Parameter(Mandatory = $true)]
        [string]$BaseUrl
    )

    process {
        $Reference = Get-OmadaSqlPropertyValue -InputObject $InputObject -Name 'C_SQLTROUBLESHOOTING_DATACONNECTION'
        $ConnectionId = $null
        $ConnectionName = $null
        if ($Reference -is [ValueType] -or $Reference -is [string]) {
            $ConnectionId = $Reference
        }
        elseif ($null -ne $Reference) {
            $ConnectionId = Get-OmadaSqlPropertyValue -InputObject $Reference -Name 'Id'
            $ConnectionName = Get-OmadaSqlPropertyValue -InputObject $Reference -Name 'DisplayName'
            if ($null -eq $ConnectionName) {
                $ConnectionName = Get-OmadaSqlPropertyValue -InputObject $Reference -Name 'Name'
            }
        }

        $Deleted = Get-OmadaSqlPropertyValue -InputObject $InputObject -Name 'Deleted'
        [pscustomobject]@{
            PSTypeName         = 'OmadaSql.Query'
            Id                 = [long](Get-OmadaSqlPropertyValue -InputObject $InputObject -Name 'Id')
            Name               = [string](Get-OmadaSqlPropertyValue -InputObject $InputObject -Name 'NAME')
            DisplayName        = [string](Get-OmadaSqlPropertyValue -InputObject $InputObject -Name 'DisplayName')
            Query              = [string](Get-OmadaSqlPropertyValue -InputObject $InputObject -Name 'C_QUERY')
            DataConnectionId   = $(if ($null -ne $ConnectionId -and "$ConnectionId" -ne '') { [long]$ConnectionId } else { $null })
            DataConnectionName = $(if ($null -ne $ConnectionName) { [string]$ConnectionName } else { $null })
            Deleted            = [bool]$Deleted
            BaseUrl            = $BaseUrl
            Properties         = $InputObject
        }
    }
}

function Get-OmadaSqlPropertyValue {
    <#
    .SYNOPSIS
    A property value, or $null when the object does not have that property. StrictMode-safe.

    .DESCRIPTION
    Returned with the unary comma, so a collection value (a multi-valued reference such as an owner
    list) comes back as the collection and is not unrolled into its first element.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$InputObject,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if ($null -eq $InputObject) {
        return $null
    }
    if ($InputObject -is [System.Collections.IDictionary]) {
        if ($InputObject.Contains($Name)) {
            return , $InputObject[$Name]
        }
        return $null
    }
    $Property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $Property) {
        return $null
    }
    return , $Property.Value
}
