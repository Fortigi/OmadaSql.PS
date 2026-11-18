param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaSql.PS\OmadaSql.PS.psm1')
)

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers\OmadaSqlTestHelper.ps1')
    Import-OmadaWebStub
    Get-Module -Name OmadaSql.PS -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $ModulePath -Force -ErrorAction Stop
}


Describe 'Get-OmadaSqlDataConnection' -Tag 'Unit' {
    BeforeEach {
        $Script:Connection = Initialize-OmadaSqlTestConnection
        Mock Get-OmadaSqlDataConnectionList -ModuleName 'OmadaSql.PS' {
            [pscustomobject]@{ Name = 'OISES'; Id = 1001 }
            [pscustomobject]@{ Name = 'ODW'; Id = 1002 }
        }
    }

    It 'Returns every data connection, and filters by name with wildcards' {
        @(Get-OmadaSqlDataConnection).Count | Should -Be 2
        @(Get-OmadaSqlDataConnection -Name 'OIS*').Id | Should -Be @(1001)
    }

    It 'Reads the list once per connection and again with -Force' {
        $null = Get-OmadaSqlDataConnection
        $null = Get-OmadaSqlDataConnection -Name 'ODW'
        Should -Invoke Get-OmadaSqlDataConnectionList -ModuleName 'OmadaSql.PS' -Times 1 -Exactly

        $null = Get-OmadaSqlDataConnection -Force
        Should -Invoke Get-OmadaSqlDataConnectionList -ModuleName 'OmadaSql.PS' -Times 2 -Exactly
    }

    It 'Fails with NotConnected without a connection' {
        Disconnect-OmadaSql -All
        { Get-OmadaSqlDataConnection } | Should -Throw -ErrorId 'OmadaSql.NotConnected,Get-OmadaSqlDataConnection'
    }
}
