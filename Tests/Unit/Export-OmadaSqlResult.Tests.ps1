param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaSql.PS\OmadaSql.PS.psm1')
)

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers\OmadaSqlTestHelper.ps1')
    Import-OmadaWebStub
    Get-Module -Name OmadaSql.PS -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Export-OmadaSqlResult' -Tag 'Unit' {
    BeforeEach {
        InModuleScope 'OmadaSql.PS' { $Script:OmadaSqlExportFormat = $null }
        $Script:Rows = @([pscustomobject]@{ Id = '1'; Name = 'a' }, [pscustomobject]@{ Id = '2'; Name = 'b' })
    }

    It 'Returns CSV text for piped rows without -Format or -Path' {
        $Script:Rows | Export-OmadaSqlResult | Should -BeExactly "`"Id`",`"Name`"`r`n`"1`",`"a`"`r`n`"2`",`"b`""
    }

    It 'Takes rows from -InputObject as one value' {
        Export-OmadaSqlResult -InputObject $Script:Rows[0] -Format Json -Option @{ Compress = $true } | Should -BeExactly '[{"Id":"1","Name":"a"}]'
    }

    It 'Takes the format as the first positional parameter and passes the options' {
        $Script:Rows | Export-OmadaSqlResult Csv -Option @{ Delimiter = ';'; NoHeader = $true } | Should -BeExactly "`"1`";`"a`"`r`n`"2`";`"b`""
    }

    It 'Skips null input' {
        @($null, $Script:Rows[0], $null) | Export-OmadaSqlResult -Format SqlArray | Should -BeExactly "(VALUES`r`n    (1, 'a')`r`n) AS t ([Id], [Name])"
    }

    It 'Exports the rows of one statement result' {
        $Result = [pscustomobject]@{ PSTypeName = 'OmadaSql.StatementResult'; Ordinal = 1; Rows = $Script:Rows }
        $Result | Export-OmadaSqlResult -Format Text | Should -BeExactly "Id Name`r`n-- ----`r`n 1 a`r`n 2 b"
    }

    It 'Exports a statement result without rows' {
        $Result = [pscustomobject]@{ PSTypeName = 'OmadaSql.StatementResult'; Ordinal = 1; Rows = @() }
        $Result | Export-OmadaSqlResult -Format PowerShellArray | Should -BeExactly '@()'
    }

    It 'Refuses more than one statement result' {
        $Result = @(
            [pscustomobject]@{ PSTypeName = 'OmadaSql.StatementResult'; Ordinal = 1; Rows = $Script:Rows }
            [pscustomobject]@{ PSTypeName = 'OmadaSql.StatementResult'; Ordinal = 2; Rows = $Script:Rows }
        )
        { $Result | Export-OmadaSqlResult -ErrorAction Stop } | Should -Throw -ErrorId 'OmadaSql.InvalidArgument,Export-OmadaSqlResult'
        try { $Result | Export-OmadaSqlResult } catch { $_.Exception.Message | Should -BeLike 'Export one statement result at a time; 2 were piped in.*' }
    }

    It 'Writes -Path in the format of its extension, relative to the current location, and returns nothing' {
        Push-Location -LiteralPath $TestDrive
        try {
            $Output = @($Script:Rows | Export-OmadaSqlResult -Path 'out.json')
            $Output.Count | Should -Be 0
            $Text = [System.IO.File]::ReadAllText((Join-Path $TestDrive 'out.json'))
            @($Text | ConvertFrom-Json).Id | Should -Be @('1', '2')
            $Text | Should -Match "`r`n$"
        }
        finally {
            Pop-Location
        }
    }

    It 'Returns the file with -PassThru and writes a byte order mark with -Encoding UTF8BOM' {
        $Path = Join-Path $TestDrive 'bom.csv'
        $File = $Script:Rows | Export-OmadaSqlResult -Path $Path -Encoding UTF8BOM -PassThru
        $File | Should -BeOfType ([System.IO.FileInfo])
        $File.FullName | Should -Be $Path
        @([System.IO.File]::ReadAllBytes($Path))[0..2] | Should -Be @(0xEF, 0xBB, 0xBF)
    }

    It 'Refuses an existing file without -Force and replaces it with -Force' {
        $Path = Join-Path $TestDrive 'daily.csv'
        Set-Content -LiteralPath $Path -Value 'old'
        { $Script:Rows | Export-OmadaSqlResult -Path $Path } | Should -Throw -ErrorId 'OmadaSql.InvalidArgument,Export-OmadaSqlResult'
        $Script:Rows | Export-OmadaSqlResult -Path $Path -Force
        (Get-Content -LiteralPath $Path -First 1) | Should -Be '"Id","Name"'
    }

    It 'Writes nothing with -WhatIf' {
        $Path = Join-Path $TestDrive 'whatif.csv'
        $Script:Rows | Export-OmadaSqlResult -Path $Path -WhatIf -PassThru | Should -BeNullOrEmpty
        Test-Path -LiteralPath $Path | Should -BeFalse
    }

    It 'Refuses an unknown format or option before reading input' {
        { $Script:Rows | Export-OmadaSqlResult -Format Excel } | Should -Throw -ErrorId 'OmadaSql.InvalidArgument,Export-OmadaSqlResult'
        { $Script:Rows | Export-OmadaSqlResult -Format Xml -Option @{ Indent = $true } } | Should -Throw -ErrorId 'OmadaSql.InvalidArgument,Export-OmadaSqlResult'
        { $Script:Rows | Export-OmadaSqlResult -Path 'a.xlsx' } | Should -Throw -ErrorId 'OmadaSql.InvalidArgument,Export-OmadaSqlResult'
    }

    It 'Completes format names' {
        $Completion = [System.Management.Automation.CommandCompletion]::CompleteInput('Export-OmadaSqlResult -Format Sq', 32, $null)
        @($Completion.CompletionMatches.CompletionText) | Should -Be @('SqlArray')
    }
}

Describe 'Export-OmadaSqlResult parameter contract' -Tag 'Unit' {
    # Parameter declarations run no code a test could observe, so the mutation gate's mutants of
    # Mandatory, Position, pipeline binding and ValidateRange are caught only by asserting the contract.
    It '<Command> -<Parameter> <ParameterSet>' -ForEach @(
        @{ Command = 'Export-OmadaSqlResult'; Parameter = 'InputObject'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $true; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Export-OmadaSqlResult'; Parameter = 'Format'; ParameterSet = ''; Mandatory = $false; Position = 0; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
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
