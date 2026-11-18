param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaSql.PS\OmadaSql.PS.psm1')
)

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers\OmadaSqlTestHelper.ps1')
    Import-OmadaWebStub
    Get-Module OmadaSql.PS | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Test-OmadaSqlRestMethodParameter' -Tag 'Unit' {
    It 'Answers from the parameters of the loaded Invoke-OmadaRestMethod' {
        InModuleScope 'OmadaSql.PS' {
            $Script:OmadaSqlRestMethodParameterCache = $null
            Test-OmadaSqlRestMethodParameter -Name 'NoInteractiveAuthentication' | Should -BeTrue
            Test-OmadaSqlRestMethodParameter -Name 'DoesNotExist' | Should -BeFalse
        }
    }
}
