function Get-OmadaSqlTempQueryAction {
    <#
    .SYNOPSIS
    What clearing does to one object: 'Delete', 'Delete and purge', 'Purge', or $null for nothing. Pure.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Deleted,

        [switch]$Purge
    )

    if ($Purge) {
        if ($Deleted) {
            return 'Purge'
        }
        return 'Delete and purge'
    }
    if ($Deleted) {
        return $null
    }
    return 'Delete'
}

function Invoke-OmadaSqlTempQueryAction {
    <#
    .SYNOPSIS
    Soft-deletes a temporary object and, with -Purge, purges it.

    .DESCRIPTION
    PurgeDataObject only accepts a delete-marked object, so a live one is deleted first. A refused
    purge is reported with the role it needs rather than as a generic permission error.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Clear-OmadaSqlTempQuery owns the confirmation.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Context,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$Item,

        [switch]$Purge
    )

    if (-not $Item.Deleted) {
        $null = Invoke-OmadaSqlRequest -Context $Context -Method DELETE -Path ('{0}({1})' -f $Script:OmadaSqlEntityPath, $Item.Id)
    }
    if (-not $Purge) {
        return
    }
    try {
        $null = Invoke-OmadaSqlRequest -Context $Context -Method POST -Path 'WebService/DataObjectWebService.asmx/PurgeDataObject' -Body ('{{"id":{0}}}' -f $Item.Id)
    }
    catch {
        if ($_.FullyQualifiedErrorId -match '^OmadaSql\.(MissingPermission|AccessDenied)') {
            throw (New-OmadaSqlErrorRecord -Kind 'MissingPermission' -Message ("Purging {0} was refused. Omada only allows purging to the System, Operation or Data Administrator role; the object stays deleted and can be purged by such an administrator." -f $Item.Name) -InnerException $_.Exception -TargetObject $Item.Name)
        }
        throw
    }
}
