function Invoke-OmadaSqlStatementList {
    <#
    .SYNOPSIS
    Runs statements one by one through a leased temporary query object and returns one result per
    statement.

    .DESCRIPTION
    One slot is leased for the whole run, the object is rewritten for every statement, and it is
    soft-deleted and the slot released afterwards, also when a statement or the run fails. A failing
    statement does not stop the next one: its result carries the error, and the caller decides.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Context,

        [Parameter(Mandatory = $true)]
        [object[]]$Target
    )

    $Slot = Enter-OmadaSqlTempQuerySlot
    $Id = 0
    try {
        foreach ($Item in $Target) {
            $Started = [System.Diagnostics.Stopwatch]::StartNew()
            $Rows = @()
            $ErrorRecord = $null
            try {
                $Id = Set-OmadaSqlTempQueryObject -Context $Context -Name $Slot.Name -Text $Item.Text -DataConnectionId $Item.DataConnection.Id -Id $Id
                $Rows = Invoke-OmadaSqlProducer -Context $Context -Id $Id
            }
            catch {
                $ErrorRecord = $_
            }
            New-OmadaSqlStatementResult -Target $Item -Rows $Rows -ErrorRecord $ErrorRecord -Elapsed $Started.Elapsed
        }
    }
    finally {
        if ($Id -gt 0) {
            Remove-OmadaSqlTempQueryObject -Context $Context -Id $Id
        }
        Exit-OmadaSqlTempQuerySlot -Slot $Slot
    }
}

function New-OmadaSqlStatementResult {
    <#
    .SYNOPSIS
    The result of one statement: where it ran, its rows, its error and how long it took.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds an object in memory and changes no state.')]
    [CmdletBinding()]
    [OutputType('OmadaSql.StatementResult')]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Target,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Rows,

        [AllowNull()]
        [System.Management.Automation.ErrorRecord]$ErrorRecord,

        [Parameter(Mandatory = $true)]
        [timespan]$Elapsed
    )

    [pscustomobject]@{
        PSTypeName     = 'OmadaSql.StatementResult'
        Ordinal        = $Target.Ordinal
        Line           = $Target.Line
        Text           = $Target.Text
        DataConnection = $Target.DataConnection.Name
        RowCount       = $Rows.Count
        Rows           = $Rows
        Succeeded      = ($null -eq $ErrorRecord)
        Error          = $ErrorRecord
        Elapsed        = $Elapsed
    }
}
