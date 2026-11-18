param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaSql.PS\OmadaSql.PS.psm1')
)

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers\OmadaSqlTestHelper.ps1')
    Import-OmadaWebStub
    Get-Module -Name OmadaSql.PS -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $ModulePath -Force -ErrorAction Stop
}


Describe 'Get-OmadaSqlQuery' -Tag 'Unit' {
    BeforeAll {
        $Script:Connection = Initialize-OmadaSqlTestConnection
    }

    It 'Returns OmadaSql.Query objects for a list' {
        Mock Get-OmadaSqlQueryData -ModuleName 'OmadaSql.PS' { (New-OmadaSqlTestODataQuery -Id 1), (New-OmadaSqlTestODataQuery -Id 2) }
        $Result = @(Get-OmadaSqlQuery)
        $Result.Id | Should -Be @(1, 2)
        $Result[0].PSObject.TypeNames | Should -Contain 'OmadaSql.Query'
        Should -Invoke Get-OmadaSqlQueryData -ModuleName 'OmadaSql.PS' -Times 1 -Exactly -ParameterFilter { $Id -eq 0 -and $Name -eq '*' -and -not $IncludeDeleted }
    }

    It 'Passes the name and -IncludeDeleted on' {
        Mock Get-OmadaSqlQueryData -ModuleName 'OmadaSql.PS' { }
        $null = Get-OmadaSqlQuery -Name 'Daily*' -IncludeDeleted
        Should -Invoke Get-OmadaSqlQueryData -ModuleName 'OmadaSql.PS' -Times 1 -Exactly -ParameterFilter { $Name -eq 'Daily*' -and $IncludeDeleted }
    }

    It 'Reads each id from the pipeline' {
        Mock Get-OmadaSqlQueryData -ModuleName 'OmadaSql.PS' { New-OmadaSqlTestODataQuery -Id $Id }
        @([pscustomobject]@{ Id = 5 }, [pscustomobject]@{ Id = 6 } | Get-OmadaSqlQuery).Id | Should -Be @(5, 6)
    }

    It 'Adds the detail with -Detailed' {
        Mock Get-OmadaSqlQueryData -ModuleName 'OmadaSql.PS' { New-OmadaSqlTestODataQuery -Id 9 }
        Mock Add-OmadaSqlQueryDetail -ModuleName 'OmadaSql.PS' { $Query | Add-Member -NotePropertyName 'Marker' -NotePropertyValue 'detail' -PassThru }
        (Get-OmadaSqlQuery -Id 9 -Detailed).Marker | Should -Be 'detail'
    }

    It 'Fails with the OmadaSql error of the request' {
        # Built here: a mock body runs in the test's scope, where the module's private functions are not visible.
        Mock Get-OmadaSqlQueryData -ModuleName 'OmadaSql.PS' {
            throw ([System.Management.Automation.ErrorRecord]::new([System.InvalidOperationException]::new('gone'), 'OmadaSql.NotFound', [System.Management.Automation.ErrorCategory]::ObjectNotFound, $null))
        }
        { Get-OmadaSqlQuery -Id 404 } | Should -Throw -ErrorId 'OmadaSql.NotFound,Get-OmadaSqlQuery'
    }
}
