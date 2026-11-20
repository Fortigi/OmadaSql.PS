# The tenant test (Tests/Tenant) only runs against a real tenant, so the build never runs it. These
# tests keep it runnable and in step with its checklist: every script parses, and the automated
# steps in docs/TENANT-TEST.md are exactly the steps the test file has.

BeforeAll {
    $Script:RepositoryRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    $Script:TenantFolder = Join-Path $Script:RepositoryRoot 'Tests/Tenant'
}

Describe 'Tests/Tenant' {
    It '<File> parses without errors' -ForEach @(
        @{ File = 'Invoke-OmadaSqlTenantTest.ps1' }
        @{ File = 'OmadaSql.TenantTest.ps1' }
        @{ File = 'TenantTestHelper.ps1' }
    ) {
        $Tokens = $null
        $Errors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $Script:TenantFolder $File), [ref]$Tokens, [ref]$Errors)
        @($Errors | ForEach-Object { '{0}: {1}' -f $_.Extent.StartLineNumber, $_.Message }) | Should -BeNullOrEmpty
    }

    It 'is not picked up by the build, which runs *.Tests.ps1 only' {
        @(Get-ChildItem -LiteralPath $Script:TenantFolder -Filter '*.Tests.ps1' -Recurse) | Should -BeNullOrEmpty
    }

    It 'has one test for every automated step of docs/TENANT-TEST.md, and no other' {
        $Checklist = Get-Content -LiteralPath (Join-Path $Script:RepositoryRoot 'docs/TENANT-TEST.md')
        $Automated = @($Checklist | Where-Object { $_ -match '^\|\s*(\d+\.\d+)\s*\|\s*auto\s*\|' } | ForEach-Object { [regex]::Match($_, '^\|\s*(\d+\.\d+)').Groups[1].Value })
        $Tokens = $null
        $Errors = $null
        $Ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $Script:TenantFolder 'OmadaSql.TenantTest.ps1'), [ref]$Tokens, [ref]$Errors)
        $Steps = @($Ast.FindAll({
                    param($Node)
                    $Node -is [System.Management.Automation.Language.CommandAst] -and $Node.GetCommandName() -eq 'It'
                }, $true) | ForEach-Object {
                $Name = $_.CommandElements[1].Value
                [regex]::Match($Name, '^(\d+\.\d+)').Groups[1].Value
            })
        $Automated.Count | Should -BeGreaterThan 20
        @($Steps | Sort-Object { [version]$_ }) | Should -Be @($Automated | Sort-Object { [version]$_ })
    }

    It 'marks every step of the checklist as auto or manual' {
        $Rows = @(Get-Content -LiteralPath (Join-Path $Script:RepositoryRoot 'docs/TENANT-TEST.md') | Where-Object { $_ -match '^\|\s*\d+\.\d+\s*\|' })
        @($Rows | Where-Object { $_ -notmatch '^\|\s*\d+\.\d+\s*\|\s*(auto|manual)\s*\|' }) | Should -BeNullOrEmpty
    }
}

Describe 'Tests/Tenant/TenantTestHelper.ps1' {
    BeforeAll {
        . (Join-Path $Script:TenantFolder 'TenantTestHelper.ps1')
    }

    It 'gives queries that read no table by name: every FROM, JOIN and APPLY source is a VALUES list' {
        foreach ($Query in (Get-TenantTestQuery).Values) {
            $Query | Should -Not -Match '\b(FROM|JOIN|APPLY)\s+(?!\(VALUES)' -Because "'$Query' must be general"
        }
    }

    It 'catches a table read through <Case>' -ForEach @(
        @{ Case = 'FROM'; Query = 'SELECT [a] = 1 FROM dbo.tblDataObject' }
        @{ Case = 'JOIN'; Query = 'SELECT [a] = 1 FROM (VALUES (1)) AS v (n) JOIN dbo.tblDataObject AS t ON 1 = 1' }
        @{ Case = 'CROSS APPLY'; Query = 'SELECT [a] = 1 FROM (VALUES (1)) AS v (n) CROSS APPLY dbo.SomeFunction(v.n) AS f' }
    ) {
        $Query | Should -Match '\b(FROM|JOIN|APPLY)\s+(?!\(VALUES)'
    }

    It 'gives queries the module accepts' {
        $ModulePath = Join-Path $Script:RepositoryRoot 'OmadaSql.PS/OmadaSql.PS.psm1'
        . (Join-Path $Script:RepositoryRoot 'Tests/Unit/Helpers/OmadaSqlTestHelper.ps1')
        Import-OmadaWebStub
        Get-Module -Name OmadaSql.PS -All | Remove-Module -Force -ErrorAction SilentlyContinue
        Import-Module $ModulePath -Force -ErrorAction Stop
        $Query = Get-TenantTestQuery
        foreach ($Name in 'Rows', 'Types', 'Fail', 'Alias', 'Unicode', 'Large') {
            @(Test-OmadaSqlQuery -Query $Query[$Name] | Where-Object { $_.Blocking }) | Should -BeNullOrEmpty -Because "the $Name query must pass validation"
        }
        @(Test-OmadaSqlQuery -Query $Query.Nameless).RuleId | Should -Contain 'OMD001'
        @(Test-OmadaSqlQuery -Query ($Query.InList -f '(1, 2)') | Where-Object { $_.Blocking }) | Should -BeNullOrEmpty
    }

    It 'builds the text outside ASCII from code points' {
        Get-TenantTestUnicodeText | Should -BeExactly ('Zo{0} {1} {2}{3}' -f [char]0x00EB, [char]0x20AC, [char]0x6D4B, [char]0x8BD5)
    }

    It 'records shapes without values' {
        $Shape = @(Get-TenantTestShape -InputObject ([pscustomobject]@{ Text = 'secret'; Number = 1; Empty = $null; Nested = [pscustomobject]@{ Id = 1 } }))
        @($Shape | ForEach-Object { $_.Name }) | Should -Be @('Text', 'Number', 'Empty', 'Nested')
        @($Shape | ForEach-Object { $_.Type }) | Should -Be @('System.String', 'System.Int32', 'null', 'System.Management.Automation.PSCustomObject')
        @($Shape[3].Of) | Should -Be @('Id')
        ($Shape | ConvertTo-Json -Depth 5) | Should -Not -Match 'secret'
    }

    It 'summarises an error record as its id and message' {
        $Record = [System.Management.Automation.ErrorRecord]::new([System.Exception]::new('boom'), 'OmadaSql.ServerError', 'InvalidResult', $null)
        $Summary = Get-TenantTestErrorSummary -ErrorRecord $Record
        $Summary.ErrorId | Should -Be 'OmadaSql.ServerError'
        $Summary.Message | Should -Be 'boom'
        Get-TenantTestErrorSummary -ErrorRecord $null | Should -BeNullOrEmpty
    }
}
