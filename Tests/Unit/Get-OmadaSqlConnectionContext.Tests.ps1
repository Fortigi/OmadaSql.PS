param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaSql.PS\OmadaSql.PS.psm1')
)

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers\OmadaSqlTestHelper.ps1')
    Import-OmadaWebStub
    Get-Module OmadaSql.PS | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Get-OmadaSqlConnectionContext' -Tag 'Unit' {
    BeforeEach {
        Disconnect-OmadaSql -All
        Mock Invoke-OmadaRestMethod -ModuleName 'OmadaSql.PS' { $null }
    }

    It 'Resolves the current connection, a connection object and a connection id' {
        $Connection = Connect-OmadaSql -Url 'https://tenant.omada.cloud' -PassThru
        InModuleScope 'OmadaSql.PS' -Parameters @{ Connection = $Connection } {
            param($Connection)
            (Get-OmadaSqlConnectionContext).Connection.Id | Should -Be $Connection.Id
            (Get-OmadaSqlConnectionContext -Connection $Connection).Connection.Id | Should -Be $Connection.Id
            (Get-OmadaSqlConnectionContext -Connection $Connection.Id).Connection.Id | Should -Be $Connection.Id
        }
    }

    It 'Fails with NotConnected for a disconnected connection' {
        $Connection = Connect-OmadaSql -Url 'https://tenant.omada.cloud' -PassThru
        Disconnect-OmadaSql
        InModuleScope 'OmadaSql.PS' -Parameters @{ Connection = $Connection } {
            param($Connection)
            { Get-OmadaSqlConnectionContext -Connection $Connection } | Should -Throw -ErrorId 'OmadaSql.NotConnected'
        }
    }

    It 'Fails with InvalidArgument for something that is not a connection' {
        InModuleScope 'OmadaSql.PS' {
            { Get-OmadaSqlConnectionContext -Connection ([pscustomobject]@{ Name = 'x' }) } | Should -Throw -ErrorId 'OmadaSql.InvalidArgument'
        }
    }
}
