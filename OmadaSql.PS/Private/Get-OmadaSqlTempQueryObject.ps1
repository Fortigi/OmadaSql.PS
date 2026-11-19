function Get-OmadaSqlTempQueryObject {
    <#
    .SYNOPSIS
    The TMP_ objects on the tenant, deleted ones included, described for this profile.
    #>
    [CmdletBinding()]
    [OutputType('OmadaSql.TempQuery')]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Context,

        [switch]$All
    )

    $InstanceGuid = (Get-OmadaSqlSetting).InstanceGuid
    foreach ($Raw in @(Get-OmadaSqlQueryData -Context $Context -Name 'TMP_*' -IncludeDeleted)) {
        $Item = ConvertTo-OmadaSqlTempQuery -Name ([string](Get-OmadaSqlPropertyValue -InputObject $Raw -Name 'NAME')) -InstanceGuid $InstanceGuid
        if (-not $All -and -not $Item.ThisProfile) {
            continue
        }
        $Leased = $null
        if ($Item.ThisProfile -and $null -ne $Item.Slot) {
            $Leased = Test-OmadaSqlTempQuerySlotLeased -InstanceGuid $InstanceGuid -Slot $Item.Slot
        }
        [pscustomobject]@{
            PSTypeName  = 'OmadaSql.TempQuery'
            Id          = [long](Get-OmadaSqlPropertyValue -InputObject $Raw -Name 'Id')
            Name        = $Item.Name
            Deleted     = [bool](Get-OmadaSqlPropertyValue -InputObject $Raw -Name 'Deleted')
            ThisProfile = $Item.ThisProfile
            Slot        = $Item.Slot
            Leased      = $Leased
        }
    }
}

function ConvertTo-OmadaSqlTempQuery {
    <#
    .SYNOPSIS
    Reads the profile id and slot out of a TMP_ name. Pure.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$InstanceGuid
    )

    $Slot = $null
    $ThisProfile = $false
    if ($Name -match '^TMP_(?<Guid>[0-9a-fA-F]{32})(_(?<Slot>\d+))?$') {
        $ThisProfile = ($Matches.Guid -eq $InstanceGuid -and $Matches.ContainsKey('Slot'))
        if ($Matches.ContainsKey('Slot')) {
            $Slot = [int]$Matches.Slot
        }
    }
    [pscustomobject]@{ Name = $Name; ThisProfile = $ThisProfile; Slot = $Slot }
}
