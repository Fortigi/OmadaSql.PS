param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaSql.PS\OmadaSql.PS.psm1')
)

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers\OmadaSqlTestHelper.ps1')
    Import-OmadaWebStub
    Get-Module -Name OmadaSql.PS -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Register-OmadaSqlExportFormat' -Tag 'Unit' {
    BeforeEach {
        InModuleScope 'OmadaSql.PS' { $Script:OmadaSqlExportFormat = $null }
    }

    It 'Adds a format Export-OmadaSqlResult writes with, also by its extension' {
        Register-OmadaSqlExportFormat -Name 'Markdown' -Extension '.md' -Description 'A table' -Option 'Title' -ScriptBlock {
            param($Row, $Column, $Option)
            '# {0}' -f $Option['Title']
            foreach ($Item in $Row) { '| {0} |' -f (($Column | ForEach-Object { $Item.$_ }) -join ' | ') }
        }
        [pscustomobject]@{ A = 1; B = 2 } | Export-OmadaSqlResult -Format Markdown -Option @{ Title = 'T' } | Should -BeExactly "# T`r`n| 1 | 2 |"
        $Path = Join-Path $TestDrive 'r.md'
        [pscustomobject]@{ A = 1 } | Export-OmadaSqlResult -Path $Path
        [System.IO.File]::ReadAllText($Path) | Should -BeExactly "# `r`n| 1 |`r`n"
        $Format = Get-OmadaSqlExportFormat -Name 'Markdown'
        $Format.Description | Should -Be 'A table'
        @($Format.Option) | Should -Be @('Title')
        $Format.BuiltIn | Should -BeFalse
    }

    It 'Returns the format with -PassThru and nothing without it' {
        @(Register-OmadaSqlExportFormat 'One' { 'x' }).Count | Should -Be 0
        (Register-OmadaSqlExportFormat -Name 'Two' -ScriptBlock { 'x' } -PassThru).Name | Should -Be 'Two'
    }

    It 'Refuses to replace a built-in format, even with -Force' {
        { Register-OmadaSqlExportFormat -Name 'csv' -ScriptBlock { 'x' } -Force } | Should -Throw -ErrorId 'OmadaSql.InvalidArgument,Register-OmadaSqlExportFormat'
        try { Register-OmadaSqlExportFormat -Name 'csv' -ScriptBlock { 'x' } } catch { $_.Exception.Message | Should -BeExactly "'Csv' is a built-in export format and cannot be replaced. Register the format under another name." }
        (Get-OmadaSqlExportFormat -Name 'Csv').BuiltIn | Should -BeTrue
    }

    It 'Replaces a registered format only with -Force' {
        Register-OmadaSqlExportFormat -Name 'Mine' -ScriptBlock { 'first' }
        { Register-OmadaSqlExportFormat -Name 'mine' -ScriptBlock { 'second' } } | Should -Throw -ErrorId 'OmadaSql.InvalidArgument,Register-OmadaSqlExportFormat'
        [pscustomobject]@{ A = 1 } | Export-OmadaSqlResult -Format Mine | Should -Be 'first'
        Register-OmadaSqlExportFormat -Name 'mine' -ScriptBlock { 'second' } -Force
        [pscustomobject]@{ A = 1 } | Export-OmadaSqlResult -Format Mine | Should -Be 'second'
        @(Get-OmadaSqlExportFormat -Name 'mine').Name | Should -Be @('mine')
    }

    It 'Refuses the name <Name>' -ForEach @(@{ Name = '1st' }, @{ Name = 'my-format' }, @{ Name = '' }) {
        { Register-OmadaSqlExportFormat -Name $Name -ScriptBlock { 'x' } } | Should -Throw
    }

    It 'Refuses the extension <Extension>' -ForEach @(@{ Extension = 'md' }, @{ Extension = '.m.d' }, @{ Extension = '.' }) {
        { Register-OmadaSqlExportFormat -Name 'Ok' -Extension $Extension -ScriptBlock { 'x' } } | Should -Throw
    }
}
