param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaSql.PS\OmadaSql.PS.psm1')
)

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers\OmadaSqlTestHelper.ps1')
    Import-OmadaWebStub
    Get-Module -Name OmadaSql.PS -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Get-OmadaSqlExportColumn' -Tag 'Unit' {
    It 'Takes the column names of the first row, in order, from an object or a dictionary' {
        InModuleScope 'OmadaSql.PS' {
            $Column = Get-OmadaSqlExportColumn -Row @([pscustomobject]@{ B = 1; A = 2 }, [pscustomobject]@{ C = 3 })
            $Column.GetType() | Should -Be ([string[]])
            $Column | Should -Be @('B', 'A')
            Get-OmadaSqlExportColumn -Row @([ordered]@{ Z = 1; Y = 2 }) | Should -Be @('Z', 'Y')
        }
    }

    It 'Returns an empty string array without rows' {
        InModuleScope 'OmadaSql.PS' {
            $Column = Get-OmadaSqlExportColumn -Row @()
            $Column.GetType() | Should -Be ([string[]])
            $Column.Count | Should -Be 0
        }
    }
}

Describe 'Format-OmadaSqlExportValue' -Tag 'Unit' {
    It 'Writes <Case> as <Expected>' -ForEach @(
        @{ Case = 'null'; Value = $null; Expected = $null }
        @{ Case = 'DBNull'; Value = [System.DBNull]::Value; Expected = $null }
        @{ Case = 'a string'; Value = 'abc'; Expected = 'abc' }
        @{ Case = 'a date'; Value = [datetime]::new(2026, 1, 2, 3, 4, 5, 60); Expected = '2026-01-02T03:04:05.060' }
        @{ Case = 'a date with an offset'; Value = [datetimeoffset]::new(2026, 1, 2, 3, 4, 5, [timespan]::FromHours(1)); Expected = '2026-01-02T03:04:05.0000000+01:00' }
        @{ Case = 'a decimal'; Value = [decimal]'12.50'; Expected = '12.50' }
        @{ Case = 'a double'; Value = [double]0.1; Expected = '0.1' }
        @{ Case = 'a float'; Value = [single]1.5; Expected = '1.5' }
        @{ Case = 'an integer'; Value = 1234567; Expected = '1234567' }
        @{ Case = 'a boolean'; Value = $true; Expected = 'True' }
    ) {
        $Text = InModuleScope 'OmadaSql.PS' -Parameters @{ Value = $Value } { param($Value) Format-OmadaSqlExportValue -Value $Value }
        $Text | Should -BeExactly $Expected
    }

    It 'Ignores the current culture' {
        $Saved = [System.Threading.Thread]::CurrentThread.CurrentCulture
        try {
            [System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo('nl-NL')
            InModuleScope 'OmadaSql.PS' {
                Format-OmadaSqlExportValue -Value ([decimal]'1234.5') | Should -BeExactly '1234.5'
                Format-OmadaSqlExportValue -Value ([double]2.25) | Should -BeExactly '2.25'
            }
        }
        finally {
            [System.Threading.Thread]::CurrentThread.CurrentCulture = $Saved
        }
    }
}

Describe 'ConvertTo-OmadaSqlCsvText' -Tag 'Unit' {
    BeforeAll {
        $Script:Rows = @(
            [pscustomobject]@{ Id = '1'; Name = 'He said "hi"'; Note = $null }
            [pscustomobject]@{ Id = '2'; Name = "Two`r`nlines"; Note = '' }
        )
    }

    It 'Quotes every field, doubles inner quotes, keeps line breaks in a field and leaves null empty' {
        $Text = InModuleScope 'OmadaSql.PS' -Parameters @{ Rows = $Script:Rows } { param($Rows) ConvertTo-OmadaSqlCsvText -Row $Rows -Column @('Id', 'Name', 'Note') }
        $Text | Should -BeExactly ("`"Id`";`"Name`";`"Note`"`r`n`"1`";`"He said `"`"hi`"`"`";`r`n`"2`";`"Two`r`nlines`";`"`"")
    }

    It 'Uses the Delimiter option and leaves the header out with NoHeader' {
        $Text = InModuleScope 'OmadaSql.PS' -Parameters @{ Rows = $Script:Rows } { param($Rows) ConvertTo-OmadaSqlCsvText -Row @($Rows[0]) -Column @('Id', 'Note') -Option @{ Delimiter = ','; NoHeader = $true } }
        $Text | Should -BeExactly '"1",'
    }

    It 'Writes the header for a result with columns but no rows, and nothing without columns' {
        InModuleScope 'OmadaSql.PS' {
            ConvertTo-OmadaSqlCsvText -Row @() -Column @('A') | Should -BeExactly '"A"'
            ConvertTo-OmadaSqlCsvText -Row @() -Column @() | Should -BeExactly ''
        }
    }

    It 'Refuses the delimiter <Case>' -ForEach @(
        @{ Case = 'of two characters'; Delimiter = ';;' }
        @{ Case = 'that is empty'; Delimiter = '' }
        @{ Case = 'that is a double quote'; Delimiter = '"' }
        @{ Case = 'that is a line feed'; Delimiter = "`n" }
        @{ Case = 'that is a carriage return'; Delimiter = "`r" }
    ) {
        $Caught = InModuleScope 'OmadaSql.PS' -Parameters @{ Delimiter = $Delimiter } { param($Delimiter) try { $null = ConvertTo-OmadaSqlCsvText -Row @() -Column @('A') -Option @{ Delimiter = $Delimiter } } catch { $_ } }
        $Caught.FullyQualifiedErrorId | Should -Be 'OmadaSql.InvalidArgument'
        $Caught.Exception.Message | Should -BeLike 'The CSV Delimiter must be one character*'
    }

    It 'Accepts a tab as delimiter' {
        InModuleScope 'OmadaSql.PS' { ConvertTo-OmadaSqlCsvText -Row @([pscustomobject]@{ A = 1; B = 2 }) -Column @('A', 'B') -Option @{ Delimiter = "`t"; NoHeader = $true } | Should -BeExactly "`"1`"`t`"2`"" }
    }
}

Describe 'ConvertTo-OmadaSqlJsonText' -Tag 'Unit' {
    It 'Writes an array of objects in column order, with null, numbers and ISO dates' {
        $Rows = @([pscustomobject]@{ B = 'x'; A = $null; N = 5; D = [datetime]::new(2026, 3, 4, 5, 6, 7); X = [System.DBNull]::Value })
        $Text = InModuleScope 'OmadaSql.PS' -Parameters @{ Rows = $Rows } { param($Rows) ConvertTo-OmadaSqlJsonText -Row $Rows -Column @('B', 'A', 'N', 'D', 'X') }
        $Parsed = @($Text | ConvertFrom-Json)
        $Parsed.Count | Should -Be 1
        @($Parsed[0].PSObject.Properties.Name) | Should -Be @('B', 'A', 'N', 'D', 'X')
        $Parsed[0].A | Should -BeNullOrEmpty
        $Parsed[0].N | Should -Be 5
        $Text | Should -Match '"D":\s*"2026-03-04T05:06:07\.000"'
        $Text | Should -Match '"X":\s*null'
        $Text | Should -Match "`n"
    }

    It 'Writes an array for one row and for none, and one line with Compress' {
        InModuleScope 'OmadaSql.PS' {
            ConvertTo-OmadaSqlJsonText -Row @([pscustomobject]@{ A = 1 }) -Column @('A') -Option @{ Compress = $true } | Should -BeExactly '[{"A":1}]'
            ConvertTo-OmadaSqlJsonText -Row @() -Column @() -Option @{ Compress = $true } | Should -BeExactly '[]'
        }
    }
}

Describe 'ConvertTo-OmadaSqlXmlText' -Tag 'Unit' {
    It 'Writes one Field per column with its name as attribute, and marks a null value' {
        $Rows = @([pscustomobject]@{ 'Display Name' = 'A & <B>'; Missing = $null; Empty = '' })
        $Text = InModuleScope 'OmadaSql.PS' -Parameters @{ Rows = $Rows } { param($Rows) ConvertTo-OmadaSqlXmlText -Row $Rows -Column @('Display Name', 'Missing', 'Empty') }
        $Text | Should -Match '^<\?xml version="1\.0" encoding="utf-8"\?>'
        $Text | Should -Match "`r`n"
        $Xml = [xml]$Text
        $Field = @($Xml.Result.Row.Field)
        @($Field | ForEach-Object { $_.GetAttribute('Name') }) | Should -Be @('Display Name', 'Missing', 'Empty')
        $Field[0].InnerText | Should -BeExactly 'A & <B>'
        $Field[1].GetAttribute('Null') | Should -Be 'true'
        $Field[2].HasAttribute('Null') | Should -BeFalse
        $Field[2].InnerText | Should -BeExactly ''
    }

    It 'Writes an empty Result without rows' {
        $Text = InModuleScope 'OmadaSql.PS' { ConvertTo-OmadaSqlXmlText -Row @() -Column @() }
        ([xml]$Text).DocumentElement.Name | Should -Be 'Result'
        ([xml]$Text).DocumentElement.ChildNodes.Count | Should -Be 0
    }
}

Describe 'ConvertTo-OmadaSqlTableText' -Tag 'Unit' {
    It 'Pads columns to the widest value, right-aligns numbers and leaves the last column unpadded' {
        $Rows = @(
            [pscustomobject]@{ Id = '7'; Name = 'Users'; Note = 'x' }
            [pscustomobject]@{ Id = '1200'; Name = $null; Note = "a`tb`r`nc" }
        )
        $Text = InModuleScope 'OmadaSql.PS' -Parameters @{ Rows = $Rows } { param($Rows) ConvertTo-OmadaSqlTableText -Row $Rows -Column @('Id', 'Name', 'Note') }
        $Text | Should -BeExactly ("  Id Name  Note`r`n---- ----- -----`r`n   7 Users x`r`n1200 NULL  a b c")
    }

    It 'Left-aligns a column with text and a number' {
        $Rows = @([pscustomobject]@{ A = '1'; B = 'z' }, [pscustomobject]@{ A = 'x'; B = 'z' })
        $Text = InModuleScope 'OmadaSql.PS' -Parameters @{ Rows = $Rows } { param($Rows) ConvertTo-OmadaSqlTableText -Row $Rows -Column @('A', 'B') }
        $Text | Should -BeExactly "A B`r`n- -`r`n1 z`r`nx z"
    }

    It 'Writes the header for no rows and nothing without columns' {
        InModuleScope 'OmadaSql.PS' {
            ConvertTo-OmadaSqlTableText -Row @() -Column @('Id', 'Name') | Should -BeExactly "Id Name`r`n-- ----"
            ConvertTo-OmadaSqlTableText -Row @() -Column @() | Should -BeExactly ''
        }
    }
}

Describe 'ConvertTo-OmadaSqlExportText parameter contract' -Tag 'Unit' {
    # Parameter declarations run no code a test could observe, so the mutation gate's mutants of
    # Mandatory, Position, pipeline binding and ValidateRange are caught only by asserting the contract.
    It '<Command> -<Parameter> <ParameterSet>' -ForEach @(
        @{ Command = 'Get-OmadaSqlExportColumn'; Parameter = 'Row'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Get-OmadaSqlExportCell'; Parameter = 'Row'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Get-OmadaSqlExportCell'; Parameter = 'Column'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'ConvertTo-OmadaSqlCsvText'; Parameter = 'Row'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'ConvertTo-OmadaSqlCsvText'; Parameter = 'Column'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Get-OmadaSqlCsvDelimiter'; Parameter = 'Option'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'ConvertTo-OmadaSqlJsonText'; Parameter = 'Row'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'ConvertTo-OmadaSqlJsonText'; Parameter = 'Column'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'ConvertTo-OmadaSqlXmlText'; Parameter = 'Row'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'ConvertTo-OmadaSqlXmlText'; Parameter = 'Column'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Write-OmadaSqlXmlField'; Parameter = 'Writer'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Write-OmadaSqlXmlField'; Parameter = 'Name'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'ConvertTo-OmadaSqlTableText'; Parameter = 'Row'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'ConvertTo-OmadaSqlTableText'; Parameter = 'Column'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'New-OmadaSqlTableColumn'; Parameter = 'Row'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'New-OmadaSqlTableColumn'; Parameter = 'Name'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Join-OmadaSqlTableLine'; Parameter = 'Layout'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Join-OmadaSqlTableLine'; Parameter = 'Cell'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
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
