function Clear-OmadaSqlTempQuery {
    <#
    .SYNOPSIS
    Deletes, and with -Purge permanently removes, temporary SQL Troubleshooting objects.

    .DESCRIPTION
    Works on the objects Get-OmadaSqlTempQuery lists: by default only this profile's, with -All every
    TMP_ object. An object a session of this profile is running a query through (Leased) is never
    touched. A live object is soft-deleted, which can be undone with Restore-OmadaSqlQuery.

    -Purge also removes the deleted objects permanently with PurgeDataObject. That cannot be undone,
    and Omada only allows it to the System, Operation or Data Administrator role. Nothing is purged
    without -Purge.

    With -All, objects of other profiles and users are included. Their leases cannot be seen from
    here, so a query another session is running at that moment can fail. Use -All when nobody else is
    running ad-hoc queries.

    Every object asks for confirmation (ConfirmImpact High); use -Confirm:$false in scripts.

    .PARAMETER All
    Include every TMP_ object, not only this profile's.

    .PARAMETER Purge
    Permanently remove the objects after deleting them. Irreversible.

    .PARAMETER Connection
    The connection to use, as returned by Connect-OmadaSql -PassThru. Defaults to the current one.

    .EXAMPLE
    Clear-OmadaSqlTempQuery

    Soft-deletes this profile's temporary objects that are not deleted yet, asking for each one.

    .EXAMPLE
    Clear-OmadaSqlTempQuery -Purge -Confirm:$false

    Permanently removes this profile's temporary objects.

    .EXAMPLE
    Clear-OmadaSqlTempQuery -All -Purge -WhatIf

    Shows what removing every temporary object on the tenant would do, without doing it.

    .LINK
    Get-OmadaSqlTempQuery

    .LINK
    https://github.com/Fortigi/OmadaSql.PS
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    [OutputType([pscustomobject])]
    param(
        [switch]$All,

        [switch]$Purge,

        [object]$Connection
    )

    try {
        $Context = Get-OmadaSqlConnectionContext -Connection $Connection
        foreach ($Item in @(Get-OmadaSqlTempQueryObject -Context $Context -All:$All)) {
            if ($Item.Leased -eq $true) {
                Write-OmadaSqlLog -Message ("Skipped {0}: a session of this profile is using it." -f $Item.Name)
                continue
            }
            $Action = Get-OmadaSqlTempQueryAction -Deleted $Item.Deleted -Purge:$Purge
            if ($null -eq $Action -or -not $PSCmdlet.ShouldProcess(("{0} ({1})" -f $Item.Name, $Item.Id), $Action)) {
                continue
            }
            Invoke-OmadaSqlTempQueryAction -Context $Context -Item $Item -Purge:$Purge
            [pscustomobject]@{ Id = $Item.Id; Name = $Item.Name; Action = $Action }
        }
    }
    catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}
