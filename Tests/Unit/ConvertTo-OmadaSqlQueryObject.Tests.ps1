param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaSql.PS\OmadaSql.PS.psm1')
)

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers\OmadaSqlTestHelper.ps1')
    Import-OmadaWebStub
    Get-Module -Name OmadaSql.PS -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $ModulePath -Force -ErrorAction Stop
}


Describe 'ConvertTo-OmadaSqlQueryObject' -Tag 'Unit' {
    It 'Maps the OData object to an OmadaSql.Query and keeps the original' {
        $Raw = New-OmadaSqlTestODataQuery -Id 7 -Name 'Q' -Query 'SELECT 1 AS [x]' -DataConnectionId 1001 -DataConnectionName 'OISES'
        InModuleScope 'OmadaSql.PS' -Parameters @{ Raw = $Raw } {
            param($Raw)
            $Result = $Raw | ConvertTo-OmadaSqlQueryObject -BaseUrl 'https://tenant.omada.cloud'
            $Result.PSObject.TypeNames | Should -Contain 'OmadaSql.Query'
            $Result.Id | Should -Be 7
            $Result.Name | Should -Be 'Q'
            $Result.Query | Should -Be 'SELECT 1 AS [x]'
            $Result.DataConnectionId | Should -Be 1001
            $Result.DataConnectionName | Should -Be 'OISES'
            $Result.Deleted | Should -BeFalse
            $Result.BaseUrl | Should -Be 'https://tenant.omada.cloud'
            $Result.Properties | Should -Be $Raw
        }
    }

    It 'Accepts a data connection reference with Name instead of DisplayName, and a bare id' {
        $WithName = [pscustomobject]@{ Id = 1; NAME = 'a'; C_SQLTROUBLESHOOTING_DATACONNECTION = [pscustomobject]@{ Id = 5; Name = 'ODW' } }
        $BareId = [pscustomobject]@{ Id = 2; NAME = 'b'; C_SQLTROUBLESHOOTING_DATACONNECTION = 6 }
        InModuleScope 'OmadaSql.PS' -Parameters @{ WithName = $WithName; BareId = $BareId } {
            param($WithName, $BareId)
            $First = ConvertTo-OmadaSqlQueryObject -InputObject $WithName -BaseUrl 'https://t'
            $First.DataConnectionName | Should -Be 'ODW'
            $First.DataConnectionId | Should -Be 5
            $Second = ConvertTo-OmadaSqlQueryObject -InputObject $BareId -BaseUrl 'https://t'
            $Second.DataConnectionId | Should -Be 6
            $Second.DataConnectionName | Should -BeNullOrEmpty
        }
    }

    It 'Tolerates missing properties, as OData returns what the tenant exposes' {
        InModuleScope 'OmadaSql.PS' {
            $Result = ConvertTo-OmadaSqlQueryObject -InputObject ([pscustomobject]@{ Id = 3 }) -BaseUrl 'https://t'
            $Result.Id | Should -Be 3
            $Result.Name | Should -Be ''
            $Result.DataConnectionId | Should -BeNullOrEmpty
            $Result.Deleted | Should -BeFalse
        }
    }

    It 'Reports a deleted object' {
        $Raw = New-OmadaSqlTestODataQuery -Deleted $true
        InModuleScope 'OmadaSql.PS' -Parameters @{ Raw = $Raw } {
            param($Raw)
            (ConvertTo-OmadaSqlQueryObject -InputObject $Raw -BaseUrl 'https://t').Deleted | Should -BeTrue
        }
    }
}

Describe 'Get-OmadaSqlPropertyValue' -Tag 'Unit' {
    It 'Reads objects and dictionaries, and returns null for a missing property or object' {
        InModuleScope 'OmadaSql.PS' {
            Get-OmadaSqlPropertyValue -InputObject ([pscustomobject]@{ A = 1 }) -Name 'A' | Should -Be 1
            Get-OmadaSqlPropertyValue -InputObject @{ A = 2 } -Name 'A' | Should -Be 2
            Get-OmadaSqlPropertyValue -InputObject ([pscustomobject]@{ A = 1 }) -Name 'B' | Should -BeNullOrEmpty
            Get-OmadaSqlPropertyValue -InputObject @{ A = 2 } -Name 'B' | Should -BeNullOrEmpty
            Get-OmadaSqlPropertyValue -InputObject $null -Name 'A' | Should -BeNullOrEmpty
        }
    }

    It 'Returns a collection value whole instead of its first element' {
        InModuleScope 'OmadaSql.PS' {
            $Value = Get-OmadaSqlPropertyValue -InputObject ([pscustomobject]@{ Owners = @('a', 'b') }) -Name 'Owners'
            @($Value).Count | Should -Be 2
            $One = Get-OmadaSqlPropertyValue -InputObject ([pscustomobject]@{ Owners = @('a') }) -Name 'Owners'
            , $One | Should -BeOfType [array]
        }
    }
}

Describe 'ConvertTo-OmadaSqlQueryObject data connection id' -Tag 'Unit' {
    It 'Reports no data connection id for an empty reference id' {
        $Raw = [pscustomobject]@{ Id = 1; NAME = 'Q'; C_SQLTROUBLESHOOTING_DATACONNECTION = [pscustomobject]@{ Id = '' } }
        InModuleScope 'OmadaSql.PS' -Parameters @{ Raw = $Raw } {
            param($Raw)
            (ConvertTo-OmadaSqlQueryObject -InputObject $Raw -BaseUrl 'https://tenant.omada.cloud').DataConnectionId | Should -BeNullOrEmpty
        }
    }
}
