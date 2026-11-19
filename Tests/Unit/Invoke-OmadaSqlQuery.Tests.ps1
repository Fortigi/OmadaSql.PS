param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaSql.PS\OmadaSql.PS.psm1')
)

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers\OmadaSqlTestHelper.ps1')
    Import-OmadaWebStub
    Get-Module -Name OmadaSql.PS -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Invoke-OmadaSqlQuery' -Tag 'Unit' {
    BeforeAll {
        $Script:Connection = Initialize-OmadaSqlTestConnection
        $Script:Target = [pscustomobject]@{ Ordinal = 1; Line = 1; Text = 'SELECT 1'; DataConnection = [pscustomobject]@{ Name = 'OISES'; Id = 1 } }
    }

    It 'Returns the rows of ad-hoc SQL' {
        Mock Get-OmadaSqlQueryRun -ModuleName 'OmadaSql.PS' { [pscustomobject]@{ Target = @($Script:Target); DirectId = 0 } }
        Mock Invoke-OmadaSqlStatementList -ModuleName 'OmadaSql.PS' { [pscustomobject]@{ Ordinal = 1; Line = 1; Text = 'x'; Rows = @([pscustomobject]@{ a = 1 }, [pscustomobject]@{ a = 2 }); Error = $null } }
        $Rows = @(Invoke-OmadaSqlQuery -Query 'SELECT 1' -DataConnection 'OISES')
        @($Rows.a) | Should -Be @(1, 2)
        Should -Invoke Get-OmadaSqlQueryRun -ModuleName 'OmadaSql.PS' -Times 1 -Exactly -ParameterFilter { $ParameterSetName -eq 'Query' -and $Parameter.Query -eq 'SELECT 1' -and $Parameter.DataConnection -eq 'OISES' }
    }

    It 'Runs a saved object directly when the plan allows it, also from the pipeline' {
        Mock Get-OmadaSqlQueryRun -ModuleName 'OmadaSql.PS' { [pscustomobject]@{ Target = @($Script:Target); DirectId = 42 } }
        Mock Invoke-OmadaSqlSavedStatement -ModuleName 'OmadaSql.PS' { [pscustomobject]@{ Ordinal = 1; Line = 1; Text = 'x'; Rows = @([pscustomobject]@{ a = 9 }); Error = $null } }
        Mock Invoke-OmadaSqlStatementList -ModuleName 'OmadaSql.PS' { throw 'must not use a temporary object' }
        @([pscustomobject]@{ Id = [long]42 } | Invoke-OmadaSqlQuery).a | Should -Be 9
        Should -Invoke Invoke-OmadaSqlSavedStatement -ModuleName 'OmadaSql.PS' -Times 1 -Exactly -ParameterFilter { $Id -eq 42 }
        Should -Invoke Get-OmadaSqlQueryRun -ModuleName 'OmadaSql.PS' -Times 1 -Exactly -ParameterFilter { $ParameterSetName -eq 'Id' }
    }

    It 'Returns statement results with -AsStatementResult' {
        Mock Get-OmadaSqlQueryRun -ModuleName 'OmadaSql.PS' { [pscustomobject]@{ Target = @($Script:Target); DirectId = 0 } }
        Mock Invoke-OmadaSqlStatementList -ModuleName 'OmadaSql.PS' { [pscustomobject]@{ Ordinal = 1; Line = 1; Text = 'x'; Rows = @(1, 2); Error = $null } }
        $Result = @(Invoke-OmadaSqlQuery -Query 'SELECT 1' -AsStatementResult)
        $Result.Count | Should -Be 1
        $Result[0].Ordinal | Should -Be 1
    }

    It 'Reports a failed statement as a non-terminating error and still returns the other rows' {
        Mock Get-OmadaSqlQueryRun -ModuleName 'OmadaSql.PS' { [pscustomobject]@{ Target = @($Script:Target); DirectId = 0 } }
        Mock Invoke-OmadaSqlStatementList -ModuleName 'OmadaSql.PS' {
            $Failure = [System.Management.Automation.ErrorRecord]::new([System.Exception]::new('server said no'), 'OmadaSql.ServerError', [System.Management.Automation.ErrorCategory]::InvalidResult, $null)
            [pscustomobject]@{ Ordinal = 1; Line = 2; Text = 'SELECT x'; Rows = @(); Error = $Failure }
            [pscustomobject]@{ Ordinal = 2; Line = 4; Text = 'SELECT y'; Rows = @([pscustomobject]@{ a = 1 }); Error = $null }
        }
        $Rows = @(Invoke-OmadaSqlQuery -Query 'SELECT 1' -ErrorVariable Failed -ErrorAction SilentlyContinue)
        $Rows.Count | Should -Be 1
        $Failed.Count | Should -Be 1
        $Failed[0].FullyQualifiedErrorId | Should -BeLike 'OmadaSql.ServerError*'
        $Failed[0].Exception.Message | Should -Be 'Statement 1 (line 2) failed: server said no'
    }

    It 'Stops at the first failure with -ErrorAction Stop' {
        Mock Get-OmadaSqlQueryRun -ModuleName 'OmadaSql.PS' { [pscustomobject]@{ Target = @($Script:Target); DirectId = 0 } }
        Mock Invoke-OmadaSqlStatementList -ModuleName 'OmadaSql.PS' {
            $Failure = [System.Management.Automation.ErrorRecord]::new([System.Exception]::new('server said no'), 'OmadaSql.ServerError', [System.Management.Automation.ErrorCategory]::InvalidResult, $null)
            [pscustomobject]@{ Ordinal = 1; Line = 2; Text = 'SELECT x'; Rows = @(); Error = $Failure }
        }
        { Invoke-OmadaSqlQuery -Query 'SELECT 1' -ErrorAction Stop } | Should -Throw '*Statement 1 (line 2) failed*'
    }

    It 'Fails as a whole, terminating, when the plan is refused' {
        Mock Get-OmadaSqlQueryRun -ModuleName 'OmadaSql.PS' { throw ([System.Management.Automation.ErrorRecord]::new([System.Exception]::new('blocked'), 'OmadaSql.ValidationFailed', [System.Management.Automation.ErrorCategory]::InvalidData, $null)) }
        { Invoke-OmadaSqlQuery -Query 'DELETE FROM t' } | Should -Throw -ErrorId 'OmadaSql.ValidationFailed,Invoke-OmadaSqlQuery'
    }
}

Describe 'Invoke-OmadaSqlQuery parameter contract' -Tag 'Unit' {
    # Parameter declarations run no code a test could observe, so the mutation gate's mutants of
    # Mandatory, Position, pipeline binding and ValidateRange are caught only by asserting the contract.
    It '<Command> -<Parameter> <ParameterSet>' -ForEach @(
        @{ Command = 'Invoke-OmadaSqlQuery'; Parameter = 'Id'; ParameterSet = 'Id'; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $true; RangeMin = '1'; RangeMax = '9223372036854775807' }
        @{ Command = 'Invoke-OmadaSqlQuery'; Parameter = 'Name'; ParameterSet = 'Name'; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Invoke-OmadaSqlQuery'; Parameter = 'Query'; ParameterSet = 'Query'; Mandatory = $true; Position = 0; ValueFromPipeline = $true; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Invoke-OmadaSqlQuery'; Parameter = 'Path'; ParameterSet = 'Path'; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
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
