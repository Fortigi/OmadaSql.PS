param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaSql.PS\OmadaSql.PS.psm1')
)

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers\OmadaSqlTestHelper.ps1')
    Import-OmadaWebStub
    Get-Module -Name OmadaSql.PS -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Get-OmadaSqlQueryRun' -Tag 'Unit' {
    BeforeAll {
        $Script:Connection = Initialize-OmadaSqlTestConnection
    }

    BeforeEach {
        Mock Resolve-OmadaSqlDataConnection -ModuleName 'OmadaSql.PS' { [pscustomobject]@{ Name = [string]$DataConnection; Id = 1 } }
    }

    It 'Runs a saved single statement directly on the saved object, on its own data connection' {
        Mock Get-OmadaSqlQueryData -ModuleName 'OmadaSql.PS' { New-OmadaSqlTestODataQuery -Id 42 -Query 'SELECT [Id] = 1' -DataConnectionId 1001 }
        $Run = InModuleScope 'OmadaSql.PS' { Get-OmadaSqlQueryRun -Context (Get-OmadaSqlConnectionContext) -ParameterSetName 'Id' -Parameter @{ Id = 42 } }
        $Run.DirectId | Should -Be 42
        $Run.Target[0].DataConnection.Name | Should -Be '1001'
    }

    It 'Runs a saved object through a temporary object when <Case>' -ForEach @(
        @{ Case = 'it holds two statements'; Query = 'SELECT [a] = 1; SELECT [b] = 2'; Parameter = @{ Id = 42 } }
        @{ Case = 'it names a database'; Query = 'SELECT [a] = 1 FROM OISES.dbo.t'; Parameter = @{ Id = 42 } }
        @{ Case = '-DataConnection overrides its own'; Query = 'SELECT [a] = 1'; Parameter = @{ Id = 42; DataConnection = 'ODW' } }
    ) {
        Mock Get-OmadaSqlQueryData -ModuleName 'OmadaSql.PS' { New-OmadaSqlTestODataQuery -Id 42 -Query $Query -DataConnectionId 1001 }
        $Run = InModuleScope 'OmadaSql.PS' -Parameters @{ Parameter = $Parameter } { param($Parameter) Get-OmadaSqlQueryRun -Context (Get-OmadaSqlConnectionContext) -ParameterSetName 'Id' -Parameter $Parameter }
        $Run.DirectId | Should -Be 0
    }

    It 'Finds a saved object by its exact name' {
        Mock Get-OmadaSqlQueryData -ModuleName 'OmadaSql.PS' { New-OmadaSqlTestODataQuery -Id 42 -Name 'Daily [x]' }
        $Run = InModuleScope 'OmadaSql.PS' { Get-OmadaSqlQueryRun -Context (Get-OmadaSqlConnectionContext) -ParameterSetName 'Name' -Parameter @{ Name = 'Daily [x]' } }
        $Run.DirectId | Should -Be 42
        Should -Invoke Get-OmadaSqlQueryData -ModuleName 'OmadaSql.PS' -Times 1 -Exactly -ParameterFilter { $ExactName -eq 'Daily [x]' }
    }

    It 'Fails with NotFound for an unknown name' {
        Mock Get-OmadaSqlQueryData -ModuleName 'OmadaSql.PS' { }
        InModuleScope 'OmadaSql.PS' {
            $Caught = $null
            try { $null = Get-OmadaSqlQueryRun -Context (Get-OmadaSqlConnectionContext) -ParameterSetName 'Name' -Parameter @{ Name = 'Nope' } } catch { $Caught = $_ }
            $Caught.FullyQualifiedErrorId | Should -Be 'OmadaSql.NotFound'
            $Caught.Exception.Message | Should -BeLike "*'Nope'*"
        }
    }

    It 'Runs ad-hoc SQL through a temporary object' {
        $Run = InModuleScope 'OmadaSql.PS' { Get-OmadaSqlQueryRun -Context (Get-OmadaSqlConnectionContext) -ParameterSetName 'Query' -Parameter @{ Query = 'SELECT [a] = 1'; DataConnection = 'OISES' } }
        $Run.DirectId | Should -Be 0
        $Run.Target[0].DataConnection.Name | Should -Be 'OISES'
    }

    It 'Reads -Path as UTF-8' {
        $Path = Join-Path $TestDrive 'q.sql'
        [System.IO.File]::WriteAllText($Path, ("SELECT [b] = '{0}'" -f [char]0x20AC), [System.Text.UTF8Encoding]::new($false))
        $Run = InModuleScope 'OmadaSql.PS' -Parameters @{ Path = $Path } { param($Path) Get-OmadaSqlQueryRun -Context (Get-OmadaSqlConnectionContext) -ParameterSetName 'Path' -Parameter @{ Path = $Path; DataConnection = 'OISES' } }
        $Run.Target[0].Text | Should -BeExactly ("SELECT [b] = '{0}'" -f [char]0x20AC)
    }

    It 'Refuses an empty query' {
        InModuleScope 'OmadaSql.PS' {
            { Get-OmadaSqlQueryRun -Context (Get-OmadaSqlConnectionContext) -ParameterSetName 'Query' -Parameter @{ Query = '  ' } } | Should -Throw -ErrorId 'OmadaSql.InvalidArgument'
        }
    }

    It 'Passes -SkipValidation and -RuleSeverity on' {
        Mock Get-OmadaSqlExecutionPlan -ModuleName 'OmadaSql.PS' { , @([pscustomobject]@{ Text = 'x' }) }
        InModuleScope 'OmadaSql.PS' {
            $null = Get-OmadaSqlQueryRun -Context (Get-OmadaSqlConnectionContext) -ParameterSetName 'Query' -Parameter @{ Query = 'SELECT 1'; SkipValidation = $true; RuleSeverity = @{ OMD001 = 'Off' } }
        }
        Should -Invoke Get-OmadaSqlExecutionPlan -ModuleName 'OmadaSql.PS' -Times 1 -Exactly -ParameterFilter { $SkipValidation -and $RuleSeverity.OMD001 -eq 'Off' -and $Sql -eq 'SELECT 1' }
    }
}

