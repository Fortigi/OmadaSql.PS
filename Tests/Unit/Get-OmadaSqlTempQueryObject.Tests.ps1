param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaSql.PS\OmadaSql.PS.psm1')
)

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers\OmadaSqlTestHelper.ps1')
    Import-OmadaWebStub
    Get-Module -Name OmadaSql.PS -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Get-OmadaSqlTempQueryObject' -Tag 'Unit' {
    BeforeAll {
        $Script:Connection = Initialize-OmadaSqlTestConnection
    }

    BeforeEach {
        $Script:Guid = Set-OmadaSqlTestSetting -Folder $TestDrive
        Mock Get-OmadaSqlQueryData -ModuleName 'OmadaSql.PS' {
            New-OmadaSqlTestODataQuery -Id 1 -Name ('TMP_{0}_1' -f $Script:Guid) -Deleted $true
            New-OmadaSqlTestODataQuery -Id 2 -Name ('TMP_{0}_1' -f ('f' * 32))
            New-OmadaSqlTestODataQuery -Id 3 -Name ('TMP_{0}' -f $Script:Guid)
        }
    }

    It 'Lists only this profile''s slot objects, deleted ones included, by default' {
        $Item = @(InModuleScope 'OmadaSql.PS' { Get-OmadaSqlTempQueryObject -Context (Get-OmadaSqlConnectionContext) })
        @($Item.Id) | Should -Be @(1)
        $Item[0].Deleted | Should -BeTrue
        $Item[0].ThisProfile | Should -BeTrue
        $Item[0].Slot | Should -Be 1
        $Item[0].Leased | Should -BeFalse
        $Item[0].PSObject.TypeNames[0] | Should -Be 'OmadaSql.TempQuery'
        Should -Invoke Get-OmadaSqlQueryData -ModuleName 'OmadaSql.PS' -Times 1 -Exactly -ParameterFilter { $Name -eq 'TMP_*' -and $IncludeDeleted }
    }

    It 'Lists every TMP_ object with -All, and cannot see the lease of others' {
        $Item = @(InModuleScope 'OmadaSql.PS' { Get-OmadaSqlTempQueryObject -Context (Get-OmadaSqlConnectionContext) -All })
        @($Item.Id) | Should -Be @(1, 2, 3)
        $Item[1].ThisProfile | Should -BeFalse
        $Item[1].Leased | Should -BeNullOrEmpty
        $Item[2].Slot | Should -BeNullOrEmpty
    }
}

Describe 'ConvertTo-OmadaSqlTempQuery' -Tag 'Unit' {
    It 'Reads <Name>' -ForEach @(
        @{ Name = ('TMP_{0}_3' -f ('a' * 32)); ThisProfile = $true; Slot = 3 }
        @{ Name = ('TMP_{0}_3' -f ('b' * 32)); ThisProfile = $false; Slot = 3 }
        @{ Name = ('TMP_{0}' -f ('a' * 32)); ThisProfile = $false; Slot = $null }
        @{ Name = 'TMP_report'; ThisProfile = $false; Slot = $null }
    ) {
        InModuleScope 'OmadaSql.PS' -Parameters @{ Name = $Name; ThisProfile = $ThisProfile; Slot = $Slot } {
            param($Name, $ThisProfile, $Slot)
            $Item = ConvertTo-OmadaSqlTempQuery -Name $Name -InstanceGuid ('a' * 32)
            $Item.ThisProfile | Should -Be $ThisProfile
            $Item.Slot | Should -Be $Slot
            $Item.Name | Should -Be $Name
        }
    }
}

Describe 'Get-OmadaSqlTempQueryObject parameter contract' -Tag 'Unit' {
    # Parameter declarations run no code a test could observe, so the mutation gate's mutants of
    # Mandatory, Position, pipeline binding and ValidateRange are caught only by asserting the contract.
    It '<Command> -<Parameter> <ParameterSet>' -ForEach @(
        @{ Command = 'Get-OmadaSqlTempQueryObject'; Parameter = 'Context'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'ConvertTo-OmadaSqlTempQuery'; Parameter = 'Name'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'ConvertTo-OmadaSqlTempQuery'; Parameter = 'InstanceGuid'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
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
