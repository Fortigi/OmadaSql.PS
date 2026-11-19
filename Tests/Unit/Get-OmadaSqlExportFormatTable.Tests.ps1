param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaSql.PS\OmadaSql.PS.psm1')
)

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers\OmadaSqlTestHelper.ps1')
    Import-OmadaWebStub
    Get-Module -Name OmadaSql.PS -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Get-OmadaSqlExportFormatTable' -Tag 'Unit' {
    BeforeEach {
        InModuleScope 'OmadaSql.PS' { $Script:OmadaSqlExportFormat = $null }
    }

    It 'Holds the built-in formats, by name in any case, once' {
        InModuleScope 'OmadaSql.PS' {
            $Table = Get-OmadaSqlExportFormatTable
            @($Table.Keys | Sort-Object) | Should -Be @('Csv', 'Json', 'PowerShellArray', 'SqlArray', 'Text', 'Xml')
            $Table['csv'].Name | Should -Be 'Csv'
            [object]::ReferenceEquals($Table, (Get-OmadaSqlExportFormatTable)) | Should -BeTrue
        }
    }

    It 'Describes the built-in <Name> format' -ForEach @(
        @{ Name = 'Csv'; Extension = '.csv'; Option = @('Delimiter', 'NoHeader') }
        @{ Name = 'Json'; Extension = '.json'; Option = @('Compress') }
        @{ Name = 'Xml'; Extension = '.xml'; Option = @() }
        @{ Name = 'Text'; Extension = '.txt'; Option = @() }
        @{ Name = 'SqlArray'; Extension = '.sql'; Option = @() }
        @{ Name = 'PowerShellArray'; Extension = '.ps1'; Option = @() }
    ) {
        $Format = InModuleScope 'OmadaSql.PS' -Parameters @{ Name = $Name } { param($Name) (Get-OmadaSqlExportFormatTable)[$Name] }
        $Format.PSObject.TypeNames[0] | Should -Be 'OmadaSql.ExportFormat'
        $Format.Extension | Should -Be $Extension
        @($Format.Option) | Should -Be $Option
        $Format.BuiltIn | Should -BeTrue
        $Format.Description | Should -Not -BeNullOrEmpty
    }

    It 'Writes with the <Name> format' -ForEach @(
        @{ Name = 'Csv'; Expected = "`"A`"`r`n`"1`"" }
        @{ Name = 'Json'; Expected = '[{"A":"1"}]' }
        @{ Name = 'Text'; Expected = "A`r`n-`r`n1" }
        @{ Name = 'SqlArray'; Expected = "(`r`n    1`r`n)" }
        @{ Name = 'PowerShellArray'; Expected = "@(`r`n    1`r`n)" }
    ) {
        $Text = InModuleScope 'OmadaSql.PS' -Parameters @{ Name = $Name } {
            param($Name)
            $Option = if ($Name -eq 'Json') { @{ Compress = $true } } else { @{} }
            & (Get-OmadaSqlExportFormatTable)[$Name].ScriptBlock @([pscustomobject]@{ A = '1' }) ([string[]]@('A')) $Option
        }
        $Text | Should -BeExactly $Expected
    }

    It 'Writes with the Xml format' {
        $Text = InModuleScope 'OmadaSql.PS' { & (Get-OmadaSqlExportFormatTable)['Xml'].ScriptBlock @([pscustomobject]@{ A = '1' }) ([string[]]@('A')) @{} }
        ([xml]$Text).Result.Row.Field.InnerText | Should -Be '1'
    }
}

