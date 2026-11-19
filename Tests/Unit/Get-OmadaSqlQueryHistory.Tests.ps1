param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaSql.PS\OmadaSql.PS.psm1')
)

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers\OmadaSqlTestHelper.ps1')
    Import-OmadaWebStub
    Get-Module -Name OmadaSql.PS -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $ModulePath -Force -ErrorAction Stop
}


Describe 'Get-OmadaSqlQueryHistory' -Tag 'Unit' {
    BeforeAll {
        $Script:Connection = Initialize-OmadaSqlTestConnection
        Mock Get-OmadaSqlHistoryEntry -ModuleName 'OmadaSql.PS' {
            [pscustomobject]@{ Id = $Id; Field = 'SQL Query'; NewValue = 'q' }
            [pscustomobject]@{ Id = $Id; Field = 'Name'; NewValue = 'n' }
            [pscustomobject]@{ Id = $Id; Field = $null; NewValue = $null }
        }
    }

    It 'Returns every entry by default' {
        @(Get-OmadaSqlQueryHistory -Id 101).Count | Should -Be 3
    }

    It 'Narrows to the given fields' {
        @(Get-OmadaSqlQueryHistory -Id 101 -Field 'SQL*').NewValue | Should -Be @('q')
    }

    It 'Takes the id from the pipeline' {
        @([pscustomobject]@{ Id = 7 }, [pscustomobject]@{ Id = 8 } | Get-OmadaSqlQueryHistory -Field 'Name').Id | Should -Be @(7, 8)
    }
}

Describe 'Get-OmadaSqlQueryHistory parameter contract' -Tag 'Unit' {
    # Parameter declarations run no code a test could observe, so the mutation gate's mutants of
    # Mandatory, Position, pipeline binding and ValidateRange are caught only by asserting the contract.
    It '<Command> -<Parameter> <ParameterSet>' -ForEach @(
        @{ Command = 'Get-OmadaSqlQueryHistory'; Parameter = 'Id'; ParameterSet = ''; Mandatory = $true; Position = 0; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $true; RangeMin = '1'; RangeMax = '9223372036854775807' }
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
