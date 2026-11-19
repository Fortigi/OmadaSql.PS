param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaSql.PS\OmadaSql.PS.psm1')
)

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers\OmadaSqlTestHelper.ps1')
    Import-OmadaWebStub
    Get-Module -Name OmadaSql.PS -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Invoke-OmadaSqlProducer' -Tag 'Unit' {
    BeforeAll {
        $Script:Connection = Initialize-OmadaSqlTestConnection
    }

    It 'Executes the object through SqlDataProducer with one page of 100000 rows and returns the rows' {
        Mock Invoke-OmadaSqlPagingRequest -ModuleName 'OmadaSql.PS' { [pscustomobject]@{ Records = 2; Rows = @([pscustomobject]@{ a = 1 }, [pscustomobject]@{ a = 2 }) } }
        $Rows = InModuleScope 'OmadaSql.PS' { Invoke-OmadaSqlProducer -Context (Get-OmadaSqlConnectionContext) -Id 55 }
        @($Rows.a) | Should -Be @(1, 2)
        Should -Invoke Invoke-OmadaSqlPagingRequest -ModuleName 'OmadaSql.PS' -Times 1 -Exactly -ParameterFilter { $DataType -eq 'SqlDataProducer' -and $DataTypeArgument.targetId -eq 55 -and $Rows -eq 100000 }
    }

    It 'Returns an empty array for a result without rows' {
        Mock Invoke-OmadaSqlPagingRequest -ModuleName 'OmadaSql.PS' { [pscustomobject]@{ Records = 0; Rows = @() } }
        InModuleScope 'OmadaSql.PS' {
            $Rows = Invoke-OmadaSqlProducer -Context (Get-OmadaSqlConnectionContext) -Id 55
            $Rows.GetType() | Should -Be ([object[]])
            $Rows.Count | Should -Be 0
        }
    }

    It 'Accepts a page without a record count' {
        Mock Invoke-OmadaSqlPagingRequest -ModuleName 'OmadaSql.PS' { [pscustomobject]@{ Rows = @([pscustomobject]@{ a = 1 }) } }
        InModuleScope 'OmadaSql.PS' { @(Invoke-OmadaSqlProducer -Context (Get-OmadaSqlConnectionContext) -Id 55).Count | Should -Be 1 }
    }

    It 'Refuses a result larger than the rows returned instead of truncating it' {
        Mock Invoke-OmadaSqlPagingRequest -ModuleName 'OmadaSql.PS' { [pscustomobject]@{ Records = 2; Rows = @([pscustomobject]@{ a = 1 }) } }
        InModuleScope 'OmadaSql.PS' {
            $Caught = $null
            try { $null = Invoke-OmadaSqlProducer -Context (Get-OmadaSqlConnectionContext) -Id 55 } catch { $Caught = $_ }
            $Caught.FullyQualifiedErrorId | Should -Be 'OmadaSql.InvalidResult'
            $Caught.Exception.Message | Should -BeLike '*matched 2 rows and Omada returned 1*'
        }
    }
}

Describe 'Invoke-OmadaSqlProducer parameter contract' -Tag 'Unit' {
    # Parameter declarations run no code a test could observe, so the mutation gate's mutants of
    # Mandatory, Position, pipeline binding and ValidateRange are caught only by asserting the contract.
    It '<Command> -<Parameter> <ParameterSet>' -ForEach @(
        @{ Command = 'Invoke-OmadaSqlProducer'; Parameter = 'Context'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Invoke-OmadaSqlProducer'; Parameter = 'Id'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
    ) {
        $Contract = Get-OmadaSqlParameterContract -CommandName $Command -ParameterName $Parameter -ParameterSetName $ParameterSet
        $Contract.Mandatory | Should -Be $Mandatory
        if ($null -ne $Position) {
            $Contract.Position | Should -Be $Position
        }
        $Contract.ValueFromPipeline | Should -Be $ValueFromPipeline
        $Contract.ValueFromPipelineByPropertyName | Should -Be $ValueFromPipelineByPropertyName
        $Contract.RangeMin | Should -Be $RangeMin
        $Contract.RangeMax | Should -Be $RangeMax
    }
}
