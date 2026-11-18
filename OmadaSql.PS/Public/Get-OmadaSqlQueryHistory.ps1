function Get-OmadaSqlQueryHistory {
    <#
    .SYNOPSIS
    Gets the full change history of a SQL Troubleshooting object.

    .DESCRIPTION
    Reads the data object history Omada keeps for a SQL Troubleshooting object, newest first, and
    returns one entry per changed field: when, who, the kind of change, the field, and its old and
    new value. Unlike the SQL Troubleshooter, which only shows changes to the SQL text, every field is
    returned (name, query, data connection, and any other); use -Field to narrow it down.

    .PARAMETER Id
    The data object id of the SQL Troubleshooting object. Accepts pipeline input by property name,
    so the output of Get-OmadaSqlQuery can be piped in.

    .PARAMETER Field
    Return only entries for these fields, wildcards allowed, for example 'SQL Query'.

    .PARAMETER Connection
    The connection to use, as returned by Connect-OmadaSql -PassThru. Defaults to the current one.

    .EXAMPLE
    Get-OmadaSqlQueryHistory -Id 1234567

    Lists every change to the object, newest first.

    .EXAMPLE
    Get-OmadaSqlQuery -Name 'Daily export' | Get-OmadaSqlQueryHistory -Field 'SQL Query' | Select-Object ChangedAt, ChangedBy, NewValue

    Shows how the SQL text of one query changed over time.

    .EXAMPLE
    Get-OmadaSqlQueryHistory -Id 1234567 | Group-Object ChangedBy | Sort-Object Count -Descending

    Shows who changed the object most often.

    .LINK
    Get-OmadaSqlQuery

    .LINK
    https://github.com/Fortigi/OmadaSql.PS
    #>
    [CmdletBinding()]
    [OutputType('OmadaSql.HistoryEntry')]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipelineByPropertyName = $true)]
        [ValidateRange(1, [long]::MaxValue)]
        [long]$Id,

        [SupportsWildcards()]
        [string[]]$Field = @('*'),

        [object]$Connection
    )

    begin {
        try {
            $Context = Get-OmadaSqlConnectionContext -Connection $Connection
        }
        catch {
            $PSCmdlet.ThrowTerminatingError($_)
        }
    }

    process {
        try {
            foreach ($Entry in @(Get-OmadaSqlHistoryEntry -Context $Context -Id $Id)) {
                $Name = [string]$Entry.Field
                if (@($Field | Where-Object { $Name -like $_ }).Count -gt 0) {
                    $Entry
                }
            }
        }
        catch {
            $PSCmdlet.ThrowTerminatingError($_)
        }
    }
}
