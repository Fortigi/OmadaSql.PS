param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaSql.PS\OmadaSql.PS.psm1')
)

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers\OmadaSqlTestHelper.ps1')
    Import-OmadaWebStub
    Get-Module -Name OmadaSql.PS -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Get-OmadaSqlScriptDomPath' -Tag 'Unit' {
    It 'Picks the <Framework> build for <Edition>' -ForEach @(
        @{ Edition = 'Desktop'; Framework = 'net472' }
        @{ Edition = 'Core'; Framework = 'net8.0' }
    ) {
        InModuleScope 'OmadaSql.PS' -Parameters @{ Edition = $Edition; Framework = $Framework } {
            param($Edition, $Framework)
            $Expected = [System.IO.Path]::Combine('C:\Modules\OmadaSql.PS', 'lib', $Framework, 'Microsoft.SqlServer.TransactSql.ScriptDom.dll')
            Get-OmadaSqlScriptDomPath -ModuleRoot 'C:\Modules\OmadaSql.PS' -Edition $Edition | Should -Be $Expected
        }
    }
}

Describe 'Import-OmadaSqlScriptDom' -Tag 'Unit' {
    It 'Loads the bundled parser and returns its assembly' {
        InModuleScope 'OmadaSql.PS' {
            $Assembly = Import-OmadaSqlScriptDom
            $Assembly.GetName().Name | Should -Be 'Microsoft.SqlServer.TransactSql.ScriptDom'
            (Get-OmadaSqlLoadedScriptDom).FullName | Should -Be $Assembly.FullName
        }
    }

    It 'Does not load a second copy when the parser is already loaded' {
        InModuleScope 'OmadaSql.PS' {
            $null = Import-OmadaSqlScriptDom
            Mock Add-Type { throw 'must not load again' }
            { Import-OmadaSqlScriptDom } | Should -Not -Throw
            Should -Invoke Add-Type -Times 0 -Exactly
        }
    }

    It 'Fails with ParserUnavailable, naming the path, when the bundled file is missing' {
        InModuleScope 'OmadaSql.PS' -Parameters @{ Root = $TestDrive } {
            param($Root)
            Mock Get-OmadaSqlLoadedScriptDom { $null }
            $Previous = $Script:OmadaSqlModuleRoot
            $Script:OmadaSqlModuleRoot = $Root
            try {
                $Caught = $null
                try { Import-OmadaSqlScriptDom } catch { $Caught = $_ }
                $Caught.FullyQualifiedErrorId | Should -Be 'OmadaSql.ParserUnavailable'
                $Caught.Exception.Message | Should -BeLike ('*not found at*{0}*' -f $Root)
            }
            finally {
                $Script:OmadaSqlModuleRoot = $Previous
            }
        }
    }

    It 'Fails with ParserUnavailable and keeps the cause when the file cannot be loaded' {
        InModuleScope 'OmadaSql.PS' {
            Mock Get-OmadaSqlLoadedScriptDom { $null }
            Mock Test-Path { $true }
            Mock Add-Type { throw [System.BadImageFormatException]::new('bad image') }
            $Caught = $null
            try { Import-OmadaSqlScriptDom } catch { $Caught = $_ }
            $Caught.FullyQualifiedErrorId | Should -Be 'OmadaSql.ParserUnavailable'
            $Caught.Exception.Message | Should -BeLike '*could not be loaded: bad image*'
            $Caught.Exception.InnerException | Should -BeOfType [System.BadImageFormatException]
        }
    }
}

Describe 'Import-OmadaSqlScriptDom parameter contract' -Tag 'Unit' {
    # Parameter declarations run no code a test could observe, so the mutation gate's mutants of
    # Mandatory, Position, pipeline binding and ValidateRange are caught only by asserting the contract.
    It '<Command> -<Parameter> <ParameterSet>' -ForEach @(
        @{ Command = 'Get-OmadaSqlScriptDomPath'; Parameter = 'ModuleRoot'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Get-OmadaSqlScriptDomPath'; Parameter = 'Edition'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
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
