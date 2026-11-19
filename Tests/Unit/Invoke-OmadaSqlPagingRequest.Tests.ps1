param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaSql.PS\OmadaSql.PS.psm1')
)

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers\OmadaSqlTestHelper.ps1')
    Import-OmadaWebStub
    Get-Module -Name OmadaSql.PS -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $ModulePath -Force -ErrorAction Stop
}


Describe 'New-OmadaSqlPagingRequestBody' -Tag 'Unit' {
    It 'Builds the body the Omada UI sends, sorting a search by name' {
        InModuleScope 'OmadaSql.PS' {
            $Body = New-OmadaSqlPagingRequestBody -DataType 'Views' -DataTypeArgument @{ OwnerShipType = 'Both' } -SearchString 'SQL Troubleshooting'
            $Body.dataType | Should -Be 'Views'
            $Body.dataTypeArgs.OwnerShipType | Should -Be 'Both'
            $Body.searchString | Should -Be 'SQL Troubleshooting'
            $Body.sidx | Should -Be 'name'
            $Body.rows | Should -Be 1000
            $Body.page | Should -Be 1
            $Body._search | Should -BeFalse
        }
    }

    It 'Sends the current time in Unix milliseconds as nd, as the UI''s jqGrid does' {
        InModuleScope 'OmadaSql.PS' {
            $Before = [System.DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
            $Body = New-OmadaSqlPagingRequestBody -DataType 'Views' -DataTypeArgument @{}
            $After = [System.DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
            $Body.nd | Should -BeOfType [long]
            $Body.nd | Should -BeGreaterOrEqual $Before
            $Body.nd | Should -BeLessOrEqual $After
        }
    }

    It 'Uses the sort field and order when there is no search' {
        InModuleScope 'OmadaSql.PS' {
            $Body = New-OmadaSqlPagingRequestBody -DataType 'DataObjectHistory' -DataTypeArgument @{} -Rows 100000 -SortField 'when' -SortOrder 'desc'
            $Body.sidx | Should -Be 'when'
            $Body.sord | Should -Be 'desc'
            $Body.rows | Should -Be 100000
            $Body.searchString | Should -BeNullOrEmpty
        }
    }

    It 'Sends no sort field when there is neither a search nor a sort field' {
        InModuleScope 'OmadaSql.PS' {
            (New-OmadaSqlPagingRequestBody -DataType 'DataObjects' -DataTypeArgument @{}).sidx | Should -BeNullOrEmpty
        }
    }
}

Describe 'Invoke-OmadaSqlPagingRequest' -Tag 'Unit' {
    BeforeAll {
        $Script:Connection = Initialize-OmadaSqlTestConnection
    }

    It 'POSTs to GetPagingData and returns the d payload' {
        Mock Invoke-OmadaSqlRequest -ModuleName 'OmadaSql.PS' { [pscustomobject]@{ d = [pscustomobject]@{ Records = 1; Rows = @([pscustomobject]@{ Name = 'x' }) } } }
        InModuleScope 'OmadaSql.PS' {
            $Context = Get-OmadaSqlConnectionContext
            (Invoke-OmadaSqlPagingRequest -Context $Context -DataType 'Views' -DataTypeArgument @{ OwnerShipType = 'Both' }).Records | Should -Be 1
        }
        Should -Invoke Invoke-OmadaSqlRequest -ModuleName 'OmadaSql.PS' -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'POST' -and $Path -eq 'WebService/JQGridPopulationWebService.asmx/GetPagingData' -and $Body.dataType -eq 'Views'
        }
    }

    It 'Asks for 1000 rows unless told otherwise' {
        Mock Invoke-OmadaSqlRequest -ModuleName 'OmadaSql.PS' { [pscustomobject]@{ d = [pscustomobject]@{ Records = 0; Rows = @() } } }
        InModuleScope 'OmadaSql.PS' {
            $null = Invoke-OmadaSqlPagingRequest -Context (Get-OmadaSqlConnectionContext) -DataType 'Views' -DataTypeArgument @{}
        }
        Should -Invoke Invoke-OmadaSqlRequest -ModuleName 'OmadaSql.PS' -Times 1 -Exactly -ParameterFilter { $Body.rows -eq 1000 }
    }

    It 'Fails with InvalidResult when the response has no d payload' {
        Mock Invoke-OmadaSqlRequest -ModuleName 'OmadaSql.PS' { [pscustomobject]@{ other = 1 } }
        InModuleScope 'OmadaSql.PS' {
            $Context = Get-OmadaSqlConnectionContext
            { Invoke-OmadaSqlPagingRequest -Context $Context -DataType 'Views' -DataTypeArgument @{} } | Should -Throw -ErrorId 'OmadaSql.InvalidResult'
        }
    }
}

Describe 'Invoke-OmadaSqlPagingRequest parameter contract' -Tag 'Unit' {
    # Parameter declarations run no code a test could observe, so the mutation gate's mutants of
    # Mandatory, Position, pipeline binding and ValidateRange are caught only by asserting the contract.
    It '<Command> -<Parameter> <ParameterSet>' -ForEach @(
        @{ Command = 'Invoke-OmadaSqlPagingRequest'; Parameter = 'Context'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Invoke-OmadaSqlPagingRequest'; Parameter = 'DataType'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Invoke-OmadaSqlPagingRequest'; Parameter = 'DataTypeArgument'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Invoke-OmadaSqlPagingRequest'; Parameter = 'Rows'; ParameterSet = ''; Mandatory = $false; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = '1'; RangeMax = '100000' }
        @{ Command = 'New-OmadaSqlPagingRequestBody'; Parameter = 'DataType'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'New-OmadaSqlPagingRequestBody'; Parameter = 'DataTypeArgument'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
    ) {
        $Contract = Get-OmadaSqlParameterContract -CommandName $Command -ParameterName $Parameter -ParameterSetName $ParameterSet
        $Contract.Mandatory | Should -Be $Mandatory
        # Only a declared position is part of the contract: without one PowerShell numbers the
        # parameters of an advanced function in declaration order, which no mutant can change.
        if ($null -ne $Position) {
            $Contract.Position | Should -Be $Position
        }
        $Contract.ValueFromPipeline | Should -Be $ValueFromPipeline
        $Contract.ValueFromPipelineByPropertyName | Should -Be $ValueFromPipelineByPropertyName
        $Contract.RangeMin | Should -Be $RangeMin
        $Contract.RangeMax | Should -Be $RangeMax
    }
}
