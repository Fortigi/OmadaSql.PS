param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaSql.PS\OmadaSql.PS.psm1')
)

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers\OmadaSqlTestHelper.ps1')
    Import-OmadaWebStub
    Get-Module -Name OmadaSql.PS -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Invoke-OmadaSqlExportFormat' -Tag 'Unit' {
    It 'Passes the rows, the columns of the first row and the options, and joins output lines with CRLF' {
        $Text = InModuleScope 'OmadaSql.PS' {
            $Format = New-OmadaSqlExportFormat -Name 'Probe' -Extension '' -ScriptBlock {
                param($Row, $Column, $Option)
                'rows={0}' -f $Row.Count
                'columns={0}' -f ($Column -join '|')
                'option={0}' -f $Option['X']
                42
            }
            Invoke-OmadaSqlExportFormat -Format $Format -Row @([pscustomobject]@{ B = 1; A = 2 }, [pscustomobject]@{ B = 3; A = 4 }) -Option @{ X = 'y' }
        }
        $Text | Should -BeExactly "rows=2`r`ncolumns=B|A`r`noption=y`r`n42"
    }

    It 'Passes an empty option table without -Option' {
        $Text = InModuleScope 'OmadaSql.PS' {
            $Format = New-OmadaSqlExportFormat -Name 'Probe' -Extension '' -ScriptBlock { param($Row, $Column, $Option) '{0}:{1}' -f ($Option -is [hashtable]), $Option.Count }
            Invoke-OmadaSqlExportFormat -Format $Format -Row @()
        }
        $Text | Should -BeExactly 'True:0'
    }

    It 'Returns an empty string when the format writes nothing' {
        InModuleScope 'OmadaSql.PS' { Invoke-OmadaSqlExportFormat -Format (New-OmadaSqlExportFormat -Name 'Probe' -Extension '' -ScriptBlock { }) -Row @() } | Should -BeExactly ''
    }
}

Describe 'Write-OmadaSqlExportFile' -Tag 'Unit' {
    It 'Writes UTF-8 without a byte order mark, ending in a line break' {
        $Path = Join-Path $TestDrive 'plain.csv'
        InModuleScope 'OmadaSql.PS' -Parameters @{ Path = $Path } { param($Path) Write-OmadaSqlExportFile -Path $Path -Text ('a{0}' -f [char]0xE9) -Encoding 'UTF8' }
        $Bytes = [System.IO.File]::ReadAllBytes($Path)
        $Bytes | Should -Be @(0x61, 0xC3, 0xA9, 0x0D, 0x0A)
    }

    It 'Writes a byte order mark with UTF8BOM' {
        $Path = Join-Path $TestDrive 'bom.csv'
        InModuleScope 'OmadaSql.PS' -Parameters @{ Path = $Path } { param($Path) Write-OmadaSqlExportFile -Path $Path -Text 'a' -Encoding 'UTF8BOM' }
        [System.IO.File]::ReadAllBytes($Path) | Should -Be @(0xEF, 0xBB, 0xBF, 0x61, 0x0D, 0x0A)
    }

    It 'Writes an empty file for an empty export' {
        $Path = Join-Path $TestDrive 'empty.sql'
        InModuleScope 'OmadaSql.PS' -Parameters @{ Path = $Path } { param($Path) Write-OmadaSqlExportFile -Path $Path -Text '' -Encoding 'UTF8' }
        (Get-Item -LiteralPath $Path).Length | Should -Be 0
    }

    It 'Refuses an existing file without -Force and replaces it with -Force' {
        $Path = Join-Path $TestDrive 'exists.csv'
        Set-Content -LiteralPath $Path -Value 'old'
        $Caught = InModuleScope 'OmadaSql.PS' -Parameters @{ Path = $Path } { param($Path) try { Write-OmadaSqlExportFile -Path $Path -Text 'new' -Encoding 'UTF8' } catch { $_ } }
        $Caught.FullyQualifiedErrorId | Should -Be 'OmadaSql.InvalidArgument'
        $Caught.Exception.Message | Should -BeExactly ("'{0}' exists. Use -Force to replace it." -f $Path)
        (Get-Content -LiteralPath $Path -Raw).Trim() | Should -Be 'old'
        InModuleScope 'OmadaSql.PS' -Parameters @{ Path = $Path } { param($Path) Write-OmadaSqlExportFile -Path $Path -Text 'new' -Encoding 'UTF8' -Force }
        (Get-Content -LiteralPath $Path -Raw).Trim() | Should -Be 'new'
    }
}

Describe 'Invoke-OmadaSqlExportFormat parameter contract' -Tag 'Unit' {
    # Parameter declarations run no code a test could observe, so the mutation gate's mutants of
    # Mandatory, Position, pipeline binding and ValidateRange are caught only by asserting the contract.
    It '<Command> -<Parameter> <ParameterSet>' -ForEach @(
        @{ Command = 'Invoke-OmadaSqlExportFormat'; Parameter = 'Format'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Invoke-OmadaSqlExportFormat'; Parameter = 'Row'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Write-OmadaSqlExportFile'; Parameter = 'Path'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Write-OmadaSqlExportFile'; Parameter = 'Text'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Write-OmadaSqlExportFile'; Parameter = 'Encoding'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
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
