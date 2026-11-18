param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaSql.PS\OmadaSql.PS.psm1')
)

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers\OmadaSqlTestHelper.ps1')
    Import-OmadaWebStub
    Get-Module -Name OmadaSql.PS -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Disconnect-OmadaSql' -Tag 'Unit' {
    BeforeEach {
        Disconnect-OmadaSql -All
        Mock Invoke-OmadaRestMethod -ModuleName 'OmadaSql.PS' { $null }
    }

    It 'Removes the current connection' {
        Connect-OmadaSql -Url 'https://tenant.omada.cloud'
        Disconnect-OmadaSql
        Get-OmadaSqlConnection | Should -BeNullOrEmpty
        Get-OmadaSqlConnection -All | Should -BeNullOrEmpty
    }

    It 'Removes a specific connection from the pipeline and leaves the current one when it was another' {
        $First = Connect-OmadaSql -Url 'https://one.omada.cloud' -PassThru
        $Second = Connect-OmadaSql -Url 'https://two.omada.cloud' -PassThru

        $First | Disconnect-OmadaSql

        (Get-OmadaSqlConnection).Id | Should -Be $Second.Id
        @(Get-OmadaSqlConnection -All).Count | Should -Be 1
    }

    It 'Clears the current connection when the removed one was current' {
        $null = Connect-OmadaSql -Url 'https://one.omada.cloud' -PassThru
        $Second = Connect-OmadaSql -Url 'https://two.omada.cloud' -PassThru

        Disconnect-OmadaSql -Connection $Second

        Get-OmadaSqlConnection | Should -BeNullOrEmpty
        @(Get-OmadaSqlConnection -All).Count | Should -Be 1
    }

    It 'Fails with NotConnected when there is nothing to remove' {
        { Disconnect-OmadaSql } | Should -Throw -ErrorId 'OmadaSql.NotConnected,Disconnect-OmadaSql'
    }
}
