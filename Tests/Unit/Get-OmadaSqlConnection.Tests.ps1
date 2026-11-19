param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaSql.PS\OmadaSql.PS.psm1')
)

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers\OmadaSqlTestHelper.ps1')
    Import-OmadaWebStub
    Get-Module -Name OmadaSql.PS -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Get-OmadaSqlConnection' -Tag 'Unit' {
    BeforeEach {
        Disconnect-OmadaSql -All
        Mock Invoke-OmadaRestMethod -ModuleName 'OmadaSql.PS' { $null }
    }

    It 'Returns nothing when there is no connection' {
        Get-OmadaSqlConnection | Should -BeNullOrEmpty
        Get-OmadaSqlConnection -All | Should -BeNullOrEmpty
    }

    It 'Returns only the current connection without -All' {
        $null = Connect-OmadaSql -Url 'https://one.omada.cloud' -PassThru
        $Second = Connect-OmadaSql -Url 'https://two.omada.cloud' -PassThru

        $Result = @(Get-OmadaSqlConnection)
        $Result.Count | Should -Be 1
        $Result[0].Id | Should -Be $Second.Id
    }

    It 'Returns every connection in the order they were made with -All' {
        $First = Connect-OmadaSql -Url 'https://one.omada.cloud' -PassThru
        $Second = Connect-OmadaSql -Url 'https://two.omada.cloud' -PassThru
        $Third = Connect-OmadaSql -Url 'https://three.omada.cloud' -PassThru

        @(Get-OmadaSqlConnection -All).Id | Should -Be @($First.Id, $Second.Id, $Third.Id)
    }

    It 'Returns nothing without -All once the current connection is removed, while others remain' {
        $null = Connect-OmadaSql -Url 'https://one.omada.cloud' -PassThru
        $null = Connect-OmadaSql -Url 'https://two.omada.cloud' -PassThru
        Disconnect-OmadaSql

        Get-OmadaSqlConnection | Should -BeNullOrEmpty
        @(Get-OmadaSqlConnection -All).Count | Should -Be 1
    }
}
