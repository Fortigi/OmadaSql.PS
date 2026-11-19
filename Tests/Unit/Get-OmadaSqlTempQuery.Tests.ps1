param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaSql.PS\OmadaSql.PS.psm1')
)

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers\OmadaSqlTestHelper.ps1')
    Import-OmadaWebStub
    Get-Module -Name OmadaSql.PS -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Get-OmadaSqlTempQuery' -Tag 'Unit' {
    BeforeAll {
        $Script:Connection = Initialize-OmadaSqlTestConnection
    }

    It 'Lists through the current connection and passes -All on' {
        Mock Get-OmadaSqlTempQueryObject -ModuleName 'OmadaSql.PS' { [pscustomobject]@{ Id = 1 } }
        @(Get-OmadaSqlTempQuery -All).Count | Should -Be 1
        Should -Invoke Get-OmadaSqlTempQueryObject -ModuleName 'OmadaSql.PS' -Times 1 -Exactly -ParameterFilter { $All }
    }

    It 'Fails terminating when there is no connection' {
        Disconnect-OmadaSql -All
        { Get-OmadaSqlTempQuery } | Should -Throw -ErrorId 'OmadaSql.NotConnected,Get-OmadaSqlTempQuery'
        $Script:Connection = Initialize-OmadaSqlTestConnection
    }
}
