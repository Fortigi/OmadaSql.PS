param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaSql.PS\OmadaSql.PS.psm1')
)

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers\OmadaSqlTestHelper.ps1')
    Import-OmadaWebStub
    Get-Module -Name OmadaSql.PS -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $ModulePath -Force -ErrorAction Stop
}


Describe 'ConvertFrom-OmadaSqlDataConnectionHtml' -Tag 'Unit' {
    It 'Parses name, id and UID of every option, HTML-decoded, in page order' {
        $Html = @'
<select id="dc"><option value="1001" data-uid="aaaa-1" selected="selected">OISES</option>
<option value="1002" data-uid="bbbb-2">Source &amp; Staging</option>
<option value="1001" data-uid="aaaa-1">OISES</option></select>
'@
        InModuleScope 'OmadaSql.PS' -Parameters @{ Html = $Html } {
            param($Html)
            $Result = @(ConvertFrom-OmadaSqlDataConnectionHtml -Html $Html)
            $Result.Count | Should -Be 2
            $Result[0].Name | Should -Be 'OISES'
            $Result[0].Id | Should -Be 1001
            $Result[0].UId | Should -Be 'aaaa-1'
            $Result[1].Name | Should -Be 'Source & Staging'
            $Result[0].PSObject.TypeNames | Should -Contain 'OmadaSql.DataConnection'
        }
    }

    It 'Returns nothing for an empty page or a page without options' {
        InModuleScope 'OmadaSql.PS' {
            @(ConvertFrom-OmadaSqlDataConnectionHtml -Html '').Count | Should -Be 0
            @(ConvertFrom-OmadaSqlDataConnectionHtml -Html '<html><body>no options</body></html>').Count | Should -Be 0
        }
    }
}
