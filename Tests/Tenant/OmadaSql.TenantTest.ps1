param(
    [Parameter(Mandatory = $true)]
    [string]$DataConnection,

    [string]$SecondDataConnection,

    [string]$QueryPath,

    [Parameter(Mandatory = $true)]
    [string]$RunId
)

# The tenant test: the automated steps of docs/TENANT-TEST.md, one It per step, named by its
# number. Run it through Tests/Tenant/Invoke-OmadaSqlTenantTest.ps1, never on its own: the runner
# checks the connection, chooses the steps for the role and writes the results. The file name does
# not end in .Tests.ps1, so the build never runs it.
#
# Tags: 'Administrator' or 'User' for a step that needs that role, 'Large' for the result over
# 100 000 rows. Untagged steps run for either role.

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'TenantTestHelper.ps1')
    $Script:DataConnection = $DataConnection
    $Script:SecondDataConnection = $SecondDataConnection
    $Script:QueryPath = $QueryPath
    $Script:Prefix = 'OSQLTEST {0}' -f $RunId
    $Script:Query = Get-TenantTestQuery
    $Script:Created = [System.Collections.Generic.List[long]]::new()
    $Script:InstanceGuid = & (Get-Module -Name OmadaSql.PS) { (Get-OmadaSqlSetting).InstanceGuid }
    $Script:Resolved = @(Get-OmadaSqlDataConnection | Where-Object { $_.Name -eq $Script:DataConnection -or [string]$_.Id -eq $Script:DataConnection })[0]

    function New-TenantTestObject {
        param([Parameter(Mandatory = $true)] [string]$Step)
        $Object = New-OmadaSqlQuery -Name ('{0} {1}' -f $Script:Prefix, $Step) -Query $Script:Query.Rows -DataConnection $Script:DataConnection
        $Script:Created.Add($Object.Id)
        return $Object
    }
}

AfterAll {
    foreach ($Id in $Script:Created) {
        try {
            if (-not (Get-OmadaSqlQuery -Id $Id -ErrorAction Stop).Deleted) {
                Remove-OmadaSqlQuery -Id $Id -Confirm:$false -ErrorAction Stop
            }
        }
        catch {
            Write-Warning ("Could not remove test object {0}: {1}" -f $Id, $_.Exception.Message)
        }
    }
}

Describe '1. Connection and data connections' {
    It '1.4 lists the data connections and finds the one given' {
        $List = @(Get-OmadaSqlDataConnection -Force)
        Add-TenantTestObservation -Step '1.4' -Data ([ordered]@{ Count = $List.Count; Shape = Get-TenantTestShape -InputObject $List[0] })
        $List.Count | Should -BeGreaterThan 0
        $Script:Resolved | Should -Not -BeNullOrEmpty -Because "data connection '$($Script:DataConnection)' must be on the list"
    }
}

