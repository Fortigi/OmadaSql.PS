param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaSql.PS\OmadaSql.PS.psm1')
)

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers\OmadaSqlTestHelper.ps1')
    Import-OmadaWebStub
    Get-Module -Name OmadaSql.PS -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $ModulePath -Force -ErrorAction Stop
}


Describe 'Get-OmadaSqlDataConnectionList' -Tag 'Unit' {
    BeforeAll {
        $Script:Connection = Initialize-OmadaSqlTestConnection
    }

    It 'Reads the view, its first row and that object''s edit page' {
        Mock Invoke-OmadaSqlPagingRequest -ModuleName 'OmadaSql.PS' -ParameterFilter { $DataType -eq 'Views' } { [pscustomobject]@{ Rows = @([pscustomobject]@{ Name = 'Other'; Id = 1 }, [pscustomobject]@{ Name = 'SQL Troubleshooting'; Id = 77 }) } }
        Mock Invoke-OmadaSqlPagingRequest -ModuleName 'OmadaSql.PS' -ParameterFilter { $DataType -eq 'DataObjects' } { [pscustomobject]@{ Rows = @([pscustomobject]@{ 'c-13' = 555 }) } }
        Mock Invoke-OmadaSqlRequest -ModuleName 'OmadaSql.PS' { '<option value="1001" data-uid="u">OISES</option>' }

        InModuleScope 'OmadaSql.PS' {
            @(Get-OmadaSqlDataConnectionList -Context (Get-OmadaSqlConnectionContext)).Name | Should -Be @('OISES')
        }
        Should -Invoke Invoke-OmadaSqlPagingRequest -ModuleName 'OmadaSql.PS' -Times 1 -Exactly -ParameterFilter {
            $DataType -eq 'DataObjects' -and $DataTypeArgument.viewId -eq '77' -and $DataTypeArgument.pageQueryString -eq 'https://tenant.omada.cloud/dataobjlst.aspx?view=77'
        }
        Should -Invoke Invoke-OmadaSqlRequest -ModuleName 'OmadaSql.PS' -Times 1 -Exactly -ParameterFilter { $Method -eq 'GET' -and $Path -eq 'dataobjdlg.aspx?DOID=555' }
    }

    It 'Fails with NotFound when the view does not exist' {
        Mock Invoke-OmadaSqlPagingRequest -ModuleName 'OmadaSql.PS' { [pscustomobject]@{ Rows = @() } }
        InModuleScope 'OmadaSql.PS' {
            { Get-OmadaSqlDataConnectionList -Context (Get-OmadaSqlConnectionContext) } | Should -Throw -ErrorId 'OmadaSql.NotFound'
        }
    }

    It 'Fails with NotFound when the view holds no SQL Troubleshooting object' {
        Mock Invoke-OmadaSqlPagingRequest -ModuleName 'OmadaSql.PS' -ParameterFilter { $DataType -eq 'Views' } { [pscustomobject]@{ Rows = @([pscustomobject]@{ Name = 'SQL Troubleshooting'; Id = 77 }) } }
        Mock Invoke-OmadaSqlPagingRequest -ModuleName 'OmadaSql.PS' -ParameterFilter { $DataType -eq 'DataObjects' } { [pscustomobject]@{ Rows = @() } }
        InModuleScope 'OmadaSql.PS' {
            { Get-OmadaSqlDataConnectionList -Context (Get-OmadaSqlConnectionContext) } | Should -Throw -ErrorId 'OmadaSql.NotFound'
        }
    }

    It 'Fails with InvalidResult when the edit page lists no data connection' {
        Mock Invoke-OmadaSqlPagingRequest -ModuleName 'OmadaSql.PS' -ParameterFilter { $DataType -eq 'Views' } { [pscustomobject]@{ Rows = @([pscustomobject]@{ Name = 'SQL Troubleshooting'; Id = 77 }) } }
        Mock Invoke-OmadaSqlPagingRequest -ModuleName 'OmadaSql.PS' -ParameterFilter { $DataType -eq 'DataObjects' } { [pscustomobject]@{ Rows = @([pscustomobject]@{ 'c-13' = 555 }) } }
        Mock Invoke-OmadaSqlRequest -ModuleName 'OmadaSql.PS' { '<html></html>' }
        InModuleScope 'OmadaSql.PS' {
            { Get-OmadaSqlDataConnectionList -Context (Get-OmadaSqlConnectionContext) } | Should -Throw -ErrorId 'OmadaSql.InvalidResult'
        }
    }
}

Describe 'Resolve-OmadaSqlDataConnection' -Tag 'Unit' {
    BeforeAll {
        $Script:Connection = Initialize-OmadaSqlTestConnection
        Mock Get-OmadaSqlDataConnectionList -ModuleName 'OmadaSql.PS' {
            [pscustomobject]@{ Name = 'OISES'; Id = 1001 }
            [pscustomobject]@{ Name = 'ODW'; Id = 1002 }
        }
    }

    It 'Resolves <Case>' -ForEach @(
        @{ Case = 'a name, case-insensitively'; Value = 'odw'; Expected = 1002 }
        @{ Case = 'an id as a number'; Value = 1001; Expected = 1001 }
        @{ Case = 'an id as a string'; Value = ' 1002 '; Expected = 1002 }
        @{ Case = 'a data connection object'; Value = [pscustomobject]@{ Name = 'whatever'; Id = 1001 }; Expected = 1001 }
    ) {
        InModuleScope 'OmadaSql.PS' -Parameters @{ Value = $Value; Expected = $Expected } {
            param($Value, $Expected)
            (Resolve-OmadaSqlDataConnection -Context (Get-OmadaSqlConnectionContext) -DataConnection $Value).Id | Should -Be $Expected
        }
    }

    It 'Fails with InvalidArgument and lists the available names for an unknown one' {
        InModuleScope 'OmadaSql.PS' {
            $Caught = $null
            try {
                $null = Resolve-OmadaSqlDataConnection -Context (Get-OmadaSqlConnectionContext) -DataConnection 'Nope'
            }
            catch {
                $Caught = $_
            }
            $Caught.FullyQualifiedErrorId | Should -Be 'OmadaSql.InvalidArgument'
            $Caught.Exception.Message | Should -BeLike '*Available: ODW, OISES*'
        }
    }
}
