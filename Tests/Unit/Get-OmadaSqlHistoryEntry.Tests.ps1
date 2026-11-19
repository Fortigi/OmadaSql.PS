param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaSql.PS\OmadaSql.PS.psm1')
)

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers\OmadaSqlTestHelper.ps1')
    Import-OmadaWebStub
    Get-Module -Name OmadaSql.PS -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $ModulePath -Force -ErrorAction Stop
}


Describe 'Get-OmadaSqlHistoryEntry' -Tag 'Unit' {
    BeforeAll {
        $Script:Connection = Initialize-OmadaSqlTestConnection
    }

    It 'Requests the DataObjectHistory of the object, newest first, and converts the rows' {
        Mock Invoke-OmadaSqlPagingRequest -ModuleName 'OmadaSql.PS' { [pscustomobject]@{ Rows = @([pscustomobject]@{ Object = 'x'; Who = 'w'; What = 'Modified'; When = '2026-11-01'; ChangedFields = '[{"Field":"Name","OldValue":"a","NewValue":"b"}]' }) } }
        InModuleScope 'OmadaSql.PS' {
            @(Get-OmadaSqlHistoryEntry -Context (Get-OmadaSqlConnectionContext) -Id 101).NewValue | Should -Be @('b')
        }
        Should -Invoke Invoke-OmadaSqlPagingRequest -ModuleName 'OmadaSql.PS' -Times 1 -Exactly -ParameterFilter {
            $DataType -eq 'DataObjectHistory' -and $DataTypeArgument.dataObjectId -eq 101 -and $DataTypeArgument.propertyId -eq 0 -and $DataTypeArgument.userId -eq 0 -and $SortField -eq 'when' -and $SortOrder -eq 'desc' -and $Rows -eq 100000
        }
    }

    It 'Returns nothing for a history without rows' {
        Mock Invoke-OmadaSqlPagingRequest -ModuleName 'OmadaSql.PS' { [pscustomobject]@{ Records = 0 } }
        InModuleScope 'OmadaSql.PS' {
            @(Get-OmadaSqlHistoryEntry -Context (Get-OmadaSqlConnectionContext) -Id 101).Count | Should -Be 0
        }
    }
}

Describe 'Get-OmadaSqlHistoryEntry parameter contract' -Tag 'Unit' {
    # Parameter declarations run no code a test could observe, so the mutation gate's mutants of
    # Mandatory, Position, pipeline binding and ValidateRange are caught only by asserting the contract.
    It '<Command> -<Parameter> <ParameterSet>' -ForEach @(
        @{ Command = 'Get-OmadaSqlHistoryEntry'; Parameter = 'Context'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Get-OmadaSqlHistoryEntry'; Parameter = 'Id'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
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