Describe '2. Object management' {
    It '2.1 creates an object with the data connection given' {
        $Object = New-TenantTestObject -Step '2.1'
        $Object.Id | Should -BeGreaterThan 0
        $Object.DataConnectionId | Should -Be $Script:Resolved.Id
        $Object.Query | Should -BeExactly $Script:Query.Rows
    }

    It '2.2 reads the object in detail, and records the shape of the raw OData object' {
        $Object = New-TenantTestObject -Step '2.2'
        $Detail = Get-OmadaSqlQuery -Id $Object.Id -Detailed
        $Reference = $Detail.Properties.C_SQLTROUBLESHOOTING_DATACONNECTION
        Add-TenantTestObservation -Step '2.2' -Data ([ordered]@{
                RawObject           = Get-TenantTestShape -InputObject $Detail.Properties
                DataConnectionShape = $(if ($null -eq $Reference) { 'missing' } elseif ($Reference -is [System.ValueType] -or $Reference -is [string]) { $Reference.GetType().FullName } else { Get-TenantTestShape -InputObject $Reference })
                HasExplicitOwner    = $null -ne $Detail.Properties.PSObject.Properties['EXPLICITOWNER']
                DetailShape         = Get-TenantTestShape -InputObject $Detail
            })
        $Detail.DataConnectionId | Should -Be $Script:Resolved.Id
        @($Detail.History).Count | Should -BeGreaterThan 0
    }

    It '2.3 changes the object and records the change types in its history' {
        $Object = New-TenantTestObject -Step '2.3'
        $Changed = "SELECT [Id] = v.Id FROM (VALUES (1), (2)) AS v (Id)"
        Set-OmadaSqlQuery -Id $Object.Id -Query $Changed -Confirm:$false
        $History = @(Get-OmadaSqlQueryHistory -Id $Object.Id)
        $Oldest = @($History | Sort-Object -Property ChangedAt)[0]
        Add-TenantTestObservation -Step '2.3' -Data ([ordered]@{ ChangeTypes = @($History.ChangeType | Select-Object -Unique); OldestChangeType = $Oldest.ChangeType; Fields = @($History.Field | Where-Object { $_ } | Select-Object -Unique) })
        (Get-OmadaSqlQuery -Id $Object.Id).Query | Should -BeExactly $Changed
        @($History | Where-Object { $_.Field -eq 'C_QUERY' }).Count | Should -BeGreaterThan 0
    }

    It '2.4 deletes and restores an object, and records whether this role may restore' {
        $Object = New-TenantTestObject -Step '2.4'
        Remove-OmadaSqlQuery -Id $Object.Id -Confirm:$false
        (Get-OmadaSqlQuery -Id $Object.Id).Deleted | Should -BeTrue
        $Failure = $null
        try {
            Restore-OmadaSqlQuery -Id $Object.Id -Confirm:$false -ErrorAction Stop
        }
        catch {
            $Failure = $_
        }
        Add-TenantTestObservation -Step '2.4' -Data ([ordered]@{ Restored = $null -eq $Failure; Error = Get-TenantTestErrorSummary -ErrorRecord $Failure })
        if ($null -eq $Failure) {
            (Get-OmadaSqlQuery -Id $Object.Id).Deleted | Should -BeFalse
        }
    }

    It '2.5 records whether this role sees deleted objects in a listing' {
        $Object = New-TenantTestObject -Step '2.5'
        Remove-OmadaSqlQuery -Id $Object.Id -Confirm:$false
        $Listed = @(Get-OmadaSqlQuery -Name ('{0} 2.5' -f $Script:Prefix) -IncludeDeleted)
        Add-TenantTestObservation -Step '2.5' -Data ([ordered]@{ DeletedListed = @($Listed | Where-Object { $_.Id -eq $Object.Id }).Count -gt 0 })
        $true | Should -BeTrue
    }

    It '2.6 records how many objects a full listing returns' {
        $Live = @(Get-OmadaSqlQuery)
        $All = @(Get-OmadaSqlQuery -IncludeDeleted)
        Add-TenantTestObservation -Step '2.6' -Data ([ordered]@{ Live = $Live.Count; IncludingDeleted = $All.Count; Note = 'Compare with the count in the web UI; a count equal to the ODataPageSizeLimit points to a paging problem.' })
        $All.Count | Should -BeGreaterOrEqual $Live.Count
    }
}

