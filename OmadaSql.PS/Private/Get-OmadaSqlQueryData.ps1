function Get-OmadaSqlQueryData {
    <#
    .SYNOPSIS
    Reads raw C_P_SQLTROUBLESHOOTING OData objects: one by id, or a list, optionally by exact name.

    .DESCRIPTION
    -Id greater than 0 reads that object. Otherwise the list is read; a -Name without wildcards is
    sent as an OData filter, a name with wildcards is applied locally. -ExactName is always sent as
    an OData filter, whatever characters it contains (a name may legitimately contain '[' or '*'). -IncludeDeleted adds
    DeletedStatus=Both, the query option OmadaSqlTroubleshooter uses: without it Omada returns live
    objects only.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Context,

        [long]$Id = 0,

        [string]$Name = '*',

        [string]$ExactName,

        [switch]$IncludeDeleted
    )

    $Option = [System.Collections.Generic.List[string]]::new()
    if ($IncludeDeleted) {
        $Option.Add('DeletedStatus=Both')
    }

    if ($Id -gt 0) {
        $Path = '{0}({1})' -f $Script:OmadaSqlEntityPath, $Id
        if ($Option.Count -gt 0) {
            $Path = '{0}?{1}' -f $Path, ($Option -join '&')
        }
        return Invoke-OmadaSqlRequest -Context $Context -Method GET -Path $Path
    }

    $HasWildcard = $false
    if ($PSBoundParameters.ContainsKey('ExactName')) {
        $Option.Add((ConvertTo-OmadaSqlODataFilter -Equal ([ordered]@{ NAME = $ExactName })))
    }
    elseif ([System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters($Name)) {
        $HasWildcard = $true
    }
    else {
        $Option.Add((ConvertTo-OmadaSqlODataFilter -Equal ([ordered]@{ NAME = $Name })))
    }
    $Option.Add('$orderby=NAME')

    $Response = Invoke-OmadaSqlRequest -Context $Context -Method GET -Path ('{0}?{1}' -f $Script:OmadaSqlEntityPath, ($Option -join '&')) -Paged
    $Items = @()
    if ($null -ne $Response -and $null -ne $Response.PSObject.Properties['value']) {
        $Items = @($Response.value)
    }
    if ($HasWildcard) {
        $Items = @($Items | Where-Object { [string](Get-OmadaSqlPropertyValue -InputObject $_ -Name 'NAME') -like $Name })
    }
    return $Items
}
