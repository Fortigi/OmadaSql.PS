function Set-OmadaSqlTempQueryObject {
    <#
    .SYNOPSIS
    Writes one statement into the temporary query object of a leased slot and returns its id.

    .DESCRIPTION
    The first write of a run looks the object up by name, deleted ones included: a slot's object is
    soft-deleted after every run and restored (UndeleteDataObject) on the next, so a profile never
    leaves more than MaxTempQuerySlots objects behind. A missing object is created. Later writes in
    the same run pass -Id and only update.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Internal step of Invoke-OmadaSqlQuery, which owns the confirmation.')]
    [CmdletBinding()]
    [OutputType([long])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Context,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Text,

        [Parameter(Mandatory = $true)]
        [long]$DataConnectionId,

        [long]$Id = 0
    )

    $Body = [ordered]@{
        NAME                                = $Name
        C_QUERY                             = $Text
        C_SQLTROUBLESHOOTING_DATACONNECTION = @{ Id = $DataConnectionId }
    }
    if ($Id -le 0) {
        $Existing = @(Get-OmadaSqlQueryData -Context $Context -ExactName $Name -IncludeDeleted) | Select-Object -First 1
        if ($null -eq $Existing) {
            $Created = Invoke-OmadaSqlRequest -Context $Context -Method POST -Path $Script:OmadaSqlEntityPath -Body $Body
            return [long](Get-OmadaSqlPropertyValue -InputObject $Created -Name 'Id')
        }
        $Id = [long]$Existing.Id
        if ([bool](Get-OmadaSqlPropertyValue -InputObject $Existing -Name 'Deleted')) {
            $null = Invoke-OmadaSqlRequest -Context $Context -Method POST -Path 'WebService/DataObjectWebService.asmx/UndeleteDataObject' -Body ('{{"id":{0}}}' -f $Id)
        }
    }
    Update-OmadaSqlQueryObject -Context $Context -Id $Id -Body $Body
    return $Id
}

function Remove-OmadaSqlTempQueryObject {
    <#
    .SYNOPSIS
    Soft-deletes a temporary query object after a run. A failure is logged, never thrown: the run's
    result stands, and the next run of the slot restores the object anyway.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Internal clean-up of the module''s own temporary object.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Context,

        [Parameter(Mandatory = $true)]
        [long]$Id
    )

    try {
        $null = Invoke-OmadaSqlRequest -Context $Context -Method DELETE -Path ('{0}({1})' -f $Script:OmadaSqlEntityPath, $Id)
    }
    catch {
        Write-OmadaSqlLog -Message ("Could not delete temporary query object {0}: {1}" -f $Id, $_.Exception.Message)
    }
}
