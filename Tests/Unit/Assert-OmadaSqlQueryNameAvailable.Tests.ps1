param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaSql.PS\OmadaSql.PS.psm1')
)

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers\OmadaSqlTestHelper.ps1')
    Import-OmadaWebStub
    Get-Module -Name OmadaSql.PS -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $ModulePath -Force -ErrorAction Stop
}


Describe 'Assert-OmadaSqlQueryNameAvailable' -Tag 'Unit' {
    BeforeAll {
        $Script:Connection = Initialize-OmadaSqlTestConnection
    }

    It 'Passes when no live object has the name, and looks it up exactly' {
        Mock Get-OmadaSqlQueryData -ModuleName 'OmadaSql.PS' { }
        InModuleScope 'OmadaSql.PS' {
            { Assert-OmadaSqlQueryNameAvailable -Context (Get-OmadaSqlConnectionContext) -Name 'Report [v2]' } | Should -Not -Throw
        }
        Should -Invoke Get-OmadaSqlQueryData -ModuleName 'OmadaSql.PS' -Times 1 -Exactly -ParameterFilter { $ExactName -eq 'Report [v2]' }
    }

    It 'Fails with InvalidArgument when another object has the name' {
        Mock Get-OmadaSqlQueryData -ModuleName 'OmadaSql.PS' { New-OmadaSqlTestODataQuery -Id 5 -Name 'Taken' }
        InModuleScope 'OmadaSql.PS' {
            { Assert-OmadaSqlQueryNameAvailable -Context (Get-OmadaSqlConnectionContext) -Name 'Taken' } | Should -Throw -ErrorId 'OmadaSql.InvalidArgument'
        }
    }

    It 'Does not count the object being renamed' {
        Mock Get-OmadaSqlQueryData -ModuleName 'OmadaSql.PS' { New-OmadaSqlTestODataQuery -Id 5 -Name 'Taken' }
        InModuleScope 'OmadaSql.PS' {
            { Assert-OmadaSqlQueryNameAvailable -Context (Get-OmadaSqlConnectionContext) -Name 'Taken' -ExceptId 5 } | Should -Not -Throw
        }
    }
}
