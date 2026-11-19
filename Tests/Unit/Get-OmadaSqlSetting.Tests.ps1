param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaSql.PS\OmadaSql.PS.psm1')
)

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers\OmadaSqlTestHelper.ps1')
    Import-OmadaWebStub
    Get-Module -Name OmadaSql.PS -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Get-OmadaSqlSetting' -Tag 'Unit' {
    BeforeEach {
        $Script:Path = Join-Path $TestDrive ('{0}\settings.json' -f [guid]::NewGuid().ToString('N'))
        InModuleScope 'OmadaSql.PS' -Parameters @{ Path = $Script:Path } { param($Path) $Script:OmadaSqlSettingsPath = $Path }
    }

    It 'Creates the file with a new profile id and 4 slots on first use, and keeps the id' {
        $First = InModuleScope 'OmadaSql.PS' { Get-OmadaSqlSetting }
        $First.InstanceGuid | Should -Match '^[0-9a-f]{32}$'
        $First.MaxTempQuerySlots | Should -Be 4
        $Bytes = [System.IO.File]::ReadAllBytes($Script:Path)
        $Bytes[0] | Should -Not -Be 0xEF
        (InModuleScope 'OmadaSql.PS' { Get-OmadaSqlSetting }).InstanceGuid | Should -Be $First.InstanceGuid
    }

    It 'Reads MaxTempQuerySlots from the file' {
        $null = New-Item -Path (Split-Path $Script:Path) -ItemType Directory -Force
        [System.IO.File]::WriteAllText($Script:Path, '{ "InstanceGuid": "0123456789abcdef0123456789abcdef", "MaxTempQuerySlots": 7 }')
        $Setting = InModuleScope 'OmadaSql.PS' { Get-OmadaSqlSetting }
        $Setting.InstanceGuid | Should -Be '0123456789abcdef0123456789abcdef'
        $Setting.MaxTempQuerySlots | Should -Be 7
    }

    It 'Uses 4 slots when the file names none' {
        $null = New-Item -Path (Split-Path $Script:Path) -ItemType Directory -Force
        [System.IO.File]::WriteAllText($Script:Path, '{ "InstanceGuid": "0123456789abcdef0123456789abcdef" }')
        (InModuleScope 'OmadaSql.PS' { Get-OmadaSqlSetting }).MaxTempQuerySlots | Should -Be 4
    }

    It 'Replaces a profile id that is not 32 hex characters' {
        $null = New-Item -Path (Split-Path $Script:Path) -ItemType Directory -Force
        [System.IO.File]::WriteAllText($Script:Path, '{ "InstanceGuid": "not-a-guid", "MaxTempQuerySlots": 2 }')
        (InModuleScope 'OmadaSql.PS' { Get-OmadaSqlSetting }).InstanceGuid | Should -Match '^[0-9a-f]{32}$'
    }

    It 'Refuses <Slots> slots' -ForEach @(@{ Slots = 0 }, @{ Slots = 33 }) {
        $null = New-Item -Path (Split-Path $Script:Path) -ItemType Directory -Force
        [System.IO.File]::WriteAllText($Script:Path, ('{{ "InstanceGuid": "0123456789abcdef0123456789abcdef", "MaxTempQuerySlots": {0} }}' -f $Slots))
        InModuleScope 'OmadaSql.PS' { { Get-OmadaSqlSetting } | Should -Throw -ErrorId 'OmadaSql.InvalidArgument' }
    }

    It 'Accepts the bounds 1 and 32' -ForEach @(@{ Slots = 1 }, @{ Slots = 32 }) {
        $null = New-Item -Path (Split-Path $Script:Path) -ItemType Directory -Force
        [System.IO.File]::WriteAllText($Script:Path, ('{{ "InstanceGuid": "0123456789abcdef0123456789abcdef", "MaxTempQuerySlots": {0} }}' -f $Slots))
        InModuleScope 'OmadaSql.PS' -Parameters @{ Slots = $Slots } { param($Slots) (Get-OmadaSqlSetting).MaxTempQuerySlots | Should -Be $Slots }
    }
}

Describe 'Get-OmadaSqlSettingsPath' -Tag 'Unit' {
    It 'Defaults to OmadaSql.PS\settings.json under the local application data folder' {
        InModuleScope 'OmadaSql.PS' {
            $Script:OmadaSqlSettingsPath = $null
            Get-OmadaSqlSettingsPath | Should -Be ([System.IO.Path]::Combine([System.Environment]::GetFolderPath('LocalApplicationData'), 'OmadaSql.PS', 'settings.json'))
        }
    }
}

Describe 'Get-OmadaSqlSetting parameter contract' -Tag 'Unit' {
    # Parameter declarations run no code a test could observe, so the mutation gate's mutants of
    # Mandatory, Position, pipeline binding and ValidateRange are caught only by asserting the contract.
    It '<Command> -<Parameter> <ParameterSet>' -ForEach @(
        @{ Command = 'Save-OmadaSqlSetting'; Parameter = 'Path'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Save-OmadaSqlSetting'; Parameter = 'Setting'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
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
