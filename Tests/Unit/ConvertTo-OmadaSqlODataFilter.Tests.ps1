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
