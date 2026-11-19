param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaSql.PS\OmadaSql.PS.psm1')
)

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers\OmadaSqlTestHelper.ps1')
    Import-OmadaWebStub
    Get-Module -Name OmadaSql.PS -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Get-OmadaSqlDiagnostic' -Tag 'Unit' {
    It 'Reports a syntax error as a blocking SQL<number> error and runs no rule on that script' {
        InModuleScope 'OmadaSql.PS' {
            $Result = Get-OmadaSqlDiagnostic -Sql "SELECT COUNT(*) FROM dbo.t;`nSELEC 1"
            @($Result.Diagnostic).Count | Should -BeGreaterThan 0
            @($Result.Diagnostic | Where-Object { $_.RuleId -notmatch '^SQL\d+$' }).Count | Should -Be 0
            $Result.Diagnostic[0].Severity | Should -Be 'Error'
            $Result.Diagnostic[0].Blocking | Should -BeTrue
            $Result.Diagnostic[0].Source | Should -Be 'T-SQL syntax'
            $Result.Diagnostic[0].Line | Should -Be 2
        }
    }

    It 'Returns the statements and the parser with the findings' {
        InModuleScope 'OmadaSql.PS' {
            $Result = Get-OmadaSqlDiagnostic -Sql "SELECT [a] = 1;`nSELECT [b] = 2"
            @($Result.Diagnostic).Count | Should -Be 0
            @($Result.Statement).Count | Should -Be 2
            $Result.ParserVersion | Should -Match '^TSql\d+Parser$'
        }
    }

    It 'Orders findings by line and column' {
        InModuleScope 'OmadaSql.PS' {
            $Result = Get-OmadaSqlDiagnostic -Sql "SELECT [a b] = 1, COUNT(*) FROM dbo.t;`nDELETE FROM dbo.t"
            @($Result.Diagnostic | ForEach-Object { $_.RuleId }) | Should -Be @('OMD003', 'OMD001', 'OMD010')
            $Result.Diagnostic[0].Source | Should -Be 'Omada compatibility'
        }
    }

    It 'Applies -RuleSeverity, and Off removes the rule' {
        InModuleScope 'OmadaSql.PS' {
            $Result = Get-OmadaSqlDiagnostic -Sql 'SELECT COUNT(*), [a b] = 1 FROM dbo.t' -RuleSeverity @{ OMD001 = 'Info'; OMD003 = 'Off' }
            @($Result.Diagnostic).Count | Should -Be 1
            $Result.Diagnostic[0].Severity | Should -Be 'Info'
            $Result.Diagnostic[0].Blocking | Should -BeFalse
        }
    }
}

Describe 'Resolve-OmadaSqlRuleSeverity' -Tag 'Unit' {
    It 'Returns every rule at its default without overrides' {
        InModuleScope 'OmadaSql.PS' {
            $Severity = Resolve-OmadaSqlRuleSeverity -RuleSeverity $null
            $Severity.Count | Should -Be @(Get-OmadaSqlRule).Count
            $Severity.OMD001 | Should -Be 'Warning'
        }
    }

    It 'Accepts a rule id in any letter case' {
        InModuleScope 'OmadaSql.PS' {
            (Resolve-OmadaSqlRuleSeverity -RuleSeverity @{ omd001 = 'Error' }).OMD001 | Should -Be 'Error'
        }
    }

    It 'Refuses <Case>' -ForEach @(
        @{ Case = 'an unknown rule'; Override = @{ OMD999 = 'Error' }; Message = "Unknown rule 'OMD999'*Known rules: OMD001,*" }
        @{ Case = 'an unknown severity'; Override = @{ OMD001 = 'Fatal' }; Message = "Severity 'Fatal' for rule 'OMD001'*" }
    ) {
        InModuleScope 'OmadaSql.PS' -Parameters @{ Override = $Override; Message = $Message } {
            param($Override, $Message)
            $Caught = $null
            try { $null = Resolve-OmadaSqlRuleSeverity -RuleSeverity $Override } catch { $Caught = $_ }
            $Caught.FullyQualifiedErrorId | Should -Be 'OmadaSql.InvalidArgument'
            $Caught.Exception.Message | Should -BeLike $Message
        }
    }
}

Describe 'New-OmadaSqlDiagnostic' -Tag 'Unit' {
    It 'Builds a diagnostic that blocks for <Severity>: <Blocking>' -ForEach @(
        @{ Severity = 'Error'; Blocking = $true }
        @{ Severity = 'Warning'; Blocking = $true }
        @{ Severity = 'Info'; Blocking = $false }
    ) {
        InModuleScope 'OmadaSql.PS' -Parameters @{ Severity = $Severity; Blocking = $Blocking } {
            param($Severity, $Blocking)
            $Diagnostic = New-OmadaSqlDiagnostic -RuleId 'OMD001' -Severity $Severity -Line 3 -Column 7 -Message 'm' -Source 's'
            $Diagnostic.Blocking | Should -Be $Blocking
            $Diagnostic.PSObject.TypeNames[0] | Should -Be 'OmadaSql.Diagnostic'
            "$($Diagnostic.RuleId)|$($Diagnostic.Line)|$($Diagnostic.Column)|$($Diagnostic.Message)|$($Diagnostic.Source)" | Should -Be 'OMD001|3|7|m|s'
        }
    }
}

Describe 'Get-OmadaSqlDiagnostic parameter contract' -Tag 'Unit' {
    # Parameter declarations run no code a test could observe, so the mutation gate's mutants of
    # Mandatory, Position, pipeline binding and ValidateRange are caught only by asserting the contract.
    It '<Command> -<Parameter> <ParameterSet>' -ForEach @(
        @{ Command = 'Get-OmadaSqlDiagnostic'; Parameter = 'Sql'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Get-OmadaSqlRuleDiagnostic'; Parameter = 'Context'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Get-OmadaSqlRuleDiagnostic'; Parameter = 'Severity'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'ConvertTo-OmadaSqlSyntaxDiagnostic'; Parameter = 'ParseError'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'New-OmadaSqlDiagnostic'; Parameter = 'RuleId'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'New-OmadaSqlDiagnostic'; Parameter = 'Severity'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'New-OmadaSqlDiagnostic'; Parameter = 'Line'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'New-OmadaSqlDiagnostic'; Parameter = 'Column'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'New-OmadaSqlDiagnostic'; Parameter = 'Message'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'New-OmadaSqlDiagnostic'; Parameter = 'Source'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
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
