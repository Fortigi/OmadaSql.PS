function Get-OmadaSqlTempQuery {
    <#
    .SYNOPSIS
    Lists the temporary SQL Troubleshooting objects that ad-hoc queries run through.

    .DESCRIPTION
    Invoke-OmadaSqlQuery runs ad-hoc SQL through objects named TMP_<profile id>_<slot>, where the
    profile id is stored in %LOCALAPPDATA%\OmadaSql.PS\settings.json. They are soft-deleted after each
    run and reused by the next, so normally only deleted ones exist. By default only this profile's
    objects are listed; -All lists every object whose name starts with TMP_, including those of other
    profiles, other users and OmadaSqlTroubleshooter (TMP_<id> without a slot).

    Leased is $true for an object a session of this profile is running a query through right now; it
    is $null for other profiles, whose leases cannot be seen from here.

    .PARAMETER All
    List every TMP_ object, not only this profile's.

    .PARAMETER Connection
    The connection to use, as returned by Connect-OmadaSql -PassThru. Defaults to the current one.

    .EXAMPLE
    Get-OmadaSqlTempQuery

    Lists this profile's temporary objects.

    .EXAMPLE
    Get-OmadaSqlTempQuery -All | Where-Object { -not $_.ThisProfile } | Format-Table Id, Name, Deleted

    Shows temporary objects that other profiles or tools left behind.

    .EXAMPLE
    (Get-OmadaSqlTempQuery -All | Measure-Object).Count

    Counts every temporary object on the tenant.

    .LINK
    Clear-OmadaSqlTempQuery

    .LINK
    https://github.com/Fortigi/OmadaSql.PS
    #>
    [CmdletBinding()]
    [OutputType('OmadaSql.TempQuery')]
    param(
        [switch]$All,

        [object]$Connection
    )

    try {
        $Context = Get-OmadaSqlConnectionContext -Connection $Connection
        Get-OmadaSqlTempQueryObject -Context $Context -All:$All
    }
    catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}
