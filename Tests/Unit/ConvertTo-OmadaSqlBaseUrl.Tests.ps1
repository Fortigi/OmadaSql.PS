param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaSql.PS\OmadaSql.PS.psm1')
)

BeforeAll {
    Get-Module -Name OmadaSql.PS -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'ConvertTo-OmadaSqlBaseUrl' -Tag 'Unit' {
    It 'Returns <Expected> for <Url>' -ForEach @(
        @{ Url = 'https://tenant.omada.cloud'; Expected = 'https://tenant.omada.cloud' }
        @{ Url = 'https://tenant.omada.cloud/'; Expected = 'https://tenant.omada.cloud' }
        @{ Url = ' https://tenant.omada.cloud/odata/dataobjects/identity?$top=1 '; Expected = 'https://tenant.omada.cloud' }
        @{ Url = 'https://omada.contoso.com:8443/home'; Expected = 'https://omada.contoso.com:8443' }
    ) {
        InModuleScope 'OmadaSql.PS' -Parameters @{ Url = $Url; Expected = $Expected } {
            param($Url, $Expected)
            ConvertTo-OmadaSqlBaseUrl -Url $Url | Should -Be $Expected
        }
    }

    It 'Refuses http' {
        InModuleScope 'OmadaSql.PS' {
            { ConvertTo-OmadaSqlBaseUrl -Url 'http://tenant.omada.cloud' } | Should -Throw -ErrorId 'OmadaSql.InvalidArgument'
        }
    }

    It 'Refuses a value that is not an absolute URL' {
        InModuleScope 'OmadaSql.PS' {
            { ConvertTo-OmadaSqlBaseUrl -Url 'tenant.omada.cloud' } | Should -Throw -ErrorId 'OmadaSql.InvalidArgument'
        }
    }
}

Describe 'ConvertTo-OmadaSqlBaseUrl parameter contract' -Tag 'Unit' {
    # Parameter declarations run no code a test could observe, so the mutation gate's mutants of
    # Mandatory, Position, pipeline binding and ValidateRange are caught only by asserting the contract.
    It '<Command> -<Parameter> <ParameterSet>' -ForEach @(
        @{ Command = 'ConvertTo-OmadaSqlBaseUrl'; Parameter = 'Url'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
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