Describe 'Resolve-OmadaSqlExportFormat' -Tag 'Unit' {
    BeforeEach {
        InModuleScope 'OmadaSql.PS' { $Script:OmadaSqlExportFormat = $null }
    }

    It 'Takes -Format by name in any case' {
        InModuleScope 'OmadaSql.PS' { (Resolve-OmadaSqlExportFormat -Format 'json' -Path 'x.csv').Name | Should -Be 'Json' }
    }

    It 'Takes the format of the -Path extension: <Path>' -ForEach @(
        @{ Path = 'C:\out\a.csv'; Expected = 'Csv' }
        @{ Path = 'a.JSON'; Expected = 'Json' }
        @{ Path = 'a.xml'; Expected = 'Xml' }
        @{ Path = 'a.txt'; Expected = 'Text' }
        @{ Path = 'a.sql'; Expected = 'SqlArray' }
        @{ Path = 'a.ps1'; Expected = 'PowerShellArray' }
    ) {
        InModuleScope 'OmadaSql.PS' -Parameters @{ Path = $Path } { param($Path) (Resolve-OmadaSqlExportFormat -Path $Path).Name } | Should -Be $Expected
    }

    It 'Uses Csv without -Format and -Path' {
        InModuleScope 'OmadaSql.PS' { (Resolve-OmadaSqlExportFormat).Name | Should -Be 'Csv' }
    }

    It 'Prefers a built-in format over a registered one with the same extension' {
        InModuleScope 'OmadaSql.PS' {
            $Table = Get-OmadaSqlExportFormatTable
            $Table['Acsv'] = New-OmadaSqlExportFormat -Name 'Acsv' -Extension '.csv' -ScriptBlock { 'x' }
            $Table['Md'] = New-OmadaSqlExportFormat -Name 'Md' -Extension '.md' -ScriptBlock { 'x' }
            $Table['None'] = New-OmadaSqlExportFormat -Name 'None' -Extension '' -ScriptBlock { 'x' }
            (Resolve-OmadaSqlExportFormat -Path 'a.csv').Name | Should -Be 'Csv'
            (Resolve-OmadaSqlExportFormat -Path 'a.md').Name | Should -Be 'Md'
        }
    }

    It 'Refuses <Case>' -ForEach @(
        @{ Case = 'an unknown format'; Format = 'Excel'; Path = $null; Message = "Unknown export format 'Excel'. Known formats: Csv, Json, PowerShellArray, SqlArray, Text, Xml." }
        @{ Case = 'an unknown extension'; Format = $null; Path = 'a.xlsx'; Message = "No export format has the extension '.xlsx'. Use -Format; known formats: Csv, Json, PowerShellArray, SqlArray, Text, Xml." }
        @{ Case = 'a path without extension'; Format = $null; Path = 'out'; Message = "No export format has the extension ''. Use -Format; known formats: Csv, Json, PowerShellArray, SqlArray, Text, Xml." }
    ) {
        $Caught = InModuleScope 'OmadaSql.PS' -Parameters @{ Format = $Format; Path = $Path } { param($Format, $Path) try { $null = Resolve-OmadaSqlExportFormat -Format $Format -Path $Path } catch { $_ } }
        $Caught.FullyQualifiedErrorId | Should -Be 'OmadaSql.InvalidArgument'
        $Caught.Exception.Message | Should -BeExactly $Message
    }
}

Describe 'Assert-OmadaSqlExportOption' -Tag 'Unit' {
    It 'Accepts the options a format knows, in any case, and no options' {
        InModuleScope 'OmadaSql.PS' {
            $Format = New-OmadaSqlExportFormat -Name 'Csv' -Extension '.csv' -Option 'Delimiter' -ScriptBlock { }
            { Assert-OmadaSqlExportOption -Format $Format -Option @{ delimiter = ';' } } | Should -Not -Throw
            { Assert-OmadaSqlExportOption -Format $Format -Option $null } | Should -Not -Throw
            { Assert-OmadaSqlExportOption -Format $Format -Option @{} } | Should -Not -Throw
        }
    }

    It 'Refuses an option the format does not know, naming the ones it does' {
        $Caught = InModuleScope 'OmadaSql.PS' {
            $Format = New-OmadaSqlExportFormat -Name 'Csv' -Extension '.csv' -Option 'Delimiter', 'NoHeader' -ScriptBlock { }
            try { Assert-OmadaSqlExportOption -Format $Format -Option @{ Delimitor = ';' } } catch { $_ }
        }
        $Caught.FullyQualifiedErrorId | Should -Be 'OmadaSql.InvalidArgument'
        $Caught.Exception.Message | Should -BeExactly "The Csv format has no option 'Delimitor'. Options: Delimiter, NoHeader."
    }

    It 'Says a format has no options' {
        $Caught = InModuleScope 'OmadaSql.PS' {
            $Format = New-OmadaSqlExportFormat -Name 'Xml' -Extension '.xml' -ScriptBlock { }
            try { Assert-OmadaSqlExportOption -Format $Format -Option @{ Indent = $true } } catch { $_ }
        }
        $Caught.Exception.Message | Should -BeExactly "The Xml format has no option 'Indent'. Options: none."
    }
}

Describe 'New-OmadaSqlExportFormat' -Tag 'Unit' {
    It 'Builds a format that is not built in by default' {
        $Format = InModuleScope 'OmadaSql.PS' { New-OmadaSqlExportFormat -Name 'Md' -Extension '.md' -ScriptBlock { 'x' } }
        $Format.BuiltIn | Should -BeFalse
        $Format.Description | Should -Be ''
        @($Format.Option).Count | Should -Be 0
        & $Format.ScriptBlock | Should -Be 'x'
    }
}

Describe 'Get-OmadaSqlExportFormatTable parameter contract' -Tag 'Unit' {
    # Parameter declarations run no code a test could observe, so the mutation gate's mutants of
    # Mandatory, Position, pipeline binding and ValidateRange are caught only by asserting the contract.
    It '<Command> -<Parameter> <ParameterSet>' -ForEach @(
        @{ Command = 'New-OmadaSqlExportFormat'; Parameter = 'Name'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'New-OmadaSqlExportFormat'; Parameter = 'Extension'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'New-OmadaSqlExportFormat'; Parameter = 'ScriptBlock'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Assert-OmadaSqlExportOption'; Parameter = 'Format'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
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
