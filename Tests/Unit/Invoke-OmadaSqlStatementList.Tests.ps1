param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaSql.PS\OmadaSql.PS.psm1')
)

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers\OmadaSqlTestHelper.ps1')
    Import-OmadaWebStub
    Get-Module -Name OmadaSql.PS -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Invoke-OmadaSqlStatementList' -Tag 'Unit' {
    BeforeAll {
        $Script:Connection = Initialize-OmadaSqlTestConnection
        $Script:Target = @(
            [pscustomobject]@{ Ordinal = 1; Line = 1; Text = 'SELECT [a] = 1'; DataConnection = [pscustomobject]@{ Name = 'OISES'; Id = 1001 } }
            [pscustomobject]@{ Ordinal = 2; Line = 3; Text = 'SELECT [b] = 2'; DataConnection = [pscustomobject]@{ Name = 'ODW'; Id = 1002 } }
        )
    }

    BeforeEach {
        Mock Enter-OmadaSqlTempQuerySlot -ModuleName 'OmadaSql.PS' { [pscustomobject]@{ Slot = 1; Name = 'TMP_x_1'; Mutex = $null } }
        Mock Exit-OmadaSqlTempQuerySlot -ModuleName 'OmadaSql.PS' { }
        Mock Set-OmadaSqlTempQueryObject -ModuleName 'OmadaSql.PS' { 55 }
        Mock Remove-OmadaSqlTempQueryObject -ModuleName 'OmadaSql.PS' { }
    }

    It 'Runs every statement through the leased object and cleans up afterwards' {
        Mock Invoke-OmadaSqlProducer -ModuleName 'OmadaSql.PS' { , @([pscustomobject]@{ v = $Id }) }
        $Result = InModuleScope 'OmadaSql.PS' -Parameters @{ Target = $Script:Target } { param($Target) @(Invoke-OmadaSqlStatementList -Context (Get-OmadaSqlConnectionContext) -Target $Target) }
        $Result.Count | Should -Be 2
        @($Result.Succeeded) | Should -Be @($true, $true)
        @($Result.RowCount) | Should -Be @(1, 1)
        @($Result.DataConnection) | Should -Be @('OISES', 'ODW')
        Should -Invoke Set-OmadaSqlTempQueryObject -ModuleName 'OmadaSql.PS' -Times 1 -Exactly -ParameterFilter { $Name -eq 'TMP_x_1' -and $Text -eq 'SELECT [a] = 1' -and $DataConnectionId -eq 1001 -and $Id -eq 0 }
        Should -Invoke Set-OmadaSqlTempQueryObject -ModuleName 'OmadaSql.PS' -Times 1 -Exactly -ParameterFilter { $Text -eq 'SELECT [b] = 2' -and $DataConnectionId -eq 1002 -and $Id -eq 55 }
        Should -Invoke Remove-OmadaSqlTempQueryObject -ModuleName 'OmadaSql.PS' -Times 1 -Exactly -ParameterFilter { $Id -eq 55 }
        Should -Invoke Exit-OmadaSqlTempQuerySlot -ModuleName 'OmadaSql.PS' -Times 1 -Exactly
    }

    It 'Keeps going after a failing statement and returns its error' {
        Mock Invoke-OmadaSqlProducer -ModuleName 'OmadaSql.PS' { throw 'boom' }
        $Result = InModuleScope 'OmadaSql.PS' -Parameters @{ Target = $Script:Target } { param($Target) @(Invoke-OmadaSqlStatementList -Context (Get-OmadaSqlConnectionContext) -Target $Target) }
        $Result.Count | Should -Be 2
        @($Result.Succeeded) | Should -Be @($false, $false)
        $Result[0].Error.Exception.Message | Should -Be 'boom'
        $Result[0].RowCount | Should -Be 0
    }

    It 'Releases the slot and deletes nothing when the object was never written' {
        Mock Set-OmadaSqlTempQueryObject -ModuleName 'OmadaSql.PS' { throw 'no rights' }
        $Result = InModuleScope 'OmadaSql.PS' -Parameters @{ Target = $Script:Target } { param($Target) @(Invoke-OmadaSqlStatementList -Context (Get-OmadaSqlConnectionContext) -Target $Target) }
        $Result[0].Succeeded | Should -BeFalse
        Should -Invoke Remove-OmadaSqlTempQueryObject -ModuleName 'OmadaSql.PS' -Times 0 -Exactly
        Should -Invoke Exit-OmadaSqlTempQuerySlot -ModuleName 'OmadaSql.PS' -Times 1 -Exactly
    }
}

Describe 'New-OmadaSqlStatementResult' -Tag 'Unit' {
    It 'Describes a statement and its rows' {
        InModuleScope 'OmadaSql.PS' {
            $Target = [pscustomobject]@{ Ordinal = 2; Line = 5; Text = 'SELECT 1'; DataConnection = [pscustomobject]@{ Name = 'OISES'; Id = 1 } }
            $Result = New-OmadaSqlStatementResult -Target $Target -Rows @(1, 2, 3) -ErrorRecord $null -Elapsed ([timespan]::FromSeconds(2))
            "$($Result.Ordinal)|$($Result.Line)|$($Result.Text)|$($Result.DataConnection)|$($Result.RowCount)|$($Result.Succeeded)|$($Result.Elapsed.TotalSeconds)" | Should -Be '2|5|SELECT 1|OISES|3|True|2'
            $Result.PSObject.TypeNames[0] | Should -Be 'OmadaSql.StatementResult'
        }
    }
}

Describe 'Invoke-OmadaSqlStatementList parameter contract' -Tag 'Unit' {
    # Parameter declarations run no code a test could observe, so the mutation gate's mutants of
    # Mandatory, Position, pipeline binding and ValidateRange are caught only by asserting the contract.
    It '<Command> -<Parameter> <ParameterSet>' -ForEach @(
        @{ Command = 'Invoke-OmadaSqlStatementList'; Parameter = 'Context'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Invoke-OmadaSqlStatementList'; Parameter = 'Target'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'New-OmadaSqlStatementResult'; Parameter = 'Target'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'New-OmadaSqlStatementResult'; Parameter = 'Rows'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'New-OmadaSqlStatementResult'; Parameter = 'Elapsed'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
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
