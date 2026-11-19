function Restore-OmadaSqlQuery {
    <#
    .SYNOPSIS
    Restores a deleted SQL Troubleshooting object.

    .DESCRIPTION
    Undeletes the object with Omada's UndeleteDataObject web service method, the call
    OmadaSqlTroubleshooter uses to reuse its temporary query object, and returns it. Omada allows
    this for members of System Administrators or Data Administrators. It clears the object's delete
    time and deleter, creates no new version and fires no event; references that other objects had
    to it were removed at deletion and are not restored.

    .PARAMETER Id
    The data object id of the deleted object. Accepts pipeline input by property name, so the output
    of Get-OmadaSqlQuery -IncludeDeleted can be piped in.

    .PARAMETER Connection
    The connection to use, as returned by Connect-OmadaSql -PassThru. Defaults to the current one.

    .EXAMPLE
    Restore-OmadaSqlQuery -Id 1234567

    Restores one object and shows it.

    .EXAMPLE
    Get-OmadaSqlQuery -Name 'Daily export' -IncludeDeleted | Where-Object Deleted | Restore-OmadaSqlQuery

    Restores the deleted copy of a query by name.

    .EXAMPLE
    Restore-OmadaSqlQuery -Id 1234567 -WhatIf

    Shows what would be restored, without restoring it.

    .LINK
    Remove-OmadaSqlQuery

    .LINK
    https://github.com/Fortigi/OmadaSql.PS
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType('OmadaSql.Query')]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipelineByPropertyName = $true)]
        [ValidateRange(1, [long]::MaxValue)]
        [long]$Id,

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
            if (-not $PSCmdlet.ShouldProcess(("{0} on {1}" -f $Id, $Context.Connection.BaseUrl), 'Restore SQL Troubleshooting object')) {
                return
            }
            # An ASMX method: it wants the JSON as a string, not an object for the module to serialize.
            $null = Invoke-OmadaSqlRequest -Context $Context -Method POST -Path 'WebService/DataObjectWebService.asmx/UndeleteDataObject' -Body ('{{"id":{0}}}' -f $Id)
            Write-OmadaSqlLog -Message ("Restored SQL Troubleshooting object {0}." -f $Id)
            Get-OmadaSqlQueryData -Context $Context -Id $Id -IncludeDeleted | ConvertTo-OmadaSqlQueryObject -BaseUrl $Context.Connection.BaseUrl
        }
        catch {
            $PSCmdlet.ThrowTerminatingError($_)
        }
    }
}