Describe '3. Query execution' {
    It '3.1 runs ad-hoc SQL through this profile''s first slot and soft-deletes it' {
        $Rows = @(Invoke-OmadaSqlQuery -Query $Script:Query.Rows -DataConnection $Script:DataConnection)
        @($Rows.Name) | Should -Be @('One', 'Two', 'Three')
        $Slot = Get-TenantTestSlotObject -Slot 1
        $Slot | Should -Not -BeNullOrEmpty
        $Slot.Name | Should -Be ('TMP_{0}_1' -f $Script:InstanceGuid)
        $Slot.Deleted | Should -BeTrue
        $Script:SlotOneId = $Slot.Id
    }

    It '3.2 reuses the same object for the next run' {
        $null = Invoke-OmadaSqlQuery -Query $Script:Query.Rows -DataConnection $Script:DataConnection
        $Slot = Get-TenantTestSlotObject -Slot 1
        $Slot.Id | Should -Be $Script:SlotOneId
        $Slot.Deleted | Should -BeTrue
        @(Get-OmadaSqlTempQuery | Where-Object { $_.Slot -eq 1 }).Count | Should -Be 1
    }

    It '3.3 records the types the values of a row arrive as' {
        $Row = @(Invoke-OmadaSqlQuery -Query $Script:Query.Types -DataConnection $Script:DataConnection)[0]
        Add-TenantTestObservation -Step '3.3' -Data ([ordered]@{
                Shape = Get-TenantTestShape -InputObject $Row
                Text  = [ordered]@{ Bit = [string]$Row.Bit; Decimal = [string]$Row.Decimal; Float = [string]$Row.Float; Date = [string]$Row.Date; DateTime = [string]$Row.DateTime }
            })
        $Row | Should -Not -BeNullOrEmpty
        $Row.Null | Should -BeNullOrEmpty
    }

    It '3.4 takes the second slot while the first is in use' {
        $MutexName = & (Get-Module -Name OmadaSql.PS) { param($Guid) Get-OmadaSqlTempQueryMutexName -InstanceGuid $Guid -Slot 1 } $Script:InstanceGuid
        $Hold = Start-TenantTestSlotHold -MutexName $MutexName
        try {
            $Rows = @(Invoke-OmadaSqlQuery -Query $Script:Query.Rows -DataConnection $Script:DataConnection)
        }
        finally {
            Stop-TenantTestSlotHold -Hold $Hold
        }
        $Rows.Count | Should -Be 3
        $Slot = Get-TenantTestSlotObject -Slot 2
        $Slot | Should -Not -BeNullOrEmpty
        $Slot.Deleted | Should -BeTrue
    }

    It '3.5 reports a failing statement and still soft-deletes the object' {
        $Rows = @(Invoke-OmadaSqlQuery -Query $Script:Query.Fail -DataConnection $Script:DataConnection -ErrorVariable Failed -ErrorAction SilentlyContinue)
        $Reported = @($Failed | Where-Object { $_.FullyQualifiedErrorId -like '*,Invoke-OmadaSqlQuery' })
        Add-TenantTestObservation -Step '3.5' -Data ([ordered]@{ Error = Get-TenantTestErrorSummary -ErrorRecord $Reported[0] })
        $Rows.Count | Should -Be 0
        $Reported.Count | Should -Be 1
        (Get-TenantTestSlotObject -Slot 1).Deleted | Should -BeTrue
    }

    It '3.6 records what Omada does with a DECLARE' {
        $Rows = @(Invoke-OmadaSqlQuery -Query $Script:Query.Declare -DataConnection $Script:DataConnection -SkipValidation -ErrorVariable Failed -ErrorAction SilentlyContinue)
        $Reported = @($Failed | Where-Object { $_.FullyQualifiedErrorId -like '*,Invoke-OmadaSqlQuery' })
        Add-TenantTestObservation -Step '3.6' -Data ([ordered]@{ Rows = $Rows.Count; Error = Get-TenantTestErrorSummary -ErrorRecord @($Reported)[0] })
        $true | Should -BeTrue
    }

    It '3.7 returns no rows for a result with an unnamed column (OMD001)' {
        $Rows = @(Invoke-OmadaSqlQuery -Query $Script:Query.Nameless -DataConnection $Script:DataConnection -SkipValidation)
        Add-TenantTestObservation -Step '3.7' -Data ([ordered]@{ Rows = $Rows.Count })
        $Rows.Count | Should -Be 0
    }

    It '3.8 renames an alias with a space to an underscore (OMD003)' {
        $Row = @(Invoke-OmadaSqlQuery -Query $Script:Query.Alias -DataConnection $Script:DataConnection -SkipValidation)[0]
        $Names = @($Row.PSObject.Properties.Name)
        Add-TenantTestObservation -Step '3.8' -Data ([ordered]@{ Columns = $Names })
        $Names | Should -Contain 'Display_Name'
    }

    It '3.9 returns text outside ASCII unchanged' {
        $Row = @(Invoke-OmadaSqlQuery -Query $Script:Query.Unicode -DataConnection $Script:DataConnection)[0]
        $Row.Text | Should -BeExactly (Get-TenantTestUnicodeText)
    }

    It '3.10 runs each statement of a script against its own data connection' -Skip:([string]::IsNullOrEmpty($SecondDataConnection)) {
        $SecondResolved = @(Get-OmadaSqlDataConnection | Where-Object { $_.Name -eq $Script:SecondDataConnection -or [string]$_.Id -eq $Script:SecondDataConnection })[0]
        $First = Get-TenantTestSchemaTable -DataConnection $Script:Resolved.Name
        $Second = Get-TenantTestSchemaTable -DataConnection $SecondResolved.Name
        $Batch = "SELECT TOP 1 [a] = 1 FROM [{0}].[{1}].[{2}];`nSELECT TOP 1 [b] = 1 FROM [{3}].[{4}].[{5}]" -f $Script:Resolved.Name, $First.Schema, $First.Table, $SecondResolved.Name, $Second.Schema, $Second.Table
        $Result = @(Invoke-OmadaSqlQuery -Query $Batch -AsStatementResult)
        @($Result.Succeeded) | Should -Be @($true, $true)
        @($Result.DataConnection) | Should -Be @($Script:Resolved.Name, $SecondResolved.Name)
    }

    It '3.11 runs a saved object without changing it' {
        $Object = New-TenantTestObject -Step '3.11'
        $Before = @(Get-OmadaSqlQueryHistory -Id $Object.Id).Count
        $Rows = @(Invoke-OmadaSqlQuery -Id $Object.Id)
        $After = @(Get-OmadaSqlQueryHistory -Id $Object.Id).Count
        $Rows.Count | Should -Be 3
        $After | Should -Be $Before
    }

    It '3.12 refuses or returns a result of more than 100 000 rows, never a truncated one' -Tag 'Large' {
        $Failure = $null
        $Rows = @()
        try {
            $Rows = @(Invoke-OmadaSqlQuery -Query $Script:Query.Large -DataConnection $Script:DataConnection -ErrorAction Stop)
        }
        catch {
            $Failure = $_
        }
        Add-TenantTestObservation -Step '3.12' -Data ([ordered]@{ Rows = $Rows.Count; Error = Get-TenantTestErrorSummary -ErrorRecord $Failure })
        if ($null -eq $Failure) {
            $Rows.Count | Should -Be 161051
        }
        else {
            $Failure.FullyQualifiedErrorId | Should -BeLike 'OmadaSql.InvalidResult*'
        }
    }
}

