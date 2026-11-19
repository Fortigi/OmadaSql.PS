function Get-OmadaSqlSetting {
    <#
    .SYNOPSIS
    The settings of this user profile: InstanceGuid and MaxTempQuerySlots, created on first use.

    .DESCRIPTION
    Stored in %LOCALAPPDATA%\OmadaSql.PS\settings.json. InstanceGuid names the temporary query objects
    of this profile (TMP_<InstanceGuid>_<n>), so it must stay the same between sessions: a new one
    would leave the old objects behind on the tenant. It is created once and then only read.

    MaxTempQuerySlots caps how many temporary objects this profile can ever leave on a tenant, and how
    many queries it can run at the same time. Default 4, at least 1, at most 32.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $Path = Get-OmadaSqlSettingsPath
    $Stored = $null
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        $Stored = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    $Slots = Get-OmadaSqlPropertyValue -InputObject $Stored -Name 'MaxTempQuerySlots'
    if ($null -eq $Slots) {
        $Slots = 4
    }
    if ([int]$Slots -lt 1 -or [int]$Slots -gt 32) {
        throw (New-OmadaSqlErrorRecord -Kind 'InvalidArgument' -Message ("MaxTempQuerySlots in '{0}' is {1}; it must be between 1 and 32." -f $Path, $Slots) -TargetObject $Path)
    }
    $InstanceGuid = [string](Get-OmadaSqlPropertyValue -InputObject $Stored -Name 'InstanceGuid')
    if ($InstanceGuid -notmatch '^[0-9a-f]{32}$') {
        $InstanceGuid = [guid]::NewGuid().ToString('N')
        Save-OmadaSqlSetting -Path $Path -Setting ([ordered]@{ InstanceGuid = $InstanceGuid; MaxTempQuerySlots = [int]$Slots })
    }
    [pscustomobject]@{
        InstanceGuid      = $InstanceGuid
        MaxTempQuerySlots = [int]$Slots
    }
}

function Get-OmadaSqlSettingsPath {
    <#
    .SYNOPSIS
    The settings file of this user profile.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    if (-not [string]::IsNullOrEmpty($Script:OmadaSqlSettingsPath)) {
        return $Script:OmadaSqlSettingsPath
    }
    return [System.IO.Path]::Combine([System.Environment]::GetFolderPath('LocalApplicationData'), 'OmadaSql.PS', 'settings.json')
}

function Save-OmadaSqlSetting {
    <#
    .SYNOPSIS
    Writes the settings file as UTF-8 without a byte order mark, creating its folder.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Internal: writes the module''s own settings file on first use.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Setting
    )

    $null = New-Item -Path (Split-Path -Path $Path -Parent) -ItemType Directory -Force
    [System.IO.File]::WriteAllText($Path, ($Setting | ConvertTo-Json), [System.Text.UTF8Encoding]::new($false))
}
