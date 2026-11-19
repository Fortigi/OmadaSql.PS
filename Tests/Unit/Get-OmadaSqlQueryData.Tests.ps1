param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaSql.PS\OmadaSql.PS.psm1')
)

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers\OmadaSqlTestHelper.ps1')
    Import-OmadaWebStub
    Get-Module -Name OmadaSql.PS -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $ModulePath -Force -ErrorAction Stop
}


Describe 'Get-OmadaSqlQueryData' -Tag 'Unit' {
    BeforeAll {
        $Script:Connection = Initialize-OmadaSqlTestConnection
    }

    It 'Reads one object by id' {
        Mock Invoke-OmadaSqlRequest -ModuleName 'OmadaSql.PS' { New-OmadaSqlTestODataQuery -Id 42 }
        InModuleScope 'OmadaSql.PS' {
            (Get-OmadaSqlQueryData -Context (Get-OmadaSqlConnectionContext) -Id 42).Id | Should -Be 42
        }
        Should -Invoke Invoke-OmadaSqlRequest -ModuleName 'OmadaSql.PS' -Times 1 -Exactly -ParameterFilter { $Method -eq 'GET' -and $Path -eq 'odata/dataobjects/C_P_SQLTROUBLESHOOTING(42)' }
    }

    It 'Asks for deleted objects too with -IncludeDeleted' {
        Mock Invoke-OmadaSqlRequest -ModuleName 'OmadaSql.PS' { New-OmadaSqlTestODataQuery -Id 42 }
        InModuleScope 'OmadaSql.PS' {
            $null = Get-OmadaSqlQueryData -Context (Get-OmadaSqlConnectionContext) -Id 42 -IncludeDeleted
        }
        Should -Invoke Invoke-OmadaSqlRequest -ModuleName 'OmadaSql.PS' -Times 1 -Exactly -ParameterFilter { $Path -eq 'odata/dataobjects/C_P_SQLTROUBLESHOOTING(42)?DeletedStatus=Both' }
    }

    It 'Lists every page, ordered by name, with an OData filter for an exact name' {
        Mock Invoke-OmadaSqlRequest -ModuleName 'OmadaSql.PS' { [pscustomobject]@{ value = @(New-OmadaSqlTestODataQuery -Id 1) } }
        InModuleScope 'OmadaSql.PS' {
            @(Get-OmadaSqlQueryData -Context (Get-OmadaSqlConnectionContext) -Name 'Daily export').Count | Should -Be 1
        }
        Should -Invoke Invoke-OmadaSqlRequest -ModuleName 'OmadaSql.PS' -Times 1 -Exactly -ParameterFilter {
            $Paged -and [System.Uri]::UnescapeDataString($Path) -eq "odata/dataobjects/C_P_SQLTROUBLESHOOTING?`$filter=NAME eq 'Daily export'&`$orderby=NAME"
        }
    }

    It 'Filters a wildcard name locally and sends no name filter' {
        Mock Invoke-OmadaSqlRequest -ModuleName 'OmadaSql.PS' { [pscustomobject]@{ value = @((New-OmadaSqlTestODataQuery -Id 1 -Name 'Daily a'), (New-OmadaSqlTestODataQuery -Id 2 -Name 'Weekly'), (New-OmadaSqlTestODataQuery -Id 3 -Name 'Daily b')) } }
        InModuleScope 'OmadaSql.PS' {
            @(Get-OmadaSqlQueryData -Context (Get-OmadaSqlConnectionContext) -Name 'Daily*').Id | Should -Be @(1, 3)
        }
        Should -Invoke Invoke-OmadaSqlRequest -ModuleName 'OmadaSql.PS' -Times 1 -Exactly -ParameterFilter { $Path -eq 'odata/dataobjects/C_P_SQLTROUBLESHOOTING?$orderby=NAME' }
    }

    It 'Sends an exact name with wildcard characters as an OData filter, not as a pattern' {
        Mock Invoke-OmadaSqlRequest -ModuleName 'OmadaSql.PS' { [pscustomobject]@{ value = @() } }
        InModuleScope 'OmadaSql.PS' {
            $null = Get-OmadaSqlQueryData -Context (Get-OmadaSqlConnectionContext) -ExactName 'Report [v2]*'
        }
        Should -Invoke Invoke-OmadaSqlRequest -ModuleName 'OmadaSql.PS' -Times 1 -Exactly -ParameterFilter {
            [System.Uri]::UnescapeDataString($Path) -like "*`$filter=NAME eq 'Report [[]v2]*'*"
        }
    }

    It 'Returns nothing for a list response without value' {
        Mock Invoke-OmadaSqlRequest -ModuleName 'OmadaSql.PS' { $null }
        InModuleScope 'OmadaSql.PS' {
            @(Get-OmadaSqlQueryData -Context (Get-OmadaSqlConnectionContext)).Count | Should -Be 0
        }
    }
}

Describe 'Get-OmadaSqlQueryData boundaries' -Tag 'Unit' {
    BeforeAll {
        $Script:Connection = Initialize-OmadaSqlTestConnection
    }

    It 'Reads object id 1 by id, as every positive id is a single read' {
        Mock Invoke-OmadaSqlRequest -ModuleName 'OmadaSql.PS' { New-OmadaSqlTestODataQuery -Id 1 }
        InModuleScope 'OmadaSql.PS' {
            $null = Get-OmadaSqlQueryData -Context (Get-OmadaSqlConnectionContext) -Id 1
        }
        Should -Invoke Invoke-OmadaSqlRequest -ModuleName 'OmadaSql.PS' -Times 1 -Exactly -ParameterFilter { $Path -eq 'odata/dataobjects/C_P_SQLTROUBLESHOOTING(1)' }
    }

    It 'Returns what the OData name filter returned without filtering it again locally' {
        # The OData filter is authoritative for a name without wildcards: the server's comparison
        # rules apply, not PowerShell's -like.
        Mock Invoke-OmadaSqlRequest -ModuleName 'OmadaSql.PS' { [pscustomobject]@{ value = @(New-OmadaSqlTestODataQuery -Id 1 -Name 'Daily export (server match)') } }
        InModuleScope 'OmadaSql.PS' {
            @(Get-OmadaSqlQueryData -Context (Get-OmadaSqlConnectionContext) -Name 'Daily export').Count | Should -Be 1
        }
    }
}

Describe 'Get-OmadaSqlQueryData parameter contract' -Tag 'Unit' {
    # Parameter declarations run no code a test could observe, so the mutation gate's mutants of
    # Mandatory, Position, pipeline binding and ValidateRange are caught only by asserting the contract.
    It '<Command> -<Parameter> <ParameterSet>' -ForEach @(
        @{ Command = 'Get-OmadaSqlQueryData'; Parameter = 'Context'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
    ) {
        $Contract = Get-OmadaSqlParameterContract -CommandName $Command -ParameterName $Parameter -ParameterSetName $ParameterSet
        $Contract.Mandatory | Should -Be $Mandatory
        $Contract.Position | Should -Be $Position
        $Contract.ValueFromPipeline | Should -Be $ValueFromPipeline
        $Contract.ValueFromPipelineByPropertyName | Should -Be $ValueFromPipelineByPropertyName
        $Contract.RangeMin | Should -Be $RangeMin
        $Contract.RangeMax | Should -Be $RangeMax
    }
}
