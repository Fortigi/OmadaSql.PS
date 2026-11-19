param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaSql.PS\OmadaSql.PS.psm1')
)

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers\OmadaSqlTestHelper.ps1')
    Import-OmadaWebStub
    Get-Module -Name OmadaSql.PS -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Get-OmadaSqlExecutionPlan' -Tag 'Unit' {
    BeforeAll {
        $Script:Connection = Initialize-OmadaSqlTestConnection
    }

    BeforeEach {
        Mock Resolve-OmadaSqlDataConnection -ModuleName 'OmadaSql.PS' { [pscustomobject]@{ Name = [string]$DataConnection; Id = 1 } }
    }

    It 'Splits a valid script and resolves every statement' {
        $Target = InModuleScope 'OmadaSql.PS' { Get-OmadaSqlExecutionPlan -Context (Get-OmadaSqlConnectionContext) -Sql "SELECT [a] = 1;`nSELECT [b] = 2 FROM ODW.dbo.t" -DataConnection 'OISES' }
        $Target.Count | Should -Be 2
        @($Target.DataConnection.Name) | Should -Be @('OISES', 'ODW')
        $Target[1].Text | Should -Be 'SELECT [b] = 2 FROM dbo.t'
    }

    It 'Stops a script with a blocking finding with ValidationFailed, listing it, before resolving anything' {
        $Caught = InModuleScope 'OmadaSql.PS' {
            try { $null = Get-OmadaSqlExecutionPlan -Context (Get-OmadaSqlConnectionContext) -Sql 'DELETE FROM dbo.t' -DataConnection 'OISES'; $null } catch { $_ }
        }
        $Caught.FullyQualifiedErrorId | Should -Be 'OmadaSql.ValidationFailed'
        $Caught.Exception.Message | Should -BeLike '*1 blocking finding(s)*line 1, column 1: Error OMD010:*-SkipValidation*'
        Should -Invoke Resolve-OmadaSqlDataConnection -ModuleName 'OmadaSql.PS' -Times 0 -Exactly
    }

    It 'Passes -RuleSeverity on' {
        $Target = InModuleScope 'OmadaSql.PS' { Get-OmadaSqlExecutionPlan -Context (Get-OmadaSqlConnectionContext) -Sql 'SELECT 1' -DataConnection 'OISES' -RuleSeverity @{ OMD001 = 'Off' } }
        $Target.Count | Should -Be 1
    }

    It 'With -SkipValidation runs what the rules would block' {
        $Target = InModuleScope 'OmadaSql.PS' { Get-OmadaSqlExecutionPlan -Context (Get-OmadaSqlConnectionContext) -Sql 'SELECT 1; SELECT 2' -DataConnection 'OISES' -SkipValidation }
        $Target.Count | Should -Be 2
    }

    It 'With -SkipValidation sends a script that does not parse as one statement, unchanged' {
        $Target = InModuleScope 'OmadaSql.PS' { Get-OmadaSqlExecutionPlan -Context (Get-OmadaSqlConnectionContext) -Sql 'SELEC 1; SELECT 2' -DataConnection 'OISES' -SkipValidation }
        $Target.Count | Should -Be 1
        $Target[0].Text | Should -BeExactly 'SELEC 1; SELECT 2'
        $Target[0].DataConnection.Name | Should -Be 'OISES'
        $Target[0].Ordinal | Should -Be 1
        $Target[0].Line | Should -Be 1
    }

    It 'With -SkipValidation sends the script as one statement when the parser cannot be loaded' {
        Mock ConvertTo-OmadaSqlScriptFragment -ModuleName 'OmadaSql.PS' { throw 'no parser' }
        $Target = InModuleScope 'OmadaSql.PS' { Get-OmadaSqlExecutionPlan -Context (Get-OmadaSqlConnectionContext) -Sql 'SELECT 1; SELECT 2' -DataConnection 'OISES' -SkipValidation }
        $Target.Count | Should -Be 1
    }

    It 'Refuses a statement without a data connection before anything is sent' {
        $Caught = InModuleScope 'OmadaSql.PS' {
            try { $null = Get-OmadaSqlExecutionPlan -Context (Get-OmadaSqlConnectionContext) -Sql "SELECT [a] = 1;`nSELECT [b] = 2" ; $null } catch { $_ }
        }
        $Caught.FullyQualifiedErrorId | Should -Be 'OmadaSql.InvalidArgument'
        $Caught.Exception.Message | Should -BeLike 'Statement 1 (line 1) has no data connection*'
    }

    It 'Refuses an unparsed script without a data connection' {
        $Caught = InModuleScope 'OmadaSql.PS' {
            try { $null = Get-OmadaSqlExecutionPlan -Context (Get-OmadaSqlConnectionContext) -Sql 'SELEC 1' -SkipValidation; $null } catch { $_ }
        }
        $Caught.FullyQualifiedErrorId | Should -Be 'OmadaSql.InvalidArgument'
    }
}

Describe 'Assert-OmadaSqlNoBlockingDiagnostic' -Tag 'Unit' {
    It 'Passes for no findings and for Info findings only' {
        InModuleScope 'OmadaSql.PS' {
            { Assert-OmadaSqlNoBlockingDiagnostic -Diagnostic @() } | Should -Not -Throw
            { Assert-OmadaSqlNoBlockingDiagnostic -Diagnostic @(New-OmadaSqlDiagnostic -RuleId 'OMD003' -Severity 'Info' -Line 1 -Column 1 -Message 'm' -Source 's') } | Should -Not -Throw
        }
    }
}

Describe 'Get-OmadaSqlExecutionPlan parameter contract' -Tag 'Unit' {
    # Parameter declarations run no code a test could observe, so the mutation gate's mutants of
    # Mandatory, Position, pipeline binding and ValidateRange are caught only by asserting the contract.
    It '<Command> -<Parameter> <ParameterSet>' -ForEach @(
        @{ Command = 'Get-OmadaSqlExecutionPlan'; Parameter = 'Context'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Get-OmadaSqlExecutionPlan'; Parameter = 'Sql'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Get-OmadaSqlUncheckedStatement'; Parameter = 'Sql'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Assert-OmadaSqlNoBlockingDiagnostic'; Parameter = 'Diagnostic'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
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
