function Split-OmadaSqlStatement {
    <#
    .SYNOPSIS
    The top-level statements of a parsed script, in order, each with its own text.

    .DESCRIPTION
    SQL Troubleshooting executes one statement per request, so a script runs statement by statement.
    The text of each statement is cut out of the script on the parser's offsets, so a semicolon or a
    GO inside a string or a comment never splits anything. GO separates batches; the statements of
    every batch are returned in one ordered list.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$Fragment,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Sql
    )

    if ($null -eq $Fragment) {
        return
    }
    $Ordinal = 0
    foreach ($Batch in @($Fragment.Batches)) {
        foreach ($Statement in @($Batch.Statements)) {
            $Ordinal++
            [pscustomobject]@{
                PSTypeName  = 'OmadaSql.Statement'
                Ordinal     = $Ordinal
                Line        = $Statement.StartLine
                StartOffset = $Statement.StartOffset
                Text        = $Sql.Substring($Statement.StartOffset, $Statement.FragmentLength)
                Fragment    = $Statement
            }
        }
    }
}
