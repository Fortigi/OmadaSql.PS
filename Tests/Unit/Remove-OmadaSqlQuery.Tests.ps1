param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaSql.PS\OmadaSql.PS.psm1')
)

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers\OmadaSqlTestHelper.ps1')
    Import-OmadaWebStub
    Get-Module -Name OmadaSql.PS -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $ModulePath -Force -ErrorAction Stop
}


Describe 'Remove-OmadaSqlQuery' -Tag 'Unit' {
    BeforeEach {
        $Script:Connection = Initialize-OmadaSqlTestConnection
        Mock Invoke-OmadaSqlRequest -ModuleName 'OmadaSql.PS' { $null }
    }

    It 'DELETEs the object over OData' {
        Remove-OmadaSqlQuery -Id 7 -Confirm:$false
        Should -Invoke Invoke-OmadaSqlRequest -ModuleName 'OmadaSql.PS' -Times 1 -Exactly -ParameterFilter { $Method -eq 'DELETE' -and $Path -eq 'odata/dataobjects/C_P_SQLTROUBLESHOOTING(7)' }
    }

    It 'Deletes every piped object' {
        [pscustomobject]@{ Id = 7 }, [pscustomobject]@{ Id = 8 } | Remove-OmadaSqlQuery -Confirm:$false
        Should -Invoke Invoke-OmadaSqlRequest -ModuleName 'OmadaSql.PS' -Times 2 -Exactly
    }

    It 'Sends nothing with -WhatIf' {
        Remove-OmadaSqlQuery -Id 7 -WhatIf
        Should -Invoke Invoke-OmadaSqlRequest -ModuleName 'OmadaSql.PS' -Times 0 -Exactly
    }

    It 'Declares a medium confirm impact, as the delete can be undone' {
        (Get-Command -Name Remove-OmadaSqlQuery).ScriptBlock.Attributes.Where({ $_ -is [System.Management.Automation.CmdletBindingAttribute] })[0].ConfirmImpact | Should -Be 'Medium'
    }
}

Describe 'Remove-OmadaSqlQuery parameter contract' -Tag 'Unit' {
    # Parameter declarations run no code a test could observe, so the mutation gate's mutants of
    # Mandatory, Position, pipeline binding and ValidateRange are caught only by asserting the contract.
    It '<Command> -<Parameter> <ParameterSet>' -ForEach @(
        @{ Command = 'Remove-OmadaSqlQuery'; Parameter = 'Id'; ParameterSet = ''; Mandatory = $true; Position = 0; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $true; RangeMin = '1'; RangeMax = '9223372036854775807' }
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
