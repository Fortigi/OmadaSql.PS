param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaSql.PS\OmadaSql.PS.psm1')
)

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers\OmadaSqlTestHelper.ps1')
    Get-Module -Name OmadaSql.PS -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $ModulePath -Force -ErrorAction Stop
    $Script:ODataUri = 'https://tenant.omada.cloud/odata/dataobjects/C_P_SQLTROUBLESHOOTING'
}

Describe 'New-OmadaSqlErrorRecord' -Tag 'Unit' {
    It 'Uses OmadaSql.<Kind> as the error id and maps <Kind> to <Category>' -ForEach @(
        @{ Kind = 'NotConnected'; Category = 'ConnectionError' }
        @{ Kind = 'MissingPermission'; Category = 'PermissionDenied' }
        @{ Kind = 'SessionExpired'; Category = 'AuthenticationError' }
        @{ Kind = 'NotFound'; Category = 'ObjectNotFound' }
        @{ Kind = 'ServerError'; Category = 'InvalidResult' }
    ) {
        InModuleScope 'OmadaSql.PS' -Parameters @{ Kind = $Kind; Category = $Category } {
            param($Kind, $Category)
            $Record = New-OmadaSqlErrorRecord -Kind $Kind -Message 'message'
            $Record.FullyQualifiedErrorId | Should -Be "OmadaSql.$Kind"
            [string]$Record.CategoryInfo.Category | Should -Be $Category
            $Record.Exception.Message | Should -Be 'message'
        }
    }

    It 'Keeps the original exception as the inner exception' {
        InModuleScope 'OmadaSql.PS' {
            $Inner = [System.Exception]::new('original')
            (New-OmadaSqlErrorRecord -Kind 'ServerError' -Message 'wrapped' -InnerException $Inner).Exception.InnerException.Message | Should -Be 'original'
        }
    }
}
