function Enter-OmadaSqlTempQuerySlot {
    <#
    .SYNOPSIS
    Leases a free temporary query slot of this user profile, waiting for one when all are taken.

    .DESCRIPTION
    Ad-hoc SQL runs through a temporary SQL Troubleshooting object, and two runs writing the same object
    would overwrite each other's SQL. Every slot is therefore leased with a named mutex, held until
    Exit-OmadaSqlTempQuerySlot: a second PowerShell session of the same profile takes the next slot, and
    waits when all MaxTempQuerySlots are in use. The mutex is in the Global namespace so sessions in
    other logon sessions of the same profile see it too; the name carries the profile's InstanceGuid,
    so other profiles never share it.

    A mutex its owner abandoned (the process ended without releasing it) is taken over: the object it
    guarded is only ever written by a lease holder, so nothing is left in flight.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [ValidateRange(0, 86400)]
        [int]$TimeoutSeconds = $Script:OmadaSqlSlotTimeoutSeconds
    )

    $Setting = Get-OmadaSqlSetting
    $Mutex = @(1..$Setting.MaxTempQuerySlots | ForEach-Object { [System.Threading.Mutex]::new($false, (Get-OmadaSqlTempQueryMutexName -InstanceGuid $Setting.InstanceGuid -Slot $_)) })
    $Index = Wait-OmadaSqlMutex -Mutex $Mutex -TimeoutMilliseconds ($TimeoutSeconds * 1000)
    for ($Other = 0; $Other -lt $Mutex.Count; $Other++) {
        if ($Other -ne $Index) {
            $Mutex[$Other].Dispose()
        }
    }
    if ($Index -lt 0) {
        throw (New-OmadaSqlErrorRecord -Kind 'Busy' -Message ("All {0} temporary query slots of this profile stayed in use for {1} seconds. Another session is running queries; try again, or raise MaxTempQuerySlots in '{2}'." -f $Setting.MaxTempQuerySlots, $TimeoutSeconds, (Get-OmadaSqlSettingsPath)))
    }
    Write-OmadaSqlLog -Message ("Leased temporary query slot {0}." -f ($Index + 1))
    [pscustomobject]@{
        PSTypeName = 'OmadaSql.TempQuerySlot'
        Slot       = $Index + 1
        Name       = Get-OmadaSqlTempQueryName -InstanceGuid $Setting.InstanceGuid -Slot ($Index + 1)
        Mutex      = $Mutex[$Index]
    }
}

function Wait-OmadaSqlMutex {
    <#
    .SYNOPSIS
    The index of the first mutex this thread acquired, or -1 after the timeout.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory = $true)]
        [System.Threading.Mutex[]]$Mutex,

        [Parameter(Mandatory = $true)]
        [int]$TimeoutMilliseconds
    )

    try {
        $Index = [System.Threading.WaitHandle]::WaitAny($Mutex, $TimeoutMilliseconds)
    }
    catch [System.Threading.AbandonedMutexException] {
        return $_.Exception.MutexIndex
    }
    if ($Index -eq [System.Threading.WaitHandle]::WaitTimeout) {
        return -1
    }
    return $Index
}

function Exit-OmadaSqlTempQuerySlot {
    <#
    .SYNOPSIS
    Releases a slot leased with Enter-OmadaSqlTempQuerySlot.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Slot
    )

    try {
        $Slot.Mutex.ReleaseMutex()
    }
    finally {
        $Slot.Mutex.Dispose()
    }
    Write-OmadaSqlLog -Message ("Released temporary query slot {0}." -f $Slot.Slot)
}

function Get-OmadaSqlTempQueryName {
    <#
    .SYNOPSIS
    The name of a temporary query object: TMP_<InstanceGuid>_<slot>. Pure.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstanceGuid,

        [Parameter(Mandatory = $true)]
        [int]$Slot
    )

    return ('TMP_{0}_{1}' -f $InstanceGuid, $Slot)
}

function Get-OmadaSqlTempQueryMutexName {
    <#
    .SYNOPSIS
    The name of the mutex that guards one slot. Pure.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstanceGuid,

        [Parameter(Mandatory = $true)]
        [int]$Slot
    )

    return ('Global\OmadaSql.PS.TempQuery.{0}.{1}' -f $InstanceGuid, $Slot)
}

function Test-OmadaSqlTempQuerySlotLeased {
    <#
    .SYNOPSIS
    Whether another session holds a slot's mutex right now.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstanceGuid,

        [Parameter(Mandatory = $true)]
        [int]$Slot
    )

    $Mutex = [System.Threading.Mutex]::new($false, (Get-OmadaSqlTempQueryMutexName -InstanceGuid $InstanceGuid -Slot $Slot))
    try {
        $Acquired = Wait-OmadaSqlMutex -Mutex @($Mutex) -TimeoutMilliseconds 0
        if ($Acquired -eq 0) {
            $Mutex.ReleaseMutex()
            return $false
        }
        return $true
    }
    finally {
        $Mutex.Dispose()
    }
}
