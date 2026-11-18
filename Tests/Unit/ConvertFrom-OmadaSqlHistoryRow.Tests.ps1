param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaSql.PS\OmadaSql.PS.psm1')
)

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers\OmadaSqlTestHelper.ps1')
    Import-OmadaWebStub
    Get-Module -Name OmadaSql.PS -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $ModulePath -Force -ErrorAction Stop
}


Describe 'ConvertFrom-OmadaSqlHistoryRow' -Tag 'Unit' {
    It 'Returns one entry per changed field, with every field kept' {
        $Row = [pscustomobject]@{
            Object        = 'Daily export'
            Who           = 'Jane Admin'
            What          = 'Modified'
            When          = '2026-11-01T10:15:00'
            ChangedFields = '[{"Field":"SQL Query","OldValue":"SELECT 1","NewValue":"SELECT 2 AS [x] WHERE a &lt; b"},{"Field":"Name","OldValue":"[N/A]","NewValue":"Daily export"}]'
        }
        InModuleScope 'OmadaSql.PS' -Parameters @{ Row = $Row } {
            param($Row)
            $Result = @($Row | ConvertFrom-OmadaSqlHistoryRow -Id 101)
            $Result.Count | Should -Be 2
            $Result[0].PSObject.TypeNames | Should -Contain 'OmadaSql.HistoryEntry'
            $Result[0].Id | Should -Be 101
            $Result[0].Name | Should -Be 'Daily export'
            $Result[0].ChangedBy | Should -Be 'Jane Admin'
            $Result[0].ChangeType | Should -Be 'Modified'
            $Result[0].ChangedAt | Should -Be ([datetime]'2026-11-01T10:15:00')
            $Result[0].Field | Should -Be 'SQL Query'
            $Result[0].OldValue | Should -Be 'SELECT 1'
            $Result[0].NewValue | Should -Be 'SELECT 2 AS [x] WHERE a < b'
            $Result[1].Field | Should -Be 'Name'
            $Result[1].OldValue | Should -BeNullOrEmpty
        }
    }

    It 'Accepts ChangedFields that arrive already parsed' {
        $Row = [pscustomobject]@{ Object = 'x'; Who = 'w'; What = 'Modified'; When = ''; ChangedFields = @([pscustomobject]@{ Field = 'Name'; OldValue = 'a'; NewValue = 'b' }) }
        InModuleScope 'OmadaSql.PS' -Parameters @{ Row = $Row } {
            param($Row)
            $Result = @(ConvertFrom-OmadaSqlHistoryRow -Row $Row -Id 1)
            $Result.Count | Should -Be 1
            $Result[0].NewValue | Should -Be 'b'
            $Result[0].ChangedAt | Should -BeNullOrEmpty
        }
    }

    It 'Keeps a row without changed fields as one entry, and skips unreadable ChangedFields without failing' {
        $Rows = @(
            [pscustomobject]@{ Object = 'x'; Who = 'w'; What = 'Deleted'; When = '2026-11-02'; ChangedFields = '' }
            [pscustomobject]@{ Object = 'x'; Who = 'w'; What = 'Modified'; When = '2026-11-03'; ChangedFields = 'not json' }
        )
        InModuleScope 'OmadaSql.PS' -Parameters @{ Rows = $Rows } {
            param($Rows)
            $Result = @($Rows | ConvertFrom-OmadaSqlHistoryRow -Id 1)
            $Result.Count | Should -Be 2
            $Result[0].ChangeType | Should -Be 'Deleted'
            $Result[0].Field | Should -BeNullOrEmpty
        }
    }

    It 'Ignores a null row' {
        InModuleScope 'OmadaSql.PS' {
            @(ConvertFrom-OmadaSqlHistoryRow -Row $null -Id 1).Count | Should -Be 0
        }
    }
}

Describe 'ConvertTo-OmadaSqlHistoryDate' -Tag 'Unit' {
    It 'Reads an ISO date and an invariant month-first date' {
        InModuleScope 'OmadaSql.PS' {
            ConvertTo-OmadaSqlHistoryDate -Value '2026-08-25T12:03:00' | Should -Be ([datetime]::new(2026, 8, 25, 12, 3, 0))
            ConvertTo-OmadaSqlHistoryDate -Value '8/25/2026 12:03 PM' | Should -Be ([datetime]::new(2026, 8, 25, 12, 3, 0))
        }
    }

    It 'Returns null for an empty or unreadable date instead of failing' {
        InModuleScope 'OmadaSql.PS' {
            ConvertTo-OmadaSqlHistoryDate -Value '' | Should -BeNullOrEmpty
            ConvertTo-OmadaSqlHistoryDate -Value 'not a date' | Should -BeNullOrEmpty
        }
    }
}