Describe '4. Validation and schema' {
    BeforeAll {
        $Script:SchemaTable = Get-TenantTestSchemaTable -DataConnection $Script:DataConnection
    }

    It '4.1 reads the schema, 4.2 from the cache the second time' {
        $Fresh = Measure-Command { $Script:Schema = @(Get-OmadaSqlSchema -DataConnection $Script:DataConnection -Force) }
        $Cached = Measure-Command { $null = Get-OmadaSqlSchema -DataConnection $Script:DataConnection }
        Add-TenantTestObservation -Step '4.1' -Data ([ordered]@{ Tables = $Script:Schema.Count; Columns = @($Script:Schema.Column).Count; FreshSeconds = [math]::Round($Fresh.TotalSeconds, 2); CachedSeconds = [math]::Round($Cached.TotalSeconds, 2) })
        $Script:Schema.Count | Should -BeGreaterThan 0
        $Cached | Should -BeLessThan $Fresh
    }

    It '4.3 records column entries the module could not split into a name and a type' {
        $Column = @(Get-OmadaSqlSchema -DataConnection $Script:DataConnection | ForEach-Object { $_.Column })
        Add-TenantTestObservation -Step '4.3' -Data ([ordered]@{
                Columns         = $Column.Count
                WithoutType     = @($Column | Where-Object { $_.Type -eq '' }).Count
                TypesWithSpaces = @($Column | Where-Object { $_.Type -match '\s' } | ForEach-Object { $_.Type } | Select-Object -Unique)
                BaseTypes       = @($Column | ForEach-Object { ($_.Type -split '[\s(]', 2)[0].ToLowerInvariant() } | Select-Object -Unique | Sort-Object)
            })
        @($Column | Where-Object { $_.Name -eq '' }).Count | Should -Be 0
    }

    It '4.4 records the schema size of the second data connection' -Skip:([string]::IsNullOrEmpty($SecondDataConnection)) {
        $Time = Measure-Command { $Tables = @(Get-OmadaSqlSchema -DataConnection $Script:SecondDataConnection -Force) }
        Add-TenantTestObservation -Step '4.4' -Data ([ordered]@{ Tables = $Tables.Count; Seconds = [math]::Round($Time.TotalSeconds, 2) })
        $Tables.Count | Should -BeGreaterThan 0
    }

    It '4.5 reports an unknown table (OMD030) and an unknown column (OMD031), and accepts a known one' {
        $Table = '[{0}].[{1}]' -f $Script:SchemaTable.Schema, $Script:SchemaTable.Table
        $Known = $Script:SchemaTable.Column[0].Name
        $UnknownTable = @(Test-OmadaSqlQuery -Query ('SELECT [c] = 1 FROM [{0}].[OSQLTEST_NoSuchTable]' -f $Script:SchemaTable.Schema) -DataConnection $Script:DataConnection)
        $UnknownColumn = @(Test-OmadaSqlQuery -Query ('SELECT [c] = t.[OSQLTEST_NoSuchColumn] FROM {0} AS t' -f $Table) -DataConnection $Script:DataConnection)
        $KnownColumn = @(Test-OmadaSqlQuery -Query ('SELECT [c] = t.[{0}] FROM {1} AS t' -f $Known, $Table) -DataConnection $Script:DataConnection)
        @($UnknownTable.RuleId) | Should -Be @('OMD030')
        @($UnknownColumn.RuleId) | Should -Be @('OMD031')
        $KnownColumn.Count | Should -Be 0
    }

    It '4.6 records the findings on the queries in -QueryPath' -Skip:([string]::IsNullOrEmpty($QueryPath)) {
        $Finding = foreach ($File in @(Get-ChildItem -LiteralPath $Script:QueryPath -Filter '*.sql' -File)) {
            foreach ($Item in @(Test-OmadaSqlQuery -Path $File.FullName -DataConnection $Script:DataConnection)) {
                [ordered]@{ File = $File.Name; RuleId = $Item.RuleId; Line = $Item.Line; Column = $Item.Column; Message = $Item.Message }
            }
        }
        Add-TenantTestObservation -Step '4.6' -Data ([ordered]@{ Findings = @($Finding); Note = 'Check every schema finding (OMD030-OMD032): each one that is wrong is a false positive.' })
        $true | Should -BeTrue
    }
}

