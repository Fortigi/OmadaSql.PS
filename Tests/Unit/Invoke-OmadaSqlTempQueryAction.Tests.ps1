param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaSql.PS\OmadaSql.PS.psm1')
)

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers\OmadaSqlTestHelper.ps1')
    Import-OmadaWebStub
    Get-Module -Name OmadaSql.PS -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Get-OmadaSqlTempQueryAction' -Tag 'Unit' {
    It 'Returns <Expected> for Deleted=<Deleted>, Purge=<Purge>' -ForEach @(
        @{ Deleted = $false; Purge = $false; Expected = 'Delete' }
        @{ Deleted = $true; Purge = $false; Expected = $null }
        @{ Deleted = $false; Purge = $true; Expected = 'Delete and purge' }
        @{ Deleted = $true; Purge = $true; Expected = 'Purge' }
    ) {
        InModuleScope 'OmadaSql.PS' -Parameters @{ Deleted = $Deleted; Purge = $Purge; Expected = $Expected } {
            param($Deleted, $Purge, $Expected)
            Get-OmadaSqlTempQueryAction -Deleted $Deleted -Purge:$Purge | Should -Be $Expected
        }
    }
}

Describe 'Invoke-OmadaSqlTempQueryAction' -Tag 'Unit' {
    BeforeAll {
        $Script:Connection = Initialize-OmadaSqlTestConnection
    }

    It 'Names the required role when a purge is refused' {
        Mock Invoke-OmadaSqlRequest -ModuleName 'OmadaSql.PS' { throw ([System.Management.Automation.ErrorRecord]::new([System.Exception]::new('401'), 'OmadaSql.MissingPermission', [System.Management.Automation.ErrorCategory]::PermissionDenied, $null)) } -ParameterFilter { $Path -like '*Purge*' }
        Mock Invoke-OmadaSqlRequest -ModuleName 'OmadaSql.PS' { }
        InModuleScope 'OmadaSql.PS' {
            $Caught = $null
            try { Invoke-OmadaSqlTempQueryAction -Context (Get-OmadaSqlConnectionContext) -Item ([pscustomobject]@{ Id = 2; Name = 'TMP_a_2'; Deleted = $true }) -Purge } catch { $Caught = $_ }
            $Caught.FullyQualifiedErrorId | Should -Be 'OmadaSql.MissingPermission'
            $Caught.Exception.Message | Should -BeLike '*TMP_a_2*System, Operation or Data Administrator*'
        }
    }

    It 'Passes any other failure on unchanged' {
        Mock Invoke-OmadaSqlRequest -ModuleName 'OmadaSql.PS' { throw ([System.Management.Automation.ErrorRecord]::new([System.Exception]::new('down'), 'OmadaSql.ServerError', [System.Management.Automation.ErrorCategory]::InvalidResult, $null)) }
        InModuleScope 'OmadaSql.PS' {
            { Invoke-OmadaSqlTempQueryAction -Context (Get-OmadaSqlConnectionContext) -Item ([pscustomobject]@{ Id = 2; Name = 'TMP_a_2'; Deleted = $true }) -Purge } | Should -Throw -ErrorId 'OmadaSql.ServerError'
        }
    }
}

Describe 'Invoke-OmadaSqlTempQueryAction parameter contract' -Tag 'Unit' {
    # Parameter declarations run no code a test could observe, so the mutation gate's mutants of
    # Mandatory, Position, pipeline binding and ValidateRange are caught only by asserting the contract.
    It '<Command> -<Parameter> <ParameterSet>' -ForEach @(
        @{ Command = 'Get-OmadaSqlTempQueryAction'; Parameter = 'Deleted'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Invoke-OmadaSqlTempQueryAction'; Parameter = 'Context'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Invoke-OmadaSqlTempQueryAction'; Parameter = 'Item'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
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