Describe 'Invoke-OmadaSqlSavedStatement' -Tag 'Unit' {
    BeforeAll {
        $Script:Connection = Initialize-OmadaSqlTestConnection
        $Script:Target = [pscustomobject]@{ Ordinal = 1; Line = 1; Text = 'SELECT 1'; DataConnection = [pscustomobject]@{ Name = 'OISES'; Id = 1 } }
    }

    It 'Executes the saved object itself and never writes it' {
        Mock Invoke-OmadaSqlProducer -ModuleName 'OmadaSql.PS' { , @([pscustomobject]@{ a = 1 }) }
        Mock Invoke-OmadaSqlRequest -ModuleName 'OmadaSql.PS' { throw 'must not write' }
        $Result = InModuleScope 'OmadaSql.PS' -Parameters @{ Target = $Script:Target } { param($Target) Invoke-OmadaSqlSavedStatement -Context (Get-OmadaSqlConnectionContext) -Id 42 -Target $Target }
        $Result.RowCount | Should -Be 1
        $Result.Succeeded | Should -BeTrue
        Should -Invoke Invoke-OmadaSqlProducer -ModuleName 'OmadaSql.PS' -Times 1 -Exactly -ParameterFilter { $Id -eq 42 }
    }

    It 'Returns the error of a failing execution' {
        Mock Invoke-OmadaSqlProducer -ModuleName 'OmadaSql.PS' { throw 'boom' }
        $Result = InModuleScope 'OmadaSql.PS' -Parameters @{ Target = $Script:Target } { param($Target) Invoke-OmadaSqlSavedStatement -Context (Get-OmadaSqlConnectionContext) -Id 42 -Target $Target }
        $Result.Succeeded | Should -BeFalse
        $Result.Error.Exception.Message | Should -Be 'boom'
    }
}

Describe 'Get-OmadaSqlQueryRun parameter contract' -Tag 'Unit' {
    # Parameter declarations run no code a test could observe, so the mutation gate's mutants of
    # Mandatory, Position, pipeline binding and ValidateRange are caught only by asserting the contract.
    It '<Command> -<Parameter> <ParameterSet>' -ForEach @(
        @{ Command = 'Get-OmadaSqlQueryRun'; Parameter = 'Context'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Get-OmadaSqlQueryRun'; Parameter = 'ParameterSetName'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Get-OmadaSqlQueryRun'; Parameter = 'Parameter'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Get-OmadaSqlSavedQuery'; Parameter = 'Context'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Get-OmadaSqlSavedQuery'; Parameter = 'ParameterSetName'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Get-OmadaSqlSavedQuery'; Parameter = 'Parameter'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Get-OmadaSqlRunText'; Parameter = 'ParameterSetName'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Get-OmadaSqlRunText'; Parameter = 'Parameter'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Invoke-OmadaSqlSavedStatement'; Parameter = 'Context'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Invoke-OmadaSqlSavedStatement'; Parameter = 'Id'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Invoke-OmadaSqlSavedStatement'; Parameter = 'Target'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
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