Describe '5. Export' {
    BeforeAll {
        $Script:ExportRows = @(Invoke-OmadaSqlQuery -Query $Script:Query.Rows -DataConnection $Script:DataConnection)
    }

    It '5.1 writes a semicolon CSV with a byte order mark' {
        $Path = Join-Path $TestDrive 'export.csv'
        $Script:ExportRows | Export-OmadaSqlResult -Path $Path -Encoding UTF8BOM -Force
        $Bytes = [System.IO.File]::ReadAllBytes($Path)
        @($Bytes[0..2]) | Should -Be @(0xEF, 0xBB, 0xBF)
        (Get-Content -LiteralPath $Path -Encoding UTF8 -TotalCount 1) | Should -Be '"Id";"Name"'
    }

    It '5.2 writes JSON, XML and a text table that read back' {
        @((($Script:ExportRows | Export-OmadaSqlResult -Format Json) | ConvertFrom-Json) | ForEach-Object { $_ }).Name | Should -Be @('One', 'Two', 'Three')
        @(([xml]($Script:ExportRows | Export-OmadaSqlResult -Format Xml)).Result.Row).Count | Should -Be 3
        ($Script:ExportRows | Export-OmadaSqlResult -Format Text) | Should -Match 'Three'
    }

    It '5.3 writes an IN list that SQL Troubleshooting runs' {
        $List = $Script:ExportRows | Select-Object -Property Id | Export-OmadaSqlResult -Format SqlArray
        $Row = @(Invoke-OmadaSqlQuery -Query ($Script:Query.InList -f ($List -replace "`r`n", ' ')) -DataConnection $Script:DataConnection)[0]
        [int]$Row.n | Should -Be 3
    }
}

Describe '6. Cleanup and purge' {
    It '6.1 refuses the purge to a regular user with the role it needs' -Tag 'User' {
        $Result = @()
        $Failure = $null
        try {
            $Result = @(Clear-OmadaSqlTempQuery -Purge -Confirm:$false -ErrorAction Stop)
        }
        catch {
            $Failure = $_
        }
        Add-TenantTestObservation -Step '6.1' -Data ([ordered]@{ Actions = @($Result.Action); Error = Get-TenantTestErrorSummary -ErrorRecord $Failure })
        $Failure | Should -Not -BeNullOrEmpty -Because 'a regular user should not be allowed to purge'
        $Failure.Exception.Message | Should -BeLike '*Administrator*'
    }

    It '6.2 purges every temporary object of this profile' -Tag 'Administrator' {
        $Result = @(Clear-OmadaSqlTempQuery -Purge -Confirm:$false)
        Add-TenantTestObservation -Step '6.2' -Data ([ordered]@{ Actions = @($Result.Action) })
        @(Get-OmadaSqlTempQuery | Where-Object { -not $_.Leased }).Count | Should -Be 0
    }
}
