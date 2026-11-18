function Set-OmadaSqlQuery {
    <#
    .SYNOPSIS
    Changes the name, SQL text or data connection of a SQL Troubleshooting object.

    .DESCRIPTION
    Reads the object first and sends only what differs from it, as the SQL Troubleshooter does, so
    an unchanged value never produces a change in the object's history. When nothing differs no
    request is sent and the object is returned as it is. A new name that another live object already
    has is refused.

    .PARAMETER Id
    The data object id of the SQL Troubleshooting object. Accepts pipeline input by property name.

    .PARAMETER Name
    The new name.

    .PARAMETER Query
    The new SQL text.

    .PARAMETER DataConnection
    The new data connection, by name (as Get-OmadaSqlDataConnection shows it) or by id.

    .PARAMETER PassThru
    Return the object after the change.

    .PARAMETER Connection
    The connection to use, as returned by Connect-OmadaSql -PassThru. Defaults to the current one.

    .EXAMPLE
    Set-OmadaSqlQuery -Id 1234567 -Query (Get-Content -Raw .\DailyExport.sql)

    Replaces the SQL text of one object with the contents of a file.

    .EXAMPLE
    Get-OmadaSqlQuery -Name 'Daily export' | Set-OmadaSqlQuery -DataConnection 'OISES' -PassThru

    Moves a query to another data connection and shows the result.

    .EXAMPLE
    Set-OmadaSqlQuery -Id 1234567 -Name 'Daily export (old)' -WhatIf

    Shows what would change, without changing it.

    .LINK
    New-OmadaSqlQuery

    .LINK
    https://github.com/Fortigi/OmadaSql.PS
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType('OmadaSql.Query')]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipelineByPropertyName = $true)]
        [ValidateRange(1, [long]::MaxValue)]
        [long]$Id,

        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [ValidateNotNullOrEmpty()]
        [string]$Query,

        [ValidateNotNull()]
        [object]$DataConnection,

        [switch]$PassThru,

        [object]$Connection
    )

    begin {
        try {
            $Context = Get-OmadaSqlConnectionContext -Connection $Connection
            $Desired = @{}
            if ($PSBoundParameters.ContainsKey('Name')) {
                $Desired.Name = $Name
            }
            if ($PSBoundParameters.ContainsKey('Query')) {
                $Desired.Query = $Query
            }
            if ($PSBoundParameters.ContainsKey('DataConnection')) {
                $Desired.DataConnectionId = (Resolve-OmadaSqlDataConnection -Context $Context -DataConnection $DataConnection).Id
            }
            if ($Desired.Count -eq 0) {
                throw (New-OmadaSqlErrorRecord -Kind 'InvalidArgument' -Message 'Specify at least one of -Name, -Query and -DataConnection.')
            }
        }
        catch {
            $PSCmdlet.ThrowTerminatingError($_)
        }
    }

    process {
        try {
            $Current = Get-OmadaSqlQueryData -Context $Context -Id $Id | ConvertTo-OmadaSqlQueryObject -BaseUrl $Context.Connection.BaseUrl
            $Body = Get-OmadaSqlQueryChange -Current $Current -Desired $Desired
            if ($Body.Count -eq 0) {
                Write-OmadaSqlLog -Message ("SQL Troubleshooting object {0} already has these values; nothing to change." -f $Id)
            }
            elseif ($PSCmdlet.ShouldProcess(("{0} '{1}' on {2}" -f $Id, $Current.Name, $Context.Connection.BaseUrl), ("Change {0}" -f (@($Body.Keys) -join ', ')))) {
                Update-OmadaSqlQueryObject -Context $Context -Id $Id -Body $Body
            }
            else {
                return
            }

            if ($PassThru) {
                Get-OmadaSqlQueryData -Context $Context -Id $Id | ConvertTo-OmadaSqlQueryObject -BaseUrl $Context.Connection.BaseUrl
            }
        }
        catch {
            $PSCmdlet.ThrowTerminatingError($_)
        }
    }
}
