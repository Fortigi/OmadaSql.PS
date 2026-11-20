param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaSql.PS\OmadaSql.PS.psm1')
)

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers\OmadaSqlTestHelper.ps1')
    Import-OmadaWebStub
    Get-Module -Name OmadaSql.PS -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Get-OmadaSqlValueKind' -Tag 'Unit' {
    It 'Calls <Case> a <Expected>' -ForEach @(
        @{ Case = 'null'; Value = $null; Expected = 'Null' }
        @{ Case = 'DBNull'; Value = [System.DBNull]::Value; Expected = 'Null' }
        @{ Case = 'a boolean'; Value = $false; Expected = 'Boolean' }
        @{ Case = 'a date'; Value = [datetime]::Now; Expected = 'DateTime' }
        @{ Case = 'a byte'; Value = [byte]1; Expected = 'Number' }
        @{ Case = 'an sbyte'; Value = [sbyte]-1; Expected = 'Number' }
        @{ Case = 'a short'; Value = [int16]1; Expected = 'Number' }
        @{ Case = 'an unsigned short'; Value = [uint16]1; Expected = 'Number' }
        @{ Case = 'an int'; Value = 1; Expected = 'Number' }
        @{ Case = 'an unsigned int'; Value = [uint32]1; Expected = 'Number' }
        @{ Case = 'a long'; Value = [long]1; Expected = 'Number' }
        @{ Case = 'an unsigned long'; Value = [uint64]1; Expected = 'Number' }
        @{ Case = 'a decimal'; Value = [decimal]1.5; Expected = 'Number' }
        @{ Case = 'a double'; Value = [double]1.5; Expected = 'Number' }
        @{ Case = 'a float'; Value = [single]1.5; Expected = 'Number' }
        @{ Case = 'NaN'; Value = [double]::NaN; Expected = 'String' }
        @{ Case = 'infinity'; Value = [double]::PositiveInfinity; Expected = 'String' }
        @{ Case = 'the text 42'; Value = '42'; Expected = 'Number' }
        @{ Case = 'the text -3.50'; Value = '-3.50'; Expected = 'Number' }
        @{ Case = 'the text 0'; Value = '0'; Expected = 'Number' }
        @{ Case = 'the text 007'; Value = '007'; Expected = 'String' }
        @{ Case = 'the text 1e5'; Value = '1e5'; Expected = 'String' }
        @{ Case = 'the text 1.'; Value = '1.'; Expected = 'String' }
        @{ Case = 'the text 42 with text after it'; Value = '42 x'; Expected = 'String' }
        @{ Case = 'the text x before 42'; Value = 'x42'; Expected = 'String' }
        @{ Case = 'a word'; Value = 'abc'; Expected = 'String' }
        @{ Case = 'a guid'; Value = [guid]::Empty; Expected = 'String' }
        @{ Case = 'a char'; Value = [char]'a'; Expected = 'String' }
    ) {
        InModuleScope 'OmadaSql.PS' -Parameters @{ Value = $Value } { param($Value) Get-OmadaSqlValueKind -Value $Value } | Should -Be $Expected
    }
}

Describe 'Get-OmadaSqlColumnKind' -Tag 'Unit' {
    It 'Is <Expected> for <Case>' -ForEach @(
        @{ Case = 'no values'; Value = @(); Expected = 'Null' }
        @{ Case = 'only nulls'; Value = @($null, $null); Expected = 'Null' }
        @{ Case = 'numbers and nulls'; Value = @('1', $null, 2); Expected = 'Number' }
        @{ Case = 'numbers and text'; Value = @('1', 'x'); Expected = 'String' }
        @{ Case = 'booleans'; Value = @($true, $false); Expected = 'Boolean' }
    ) {
        InModuleScope 'OmadaSql.PS' -Parameters @{ Value = $Value } { param($Value) Get-OmadaSqlColumnKind -Value $Value } | Should -Be $Expected
    }
}

