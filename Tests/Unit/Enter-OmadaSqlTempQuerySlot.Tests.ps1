param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaSql.PS\OmadaSql.PS.psm1')
)

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers\OmadaSqlTestHelper.ps1')
    Import-OmadaWebStub
    Get-Module -Name OmadaSql.PS -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Temporary query slot names' -Tag 'Unit' {
    It 'Names the object TMP_<id>_<slot> and the mutex in the Global namespace' {
        InModuleScope 'OmadaSql.PS' {
            Get-OmadaSqlTempQueryName -InstanceGuid 'abc' -Slot 3 | Should -BeExactly 'TMP_abc_3'
            Get-OmadaSqlTempQueryMutexName -InstanceGuid 'abc' -Slot 3 | Should -BeExactly 'Global\OmadaSql.PS.TempQuery.abc.3'
        }
    }
}

Describe 'Enter-OmadaSqlTempQuerySlot' -Tag 'Unit' {
    BeforeAll {
        # Holds one slot's mutex on another thread, as a second PowerShell session would.
        function Start-SlotHolder {
            param([string]$MutexName)
            $Held = [System.Threading.ManualResetEvent]::new($false)
            $Release = [System.Threading.ManualResetEvent]::new($false)
            $Shell = [powershell]::Create()
            $null = $Shell.AddScript({
                    param($Name, $Held, $Release)
                    $Mutex = [System.Threading.Mutex]::new($false, $Name)
                    $null = $Mutex.WaitOne()
                    $null = $Held.Set()
                    $null = $Release.WaitOne(30000)
                    $Mutex.ReleaseMutex()
                    $Mutex.Dispose()
                }).AddArgument($MutexName).AddArgument($Held).AddArgument($Release)
            $Handle = $Shell.BeginInvoke()
            $null = $Held.WaitOne(10000)
            [pscustomobject]@{ Shell = $Shell; Handle = $Handle; Release = $Release }
        }
        function Stop-SlotHolder {
            param($Holder)
            $null = $Holder.Release.Set()
            $null = $Holder.Shell.EndInvoke($Holder.Handle)
            $Holder.Shell.Dispose()
        }
    }

    BeforeEach {
        $Script:Guid = Set-OmadaSqlTestSetting -Folder $TestDrive -MaxTempQuerySlots 2
    }

    It 'Leases the first free slot and releases it' {
        InModuleScope 'OmadaSql.PS' -Parameters @{ Guid = $Script:Guid } {
            param($Guid)
            $Slot = Enter-OmadaSqlTempQuerySlot -TimeoutSeconds 1
            $Slot.Slot | Should -Be 1
            $Slot.Name | Should -BeExactly ('TMP_{0}_1' -f $Guid)
            $Slot.PSObject.TypeNames | Should -Contain 'OmadaSql.TempQuerySlot'
            Exit-OmadaSqlTempQuerySlot -Slot $Slot
        }
    }

    It 'Takes the next slot while another session holds the first, and reports the held one as leased' {
        $Holder = Start-SlotHolder -MutexName ('Global\OmadaSql.PS.TempQuery.{0}.1' -f $Script:Guid)
        try {
            InModuleScope 'OmadaSql.PS' -Parameters @{ Guid = $Script:Guid } {
                param($Guid)
                Test-OmadaSqlTempQuerySlotLeased -InstanceGuid $Guid -Slot 1 | Should -BeTrue
                Test-OmadaSqlTempQuerySlotLeased -InstanceGuid $Guid -Slot 2 | Should -BeFalse
                $Slot = Enter-OmadaSqlTempQuerySlot -TimeoutSeconds 1
                $Slot.Slot | Should -Be 2
                Exit-OmadaSqlTempQuerySlot -Slot $Slot
            }
        }
        finally {
            Stop-SlotHolder -Holder $Holder
        }
    }

    It 'Fails with Busy when every slot stays in use' {
        $Holder1 = Start-SlotHolder -MutexName ('Global\OmadaSql.PS.TempQuery.{0}.1' -f $Script:Guid)
        $Holder2 = Start-SlotHolder -MutexName ('Global\OmadaSql.PS.TempQuery.{0}.2' -f $Script:Guid)
        try {
            InModuleScope 'OmadaSql.PS' {
                $Caught = $null
                try { $null = Enter-OmadaSqlTempQuerySlot -TimeoutSeconds 0 } catch { $Caught = $_ }
                $Caught.FullyQualifiedErrorId | Should -Be 'OmadaSql.Busy'
                $Caught.Exception.Message | Should -BeLike 'All 2 temporary query slots*0 seconds*'
            }
        }
        finally {
            Stop-SlotHolder -Holder $Holder1
            Stop-SlotHolder -Holder $Holder2
        }
    }
}

Describe 'Wait-OmadaSqlMutex' -Tag 'Unit' {
    It 'Returns the index of the acquired mutex' {
        InModuleScope 'OmadaSql.PS' {
            $Mutex = [System.Threading.Mutex]::new($false)
            try {
                Wait-OmadaSqlMutex -Mutex @($Mutex) -TimeoutMilliseconds 0 | Should -Be 0
                $Mutex.ReleaseMutex()
            }
            finally {
                $Mutex.Dispose()
            }
        }
    }
}

Describe 'Enter-OmadaSqlTempQuerySlot parameter contract' -Tag 'Unit' {
    # Parameter declarations run no code a test could observe, so the mutation gate's mutants of
    # Mandatory, Position, pipeline binding and ValidateRange are caught only by asserting the contract.
    It '<Command> -<Parameter> <ParameterSet>' -ForEach @(
        @{ Command = 'Enter-OmadaSqlTempQuerySlot'; Parameter = 'TimeoutSeconds'; ParameterSet = ''; Mandatory = $false; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = '0'; RangeMax = '86400' }
        @{ Command = 'Wait-OmadaSqlMutex'; Parameter = 'Mutex'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Wait-OmadaSqlMutex'; Parameter = 'TimeoutMilliseconds'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Exit-OmadaSqlTempQuerySlot'; Parameter = 'Slot'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Get-OmadaSqlTempQueryName'; Parameter = 'InstanceGuid'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Get-OmadaSqlTempQueryName'; Parameter = 'Slot'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Get-OmadaSqlTempQueryMutexName'; Parameter = 'InstanceGuid'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Get-OmadaSqlTempQueryMutexName'; Parameter = 'Slot'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Test-OmadaSqlTempQuerySlotLeased'; Parameter = 'InstanceGuid'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Test-OmadaSqlTempQuerySlotLeased'; Parameter = 'Slot'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
    ) {
        $Contract = Get-OmadaSqlParameterContract -CommandName $Command -ParameterName $Parameter -ParameterSetName $ParameterSet
        $Contract.Mandatory | Should -Be $Mandatory
        if ($null -ne $Position) {
            $Contract.Position | Should -Be $Position
        }
        $Contract.ValueFromPipeline | Should -Be $ValueFromPipeline
        $Contract.ValueFromPipelineByPropertyName | Should -Be $ValueFromPipelineByPropertyName
        $Contract.RangeMin | Should -Be $RangeMin
        $Contract.RangeMax | Should -Be $RangeMax
    }
}
