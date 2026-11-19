param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaSql.PS\OmadaSql.PS.psm1')
)

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers\OmadaSqlTestHelper.ps1')
    Import-OmadaWebStub
    Get-Module -Name OmadaSql.PS -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $ModulePath -Force -ErrorAction Stop
}


Describe 'Add-OmadaSqlQueryDetail' -Tag 'Unit' {
    BeforeAll {
        $Script:Connection = Initialize-OmadaSqlTestConnection
        Mock Get-OmadaSqlDataConnectionList -ModuleName 'OmadaSql.PS' { [pscustomobject]@{ Name = 'OISES'; Id = 1001 } }
        Mock Get-OmadaSqlHistoryEntry -ModuleName 'OmadaSql.PS' {
            [pscustomobject]@{ Id = $Id; ChangedAt = [datetime]'2026-11-03'; ChangedBy = 'Bob'; ChangeType = 'Modified'; Field = 'SQL Query' }
            [pscustomobject]@{ Id = $Id; ChangedAt = [datetime]'2026-10-01'; ChangedBy = 'Alice'; ChangeType = 'Created'; Field = $null }
            [pscustomobject]@{ Id = $Id; ChangedAt = [datetime]'2026-10-15'; ChangedBy = 'Carol'; ChangeType = 'Modified'; Field = 'Name' }
        }
    }

    It 'Adds the history, the creator and the last editor, and resolves the data connection name' {
        $Raw = [pscustomobject]@{ Id = 101; NAME = 'Q'; C_SQLTROUBLESHOOTING_DATACONNECTION = 1001 }
        InModuleScope 'OmadaSql.PS' -Parameters @{ Raw = $Raw } {
            param($Raw)
            $Query = ConvertTo-OmadaSqlQueryObject -InputObject $Raw -BaseUrl 'https://tenant.omada.cloud'
            $Result = Add-OmadaSqlQueryDetail -Context (Get-OmadaSqlConnectionContext) -Query $Query
            $Result.PSObject.TypeNames | Should -Contain 'OmadaSql.QueryDetail'
            @($Result.History).Count | Should -Be 3
            $Result.CreatedBy | Should -Be 'Alice'
            $Result.CreatedAt | Should -Be ([datetime]'2026-10-01')
            $Result.ChangedBy | Should -Be 'Bob'
            $Result.ChangedAt | Should -Be ([datetime]'2026-11-03')
            $Result.DataConnectionName | Should -Be 'OISES'
            $Result.Owner | Should -BeNullOrEmpty
        }
    }

    It 'Lists explicit owners by display name when the object has them' {
        $Raw = [pscustomobject]@{ Id = 101; NAME = 'Q'; EXPLICITOWNER = @([pscustomobject]@{ Id = 5; DisplayName = 'Admins' }, [pscustomobject]@{ Id = 6 }) }
        InModuleScope 'OmadaSql.PS' -Parameters @{ Raw = $Raw } {
            param($Raw)
            $Query = ConvertTo-OmadaSqlQueryObject -InputObject $Raw -BaseUrl 'https://tenant.omada.cloud'
            (Add-OmadaSqlQueryDetail -Context (Get-OmadaSqlConnectionContext) -Query $Query).Owner | Should -Be @('Admins', '6')
        }
    }
}

Describe 'Get-OmadaSqlHistorySummary' -Tag 'Unit' {
    It 'Falls back to the oldest entry when the history has no creation' {
        $History = @(
            [pscustomobject]@{ ChangedAt = [datetime]'2026-11-03'; ChangedBy = 'Bob'; ChangeType = 'Modified' }
            [pscustomobject]@{ ChangedAt = [datetime]'2026-10-15'; ChangedBy = 'Carol'; ChangeType = 'Modified' }
        )
        InModuleScope 'OmadaSql.PS' -Parameters @{ History = $History } {
            param($History)
            $Summary = Get-OmadaSqlHistorySummary -History $History
            $Summary.CreatedBy | Should -Be 'Carol'
            $Summary.ChangedBy | Should -Be 'Bob'
        }
    }

    It 'Returns empty values for a history without dated entries' {
        InModuleScope 'OmadaSql.PS' {
            $Summary = Get-OmadaSqlHistorySummary -History @([pscustomobject]@{ ChangedAt = $null; ChangedBy = 'x'; ChangeType = 'Created' })
            $Summary.CreatedBy | Should -BeNullOrEmpty
            $Summary.ChangedAt | Should -BeNullOrEmpty
        }
    }
}

