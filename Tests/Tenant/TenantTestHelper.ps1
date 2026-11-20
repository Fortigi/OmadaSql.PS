<#
    Helpers for the tenant test (see docs/TENANT-TEST.md). Dot-sourced by OmadaSql.TenantTest.ps1.

    Every query here is general on purpose: it reads no Omada table, only constants, VALUES lists and
    the schema of the data connection the test is given, so it runs on any tenant and any data
    connection, and it reads no business data.

    An observation records what a tenant does where the module only assumes it. Observations keep
    shapes (property names and .NET types) and outcomes, never values: the result file can be
    reviewed and shared without exposing tenant data. Error messages are kept, so read the file
    before you share it.
#>

function Get-TenantTestQuery {
    # The general queries the tenant test runs, by purpose.
    $Large = ((0..10) | ForEach-Object { '({0})' -f $_ }) -join ', '
    @{
        Rows     = "SELECT [Id] = v.Id, [Name] = v.Name FROM (VALUES (1, N'One'), (2, N'Two'), (3, N'Three')) AS v (Id, Name)"
        Types    = "SELECT [Int] = CAST(1 AS int), [BigInt] = CAST(2 AS bigint), [Decimal] = CAST(12.50 AS decimal(9, 2)), [Float] = CAST(0.5 AS float), [Bit] = CAST(1 AS bit), [Date] = CAST('2026-01-02' AS date), [DateTime] = CAST('2026-01-02T03:04:05.123' AS datetime2(3)), [Guid] = CAST('0f6a1b3c-1111-4a2b-9c01-a00000000900' AS uniqueidentifier), [Text] = N'x', [Null] = CAST(NULL AS int)"
        Fail     = 'SELECT [x] = 1 / 0'
        Declare  = 'DECLARE @x int = 1'
        Nameless = 'SELECT COUNT(*) FROM (VALUES (1), (2)) AS v (n)'
        Alias    = "SELECT [Display Name] = N'x'"
        Unicode  = "SELECT [Text] = N'{0}'" -f (Get-TenantTestUnicodeText)
        Large    = 'SELECT [n] = 1 FROM (VALUES {0}) AS a (n) CROSS JOIN (VALUES {0}) AS b (n) CROSS JOIN (VALUES {0}) AS c (n) CROSS JOIN (VALUES {0}) AS d (n) CROSS JOIN (VALUES {0}) AS e (n)' -f $Large
        InList   = 'SELECT [n] = COUNT(*) FROM (VALUES (1), (2), (3), (4)) AS v (Id) WHERE v.Id IN {0}'
    }
}

function Get-TenantTestUnicodeText {
    # Text with characters outside ASCII and Latin-1, built from code points so the file encoding cannot change it.
    'Zo{0} {1} {2}{3}' -f [char]0x00EB, [char]0x20AC, [char]0x6D4B, [char]0x8BD5
}

function Get-TenantTestShape {
    # The names and .NET types of an object's properties, without their values.
    param([AllowNull()] $InputObject)
    if ($null -eq $InputObject) {
        return @()
    }
    @($InputObject.PSObject.Properties | ForEach-Object {
            [ordered]@{
                Name = $_.Name
                Type = $(if ($null -eq $_.Value) { 'null' } else { $_.Value.GetType().FullName })
                Of   = $(if ($null -ne $_.Value -and $_.Value -isnot [string] -and $_.Value -isnot [System.ValueType]) { @($_.Value.PSObject.Properties | ForEach-Object { $_.Name }) } else { $null })
            }
        })
}

function Add-TenantTestObservation {
    # Records what the tenant did for a checklist step.
    param(
        [Parameter(Mandatory = $true)] [string]$Step,
        [Parameter(Mandatory = $true)] [System.Collections.IDictionary]$Data
    )
    $global:OmadaSqlTenantObservation.Add([ordered]@{ Step = $Step; Data = $Data })
}

function Get-TenantTestErrorSummary {
    # The parts of an error record worth keeping: the error id and the message.
    param([AllowNull()] $ErrorRecord)
    if ($null -eq $ErrorRecord) {
        return $null
    }
    [ordered]@{ ErrorId = $ErrorRecord.FullyQualifiedErrorId; Message = $ErrorRecord.Exception.Message }
}

function Get-TenantTestSchemaTable {
    # A table of the data connection to aim schema-based queries at: dbo.tblDataObject when the
    # schema has it, else the first table or view with a column, so the test needs no fixed table.
    param([Parameter(Mandatory = $true)] $DataConnection)
    $Tables = @(Get-OmadaSqlSchema -DataConnection $DataConnection | Where-Object { @($_.Column).Count -gt 0 })
    $Preferred = @($Tables | Where-Object { $_.Name -eq 'dbo.tblDataObject' })
    if ($Preferred.Count -gt 0) {
        return $Preferred[0]
    }
    if ($Tables.Count -eq 0) {
        throw "The schema of data connection '$DataConnection' has no table or view with columns."
    }
    return $Tables[0]
}

function Get-TenantTestSlotObject {
    # This profile's temporary object for one slot, or $null.
    param([Parameter(Mandatory = $true)] [int]$Slot)
    @(Get-OmadaSqlTempQuery | Where-Object { $_.Slot -eq $Slot }) | Select-Object -First 1
}

function Start-TenantTestSlotHold {
    # Leases one slot from another thread by holding its mutex, so the next run must take another
    # slot. Stop-TenantTestSlotHold releases it.
    param([Parameter(Mandatory = $true)] [string]$MutexName)
    $Ready = [System.Threading.ManualResetEvent]::new($false)
    $Release = [System.Threading.ManualResetEvent]::new($false)
    $PowerShell = [powershell]::Create()
    $null = $PowerShell.AddScript({
            param($Name, $Ready, $Release)
            $Mutex = [System.Threading.Mutex]::new($false, $Name)
            $null = $Mutex.WaitOne()
            $null = $Ready.Set()
            $null = $Release.WaitOne()
            $Mutex.ReleaseMutex()
            $Mutex.Dispose()
        }).AddArgument($MutexName).AddArgument($Ready).AddArgument($Release)
    $Handle = $PowerShell.BeginInvoke()
    try {
        $Held = $Ready.WaitOne(30000)
    }
    finally {
        $Ready.Dispose()
    }
    $Hold = [pscustomobject]@{ PowerShell = $PowerShell; Handle = $Handle; Release = $Release }
    if (-not $Held) {
        # The thread may still be waiting for the mutex: stop it and free everything before failing.
        Stop-TenantTestSlotHold -Hold $Hold
        throw "Could not hold mutex $MutexName."
    }
    return $Hold
}

function Stop-TenantTestSlotHold {
    # Releases the mutex, waits for the thread to end and disposes the runspace and the event.
    param([Parameter(Mandatory = $true)] $Hold)
    try {
        $null = $Hold.Release.Set()
        if (-not $Hold.Handle.AsyncWaitHandle.WaitOne(30000)) {
            $Hold.PowerShell.Stop()
        }
    }
    finally {
        $Hold.PowerShell.Dispose()
        $Hold.Release.Dispose()
    }
}
