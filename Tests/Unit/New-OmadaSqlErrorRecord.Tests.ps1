param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaSql.PS\OmadaSql.PS.psm1')
)

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers\OmadaSqlTestHelper.ps1')
    Get-Module -Name OmadaSql.PS -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $ModulePath -Force -ErrorAction Stop
    $Script:ODataUri = 'https://tenant.omada.cloud/odata/dataobjects/C_P_SQLTROUBLESHOOTING'
}

Describe 'New-OmadaSqlErrorRecord' -Tag 'Unit' {
    It 'Uses OmadaSql.<Kind> as the error id and maps <Kind> to <Category>' -ForEach @(
        @{ Kind = 'NotConnected'; Category = 'ConnectionError' }
        @{ Kind = 'MissingPermission'; Category = 'PermissionDenied' }
        @{ Kind = 'SessionExpired'; Category = 'AuthenticationError' }
        @{ Kind = 'NotFound'; Category = 'ObjectNotFound' }
        @{ Kind = 'ServerError'; Category = 'InvalidResult' }
        @{ Kind = 'EndpointNotEnabled'; Category = 'NotEnabled' }
        @{ Kind = 'AccessDenied'; Category = 'PermissionDenied' }
        @{ Kind = 'InvalidArgument'; Category = 'InvalidArgument' }
        @{ Kind = 'ParserUnavailable'; Category = 'ResourceUnavailable' }
        @{ Kind = 'ValidationFailed'; Category = 'InvalidData' }
        @{ Kind = 'Busy'; Category = 'ResourceBusy' }
    ) {
        InModuleScope 'OmadaSql.PS' -Parameters @{ Kind = $Kind; Category = $Category } {
            param($Kind, $Category)
            $Record = New-OmadaSqlErrorRecord -Kind $Kind -Message 'message'
            $Record.FullyQualifiedErrorId | Should -Be "OmadaSql.$Kind"
            [string]$Record.CategoryInfo.Category | Should -Be $Category
            $Record.Exception.Message | Should -Be 'message'
        }
    }

    It 'Keeps the original exception as the inner exception' {
        InModuleScope 'OmadaSql.PS' {
            $Inner = [System.Exception]::new('original')
            (New-OmadaSqlErrorRecord -Kind 'ServerError' -Message 'wrapped' -InnerException $Inner).Exception.InnerException.Message | Should -Be 'original'
        }
    }
}

Describe 'New-OmadaSqlErrorRecord parameter contract' -Tag 'Unit' {
    # Parameter declarations run no code a test could observe, so the mutation gate's mutants of
    # Mandatory, Position, pipeline binding and ValidateRange are caught only by asserting the contract.
    It '<Command> -<Parameter> <ParameterSet>' -ForEach @(
        @{ Command = 'New-OmadaSqlErrorRecord'; Parameter = 'Kind'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'New-OmadaSqlErrorRecord'; Parameter = 'Message'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
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