Describe 'ConvertTo-OmadaSqlSqlLiteral' -Tag 'Unit' {
    It 'Writes <Case> as <Expected>' -ForEach @(
        @{ Case = 'null'; Value = $null; Kind = 'String'; Expected = 'NULL' }
        @{ Case = 'a number'; Value = '12.50'; Kind = 'Number'; Expected = '12.50' }
        @{ Case = 'a CLR number'; Value = [decimal]::Parse('3.0', [System.Globalization.CultureInfo]::InvariantCulture); Kind = 'Number'; Expected = '3.0' }
        @{ Case = 'true'; Value = $true; Kind = 'Boolean'; Expected = '1' }
        @{ Case = 'false'; Value = $false; Kind = 'Boolean'; Expected = '0' }
        @{ Case = 'a date'; Value = [datetime]::new(2026, 5, 6, 7, 8, 9); Kind = 'DateTime'; Expected = "'2026-05-06T07:08:09.000'" }
        @{ Case = 'text with a quote'; Value = "O'Brien"; Kind = 'String'; Expected = "'O''Brien'" }
        @{ Case = 'a number in a text column'; Value = '7'; Kind = 'String'; Expected = "'7'" }
        @{ Case = 'text outside ASCII'; Value = ('Caf{0}' -f [char]0xE9); Kind = 'String'; Expected = ("N'Caf{0}'" -f [char]0xE9) }
        @{ Case = 'the last ASCII character'; Value = ('a{0}' -f [char]0x7F); Kind = 'String'; Expected = ("'a{0}'" -f [char]0x7F) }
    ) {
        InModuleScope 'OmadaSql.PS' -Parameters @{ Value = $Value; Kind = $Kind } { param($Value, $Kind) ConvertTo-OmadaSqlSqlLiteral -Value $Value -Kind $Kind } | Should -BeExactly $Expected
    }
}

Describe 'ConvertTo-OmadaSqlPowerShellLiteral' -Tag 'Unit' {
    It 'Writes <Case> as <Expected>' -ForEach @(
        @{ Case = 'null'; Value = $null; Kind = 'String'; Expected = '$null' }
        @{ Case = 'a number'; Value = '-4'; Kind = 'Number'; Expected = '-4' }
        @{ Case = 'true'; Value = $true; Kind = 'Boolean'; Expected = '$true' }
        @{ Case = 'false'; Value = $false; Kind = 'Boolean'; Expected = '$false' }
        @{ Case = 'a date'; Value = [datetime]::new(2026, 5, 6); Kind = 'DateTime'; Expected = "[datetime]'2026-05-06T00:00:00.000'" }
        @{ Case = 'text with a quote'; Value = "it's"; Kind = 'String'; Expected = "'it''s'" }
        @{ Case = 'text with a typographic quote'; Value = ('it{0}s' -f [char]0x2019); Kind = 'String'; Expected = ("'it{0}{0}s'" -f [char]0x2019) }
        @{ Case = 'text with a dollar sign'; Value = '$env:X'; Kind = 'String'; Expected = "'`$env:X'" }
    ) {
        InModuleScope 'OmadaSql.PS' -Parameters @{ Value = $Value; Kind = $Kind } { param($Value, $Kind) ConvertTo-OmadaSqlPowerShellLiteral -Value $Value -Kind $Kind } | Should -BeExactly $Expected
    }
}

Describe 'ConvertTo-OmadaSqlSqlArrayText' -Tag 'Unit' {
    It 'Writes one column as a list for IN, unquoted when every value is a number' {
        $Rows = @([pscustomobject]@{ Id = '900' }, [pscustomobject]@{ Id = $null }, [pscustomobject]@{ Id = '901' })
        $Text = InModuleScope 'OmadaSql.PS' -Parameters @{ Rows = $Rows } { param($Rows) ConvertTo-OmadaSqlSqlArrayText -Row $Rows -Column @('Id') }
        $Text | Should -BeExactly "(`r`n    900,`r`n    NULL,`r`n    901`r`n)"
    }

    It 'Writes several columns as a VALUES table with bracketed names' {
        $Rows = @([pscustomobject]@{ Id = '1'; 'Odd]Name' = 'a' }, [pscustomobject]@{ Id = '2'; 'Odd]Name' = "b'c" })
        $Text = InModuleScope 'OmadaSql.PS' -Parameters @{ Rows = $Rows } { param($Rows) ConvertTo-OmadaSqlSqlArrayText -Row $Rows -Column @('Id', 'Odd]Name') }
        $Text | Should -BeExactly "(VALUES`r`n    (1, 'a'),`r`n    (2, 'b''c')`r`n) AS t ([Id], [Odd]]Name])"
    }

    It 'Quotes every value of a column with text and numbers' {
        $Rows = @([pscustomobject]@{ Code = '007' }, [pscustomobject]@{ Code = '8' })
        InModuleScope 'OmadaSql.PS' -Parameters @{ Rows = $Rows } { param($Rows) ConvertTo-OmadaSqlSqlArrayText -Row $Rows -Column @('Code') } | Should -BeExactly "(`r`n    '007',`r`n    '8'`r`n)"
    }

    It 'Writes nothing for <Case>' -ForEach @(
        @{ Case = 'no rows'; Rows = @(); Column = @('Id') }
        @{ Case = 'no columns'; Rows = @([pscustomobject]@{}); Column = @() }
    ) {
        InModuleScope 'OmadaSql.PS' -Parameters @{ Rows = $Rows; Column = $Column } { param($Rows, $Column) ConvertTo-OmadaSqlSqlArrayText -Row $Rows -Column $Column } | Should -BeExactly ''
    }
}