Describe 'Add-OmadaSqlQueryDetail edge cases' -Tag 'Unit' {
    BeforeAll {
        $Script:Connection = Initialize-OmadaSqlTestConnection
        Mock Get-OmadaSqlHistoryEntry -ModuleName 'OmadaSql.PS' { }
        Mock Get-OmadaSqlDataConnection -ModuleName 'OmadaSql.PS' { [pscustomobject]@{ Name = 'RENAMED'; Id = 1001 } }
    }

    It 'Keeps the data connection name OData returned and does not look the connections up' {
        $Raw = New-OmadaSqlTestODataQuery -DataConnectionId 1001 -DataConnectionName 'OISES'
        InModuleScope 'OmadaSql.PS' -Parameters @{ Raw = $Raw } {
            param($Raw)
            $Query = ConvertTo-OmadaSqlQueryObject -InputObject $Raw -BaseUrl 'https://tenant.omada.cloud'
            (Add-OmadaSqlQueryDetail -Context (Get-OmadaSqlConnectionContext) -Query $Query).DataConnectionName | Should -Be 'OISES'
        }
        Should -Invoke Get-OmadaSqlDataConnection -ModuleName 'OmadaSql.PS' -Times 0 -Exactly
    }

    It 'Makes OmadaSql.QueryDetail the primary type name, so its format view applies' {
        $Raw = New-OmadaSqlTestODataQuery
        InModuleScope 'OmadaSql.PS' -Parameters @{ Raw = $Raw } {
            param($Raw)
            $Query = ConvertTo-OmadaSqlQueryObject -InputObject $Raw -BaseUrl 'https://tenant.omada.cloud'
            $Result = Add-OmadaSqlQueryDetail -Context (Get-OmadaSqlConnectionContext) -Query $Query
            $Result.PSObject.TypeNames[0] | Should -Be 'OmadaSql.QueryDetail'
            $Result.PSObject.TypeNames[1] | Should -Be 'OmadaSql.Query'
        }
    }
}

Describe 'Get-OmadaSqlHistorySummary edge cases' -Tag 'Unit' {
    It 'Uses a single dated entry as both the creation and the last change' {
        InModuleScope 'OmadaSql.PS' {
            $Summary = Get-OmadaSqlHistorySummary -History @([pscustomobject]@{ ChangedAt = [datetime]'2026-10-01'; ChangedBy = 'Alice'; ChangeType = 'Modified' })
            $Summary.CreatedBy | Should -Be 'Alice'
            $Summary.ChangedBy | Should -Be 'Alice'
            $Summary.CreatedAt | Should -Be ([datetime]'2026-10-01')
        }
    }

    It 'Takes only the oldest creation when the history holds more than one' {
        $History = @(
            [pscustomobject]@{ ChangedAt = [datetime]'2026-10-05'; ChangedBy = 'Dave'; ChangeType = 'Created' }
            [pscustomobject]@{ ChangedAt = [datetime]'2026-10-01'; ChangedBy = 'Alice'; ChangeType = 'Created' }
        )
        InModuleScope 'OmadaSql.PS' -Parameters @{ History = $History } {
            param($History)
            $Summary = Get-OmadaSqlHistorySummary -History $History
            $Summary.CreatedBy | Should -BeExactly 'Alice'
            @($Summary.CreatedBy).Count | Should -Be 1
            @($Summary.CreatedAt).Count | Should -Be 1
        }
    }
}

Describe 'Get-OmadaSqlReferenceName' -Tag 'Unit' {
    It 'Skips an empty display name and uses the name' {
        InModuleScope 'OmadaSql.PS' {
            Get-OmadaSqlReferenceName -Reference ([pscustomobject]@{ DisplayName = ''; Name = 'Admins'; Id = 5 }) | Should -Be 'Admins'
        }
    }

    It 'Falls back to the id when display name and name are missing' {
        InModuleScope 'OmadaSql.PS' {
            Get-OmadaSqlReferenceName -Reference ([pscustomobject]@{ Id = 5 }) | Should -Be '5'
        }
    }
}
