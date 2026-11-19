param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaSql.PS\OmadaSql.PS.psm1')
)

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers\OmadaSqlTestHelper.ps1')
    Import-OmadaWebStub
    Get-Module -Name OmadaSql.PS -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Disconnect-OmadaSql' -Tag 'Unit' {
    BeforeEach {
        Disconnect-OmadaSql -All
        Mock Invoke-OmadaRestMethod -ModuleName 'OmadaSql.PS' { $null }
    }

    It 'Removes the current connection' {
        Connect-OmadaSql -Url 'https://tenant.omada.cloud'
        Disconnect-OmadaSql
        Get-OmadaSqlConnection | Should -BeNullOrEmpty
        Get-OmadaSqlConnection -All | Should -BeNullOrEmpty
    }

    It 'Removes a specific connection from the pipeline and leaves the current one when it was another' {
        $First = Connect-OmadaSql -Url 'https://one.omada.cloud' -PassThru
        $Second = Connect-OmadaSql -Url 'https://two.omada.cloud' -PassThru

        $First | Disconnect-OmadaSql

        (Get-OmadaSqlConnection).Id | Should -Be $Second.Id
        @(Get-OmadaSqlConnection -All).Count | Should -Be 1
    }

    It 'Clears the current connection when the removed one was current' {
        $null = Connect-OmadaSql -Url 'https://one.omada.cloud' -PassThru
        $Second = Connect-OmadaSql -Url 'https://two.omada.cloud' -PassThru

        Disconnect-OmadaSql -Connection $Second

        Get-OmadaSqlConnection | Should -BeNullOrEmpty
        @(Get-OmadaSqlConnection -All).Count | Should -Be 1
    }

    It 'Fails with NotConnected when there is nothing to remove' {
        { Disconnect-OmadaSql } | Should -Throw -ErrorId 'OmadaSql.NotConnected,Disconnect-OmadaSql'
    }
}

Describe 'Disconnect-OmadaSql parameter contract' -Tag 'Unit' {
    # Parameter declarations run no code a test could observe, so the mutation gate's mutants of
    # Mandatory, Position, pipeline binding and ValidateRange are caught only by asserting the contract.
    It '<Command> -<Parameter> <ParameterSet>' -ForEach @(
        @{ Command = 'Disconnect-OmadaSql'; Parameter = 'Connection'; ParameterSet = 'Connection'; Mandatory = $false; Position = $null; ValueFromPipeline = $true; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Disconnect-OmadaSql'; Parameter = 'All'; ParameterSet = 'All'; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
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
