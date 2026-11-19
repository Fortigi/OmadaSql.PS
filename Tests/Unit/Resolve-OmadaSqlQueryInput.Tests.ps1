param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaSql.PS\OmadaSql.PS.psm1')
)

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers\OmadaSqlTestHelper.ps1')
    Import-OmadaWebStub
    Get-Module -Name OmadaSql.PS -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Resolve-OmadaSqlQueryInput' -Tag 'Unit' {
    It 'Keeps the parameters of a call that is not fed by the pipeline, even with an object as input' {
        InModuleScope 'OmadaSql.PS' {
            $Resolved = Resolve-OmadaSqlQueryInput -ParameterSetName 'Query' -Parameter @{ Query = 'SELECT 1'; DataConnection = 'OISES' } -InputObject ([pscustomobject]@{ Id = 7 })
            $Resolved.ParameterSetName | Should -Be 'Query'
            $Resolved.Parameter.Query | Should -Be 'SELECT 1'
            $Resolved.Parameter.DataConnection | Should -Be 'OISES'
            $Resolved.Parameter.ContainsKey('Id') | Should -BeFalse
        }
    }

    It 'Keeps a piped string as SQL text' {
        InModuleScope 'OmadaSql.PS' {
            $Resolved = Resolve-OmadaSqlQueryInput -ParameterSetName 'Query' -Parameter @{ Query = 'SELECT 1' } -InputObject 'SELECT 1' -ExpectingInput
            $Resolved.ParameterSetName | Should -Be 'Query'
            $Resolved.Parameter.Query | Should -Be 'SELECT 1'
        }
    }

    It 'Leaves another parameter set alone' {
        InModuleScope 'OmadaSql.PS' {
            $Resolved = Resolve-OmadaSqlQueryInput -ParameterSetName 'Id' -Parameter @{ Id = [long]5 } -InputObject ([pscustomobject]@{ Name = 'x' }) -ExpectingInput
            $Resolved.ParameterSetName | Should -Be 'Id'
            $Resolved.Parameter.Id | Should -Be 5
        }
    }

    It 'Runs a piped object with an <Kind> Id as that saved object and keeps the other parameters' -ForEach @(
        @{ Kind = 'int'; Value = [int]42 }
        @{ Kind = 'string'; Value = '42' }
    ) {
        InModuleScope 'OmadaSql.PS' -Parameters @{ IdValue = $Value } {
            param($IdValue)
            $Resolved = Resolve-OmadaSqlQueryInput -ParameterSetName 'Query' -Parameter @{ Query = '@{Id=42}'; DataConnection = 'OISES' } -InputObject ([pscustomobject]@{ Id = $IdValue }) -ExpectingInput
            $Resolved.ParameterSetName | Should -Be 'Id'
            $Resolved.Parameter.Id | Should -Be 42
            $Resolved.Parameter.Id.GetType() | Should -Be ([long])
            $Resolved.Parameter.ContainsKey('Query') | Should -BeFalse
            $Resolved.Parameter.DataConnection | Should -Be 'OISES'
        }
    }

    It 'Does not change the bound parameters it was given' {
        InModuleScope 'OmadaSql.PS' {
            $Bound = @{ Query = '@{Id=42}' }
            $null = Resolve-OmadaSqlQueryInput -ParameterSetName 'Query' -Parameter $Bound -InputObject ([pscustomobject]@{ Id = 42 }) -ExpectingInput
            $Bound.Query | Should -Be '@{Id=42}'
            $Bound.ContainsKey('Id') | Should -BeFalse
        }
    }

    It 'Refuses a piped <Kind> with OmadaSql.InvalidArgument' -ForEach @(
        @{ Kind = 'object without an Id'; Piped = [pscustomobject]@{ Name = 'x' }; TypeName = 'System.Management.Automation.PSCustomObject' }
        @{ Kind = 'object with Id 0'; Piped = [pscustomobject]@{ Id = 0 }; TypeName = 'System.Management.Automation.PSCustomObject' }
        @{ Kind = 'object with a negative Id'; Piped = [pscustomobject]@{ Id = -3 }; TypeName = 'System.Management.Automation.PSCustomObject' }
        @{ Kind = 'object with a non-numeric Id'; Piped = [pscustomobject]@{ Id = 'abc' }; TypeName = 'System.Management.Automation.PSCustomObject' }
        @{ Kind = 'number'; Piped = 42; TypeName = 'System.Int32' }
    ) {
        $Caught = InModuleScope 'OmadaSql.PS' -Parameters @{ PipedObject = $Piped } {
            param($PipedObject)
            try { $null = Resolve-OmadaSqlQueryInput -ParameterSetName 'Query' -Parameter @{ Query = 'x' } -InputObject $PipedObject -ExpectingInput } catch { $_ }
        }
        $Caught.FullyQualifiedErrorId | Should -Be 'OmadaSql.InvalidArgument'
        $Caught.Exception.Message | Should -BeLike ("Pipeline input of type {0} is neither SQL text*" -f $TypeName)
    }

    It 'Names a null pipeline object in the error' {
        $Caught = InModuleScope 'OmadaSql.PS' {
            try { $null = Resolve-OmadaSqlQueryInput -ParameterSetName 'Query' -Parameter @{ Query = 'x' } -InputObject $null -ExpectingInput } catch { $_ }
        }
        $Caught.Exception.Message | Should -BeLike 'Pipeline input of type null is*'
    }
}

Describe 'Get-OmadaSqlPipelineId' -Tag 'Unit' {
    It 'Returns <Expected> for <Kind>' -ForEach @(
        @{ Kind = 'a long Id'; Piped = [pscustomobject]@{ Id = [long]9 }; Expected = 9 }
        @{ Kind = 'a hashtable Id'; Piped = @{ Id = 11 }; Expected = 11 }
        @{ Kind = 'no Id'; Piped = [pscustomobject]@{ Name = 'x' }; Expected = 0 }
        @{ Kind = 'a null Id'; Piped = [pscustomobject]@{ Id = $null }; Expected = 0 }
        @{ Kind = 'a decimal Id'; Piped = [pscustomobject]@{ Id = '1.5' }; Expected = 0 }
        @{ Kind = 'null'; Piped = $null; Expected = 0 }
    ) {
        $Id = InModuleScope 'OmadaSql.PS' -Parameters @{ PipedObject = $Piped } { param($PipedObject) Get-OmadaSqlPipelineId -InputObject $PipedObject }
        $Id | Should -Be $Expected
        $Id.GetType() | Should -Be ([long])
    }
}

Describe 'Resolve-OmadaSqlQueryInput parameter contract' -Tag 'Unit' {
    # Parameter declarations run no code a test could observe, so the mutation gate's mutants of
    # Mandatory, Position, pipeline binding and ValidateRange are caught only by asserting the contract.
    It '<Command> -<Parameter> <ParameterSet>' -ForEach @(
        @{ Command = 'Resolve-OmadaSqlQueryInput'; Parameter = 'ParameterSetName'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Resolve-OmadaSqlQueryInput'; Parameter = 'Parameter'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
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
