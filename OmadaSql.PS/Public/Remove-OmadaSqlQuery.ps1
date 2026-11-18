function Remove-OmadaSqlQuery {
    <#
    .SYNOPSIS
    Deletes a SQL Troubleshooting object in Omada.

    .DESCRIPTION
    Deletes the object over OData. Omada marks a deleted data object as deleted rather than removing
    it, so Restore-OmadaSqlQuery can bring it back, and Get-OmadaSqlQuery -IncludeDeleted still shows
    it. Other objects that referred to it lose that reference at deletion time and do not get it back
    on restore.

    .PARAMETER Id
    The data object id of the SQL Troubleshooting object. Accepts pipeline input by property name.

    .PARAMETER Connection
    The connection to use, as returned by Connect-OmadaSql -PassThru. Defaults to the current one.

    .EXAMPLE
    Remove-OmadaSqlQuery -Id 1234567 -Confirm

    Deletes one object after asking for confirmation.

    .EXAMPLE
    Get-OmadaSqlQuery -Name 'TMP_*' | Remove-OmadaSqlQuery -WhatIf

    Shows which objects would be deleted, without deleting them.

    .EXAMPLE
    Remove-OmadaSqlQuery -Id 1234567

    Deletes one object. The command asks for confirmation only when $ConfirmPreference is Medium or
    lower: a deleted object can be restored with Restore-OmadaSqlQuery.

    .LINK
    Restore-OmadaSqlQuery

    .LINK
    https://github.com/Fortigi/OmadaSql.PS
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
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
            if (-not $PSCmdlet.ShouldProcess(("{0} on {1}" -f $Id, $Context.Connection.BaseUrl), 'Delete SQL Troubleshooting object')) {
                return
            }
            $null = Invoke-OmadaSqlRequest -Context $Context -Method DELETE -Path ('{0}({1})' -f $Script:OmadaSqlEntityPath, $Id)
            Write-OmadaSqlLog -Message ("Deleted SQL Troubleshooting object {0}." -f $Id)
        }
        catch {
            $PSCmdlet.ThrowTerminatingError($_)
        }
    }
}
