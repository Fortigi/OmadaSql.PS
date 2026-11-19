param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaSql.PS\OmadaSql.PS.psm1')
)

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers\OmadaSqlTestHelper.ps1')
    Import-OmadaWebStub
    Get-Module -Name OmadaSql.PS -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $ModulePath -Force -ErrorAction Stop
}


Describe 'ConvertTo-OmadaSqlODataFilter' -Tag 'Unit' {
    It 'Quotes a string value and percent-encodes the expression' {
        InModuleScope 'OmadaSql.PS' {
            ConvertTo-OmadaSqlODataFilter -Equal ([ordered]@{ NAME = 'Daily export' }) | Should -Be ('$filter=' + [System.Uri]::EscapeDataString("NAME eq 'Daily export'"))
        }
    }

    It 'Doubles a single quote, the OData escape, so the name stays data' {
        InModuleScope 'OmadaSql.PS' {
            $Filter = ConvertTo-OmadaSqlODataFilter -Equal ([ordered]@{ NAME = "O'Brien & Co #1" })
            [System.Uri]::UnescapeDataString($Filter) | Should -Be "`$filter=NAME eq 'O''Brien & Co #1'"
            $Filter | Should -Not -Match '[&#]'
        }
    }

    It 'Writes booleans in lower case and numbers as they are, joined with and' {
        InModuleScope 'OmadaSql.PS' {
            [System.Uri]::UnescapeDataString((ConvertTo-OmadaSqlODataFilter -Equal ([ordered]@{ Deleted = $false; Id = 42 }) -Raw 'NAME ne null')) |
                Should -Be '$filter=Deleted eq false and Id eq 42 and NAME ne null'
        }
    }
}

Describe 'ConvertTo-OmadaSqlODataFilter parameter contract' -Tag 'Unit' {
    # Parameter declarations run no code a test could observe, so the mutation gate's mutants of
    # Mandatory, Position, pipeline binding and ValidateRange are caught only by asserting the contract.
    It '<Command> -<Parameter> <ParameterSet>' -ForEach @(
        @{ Command = 'ConvertTo-OmadaSqlODataFilter'; Parameter = 'Equal'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
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