Describe 'ConvertTo-OmadaSqlPowerShellArrayText' -Tag 'Unit' {
    It 'Writes one column as an array' {
        $Rows = @([pscustomobject]@{ Name = 'a' }, [pscustomobject]@{ Name = $null })
        InModuleScope 'OmadaSql.PS' -Parameters @{ Rows = $Rows } { param($Rows) ConvertTo-OmadaSqlPowerShellArrayText -Row $Rows -Column @('Name') } | Should -BeExactly "@(`r`n    'a',`r`n    `$null`r`n)"
    }

    It 'Writes several columns as objects, quoting a key that is not a simple name' {
        $Rows = @([pscustomobject]@{ Id = '1'; 'Display Name' = 'x' }, [pscustomobject]@{ Id = '2'; 'Display Name' = 'y' })
        $Text = InModuleScope 'OmadaSql.PS' -Parameters @{ Rows = $Rows } { param($Rows) ConvertTo-OmadaSqlPowerShellArrayText -Row $Rows -Column @('Id', 'Display Name') }
        $Text | Should -BeExactly "@(`r`n    [PSCustomObject]@{ Id = 1; 'Display Name' = 'x' }`r`n    [PSCustomObject]@{ Id = 2; 'Display Name' = 'y' }`r`n)"
        $Value = Invoke-Expression $Text
        @($Value.'Display Name') | Should -Be @('x', 'y')
    }

    It 'Writes an empty array for <Case>' -ForEach @(
        @{ Case = 'no rows'; Rows = @(); Column = @('Id') }
        @{ Case = 'no columns'; Rows = @([pscustomobject]@{}); Column = @() }
    ) {
        InModuleScope 'OmadaSql.PS' -Parameters @{ Rows = $Rows; Column = $Column } { param($Rows, $Column) ConvertTo-OmadaSqlPowerShellArrayText -Row $Rows -Column $Column } | Should -BeExactly '@()'
    }
}

Describe 'Format-OmadaSqlPowerShellKey' -Tag 'Unit' {
    It 'Writes <Name> as <Expected>' -ForEach @(
        @{ Name = 'Id'; Expected = 'Id' }
        @{ Name = '_x1'; Expected = '_x1' }
        @{ Name = '1x'; Expected = "'1x'" }
        @{ Name = 'a-b'; Expected = "'a-b'" }
        @{ Name = "it's"; Expected = "'it''s'" }
        @{ Name = ''; Expected = "''" }
    ) {
        InModuleScope 'OmadaSql.PS' -Parameters @{ Name = $Name } { param($Name) Format-OmadaSqlPowerShellKey -Name $Name } | Should -BeExactly $Expected
    }
}

Describe 'ConvertTo-OmadaSqlArrayText parameter contract' -Tag 'Unit' {
    # Parameter declarations run no code a test could observe, so the mutation gate's mutants of
    # Mandatory, Position, pipeline binding and ValidateRange are caught only by asserting the contract.
    It '<Command> -<Parameter> <ParameterSet>' -ForEach @(
        @{ Command = 'Get-OmadaSqlColumnKind'; Parameter = 'Value'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'ConvertTo-OmadaSqlSqlLiteral'; Parameter = 'Kind'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'ConvertTo-OmadaSqlPowerShellLiteral'; Parameter = 'Kind'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Get-OmadaSqlLiteralTable'; Parameter = 'Row'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Get-OmadaSqlLiteralTable'; Parameter = 'Column'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Get-OmadaSqlLiteralTable'; Parameter = 'Language'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'ConvertTo-OmadaSqlSqlArrayText'; Parameter = 'Row'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'ConvertTo-OmadaSqlSqlArrayText'; Parameter = 'Column'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'ConvertTo-OmadaSqlPowerShellArrayText'; Parameter = 'Row'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'ConvertTo-OmadaSqlPowerShellArrayText'; Parameter = 'Column'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Format-OmadaSqlPowerShellKey'; Parameter = 'Name'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
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
