function Assert-OmadaSqlQueryNameAvailable {
    <#
    .SYNOPSIS
    Throws OmadaSql.InvalidArgument when a live SQL Troubleshooting object already has this name.

    .DESCRIPTION
    -ExceptId leaves out the object being renamed, so renaming an object to its own name is not a
    conflict. Deleted objects do not count: the SQL Troubleshooter refuses only live duplicates.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Context,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [long]$ExceptId = 0
    )

    $Existing = @(Get-OmadaSqlQueryData -Context $Context -ExactName $Name | Where-Object {
            [long](Get-OmadaSqlPropertyValue -InputObject $_ -Name 'Id') -ne $ExceptId
        })
    if ($Existing.Count -gt 0) {
        throw (New-OmadaSqlErrorRecord -Kind 'InvalidArgument' -Message ("A SQL Troubleshooting object named '{0}' already exists (id {1})." -f $Name, (Get-OmadaSqlPropertyValue -InputObject $Existing[0] -Name 'Id')) -TargetObject $Name)
    }
}
