function Add-OmadaSqlQueryDetail {
    <#
    .SYNOPSIS
    Adds the detail of Get-OmadaSqlQuery -Detailed to a query object: history, creator, last
    editor, owners and the data connection name.

    .DESCRIPTION
    CreatedBy/CreatedAt and ChangedBy/ChangedAt come from the history, because OData does not expose
    CreatedBy on data objects. The oldest entry whose change type starts with 'Creat' is the creation;
    when the history has no such entry (it may have been trimmed), the oldest entry is used and
    CreatedBy is reported as found in that entry. The owners are the EXPLICITOWNER references when the
    object type exposes that property, else $null.
    #>
    [CmdletBinding()]
    [OutputType('OmadaSql.Query')]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Context,

        [Parameter(Mandatory = $true)]
        [object]$Query
    )

    $History = @(Get-OmadaSqlHistoryEntry -Context $Context -Id $Query.Id)
    $Summary = Get-OmadaSqlHistorySummary -History $History

    $ConnectionName = $Query.DataConnectionName
    if ([string]::IsNullOrWhiteSpace($ConnectionName) -and $null -ne $Query.DataConnectionId) {
        $Known = @(Get-OmadaSqlDataConnection -Connection $Context.Connection | Where-Object { $_.Id -eq $Query.DataConnectionId })
        if ($Known.Count -gt 0) {
            $ConnectionName = $Known[0].Name
        }
    }

    $Owner = Get-OmadaSqlPropertyValue -InputObject $Query.Properties -Name 'EXPLICITOWNER'
    $Query.DataConnectionName = $ConnectionName
    $Query.PSObject.TypeNames.Insert(0, 'OmadaSql.QueryDetail')
    $Query | Add-Member -NotePropertyMembers ([ordered]@{
            CreatedBy = $Summary.CreatedBy
            CreatedAt = $Summary.CreatedAt
            ChangedBy = $Summary.ChangedBy
            ChangedAt = $Summary.ChangedAt
            Owner     = $(if ($null -ne $Owner) { @($Owner | ForEach-Object { Get-OmadaSqlReferenceName -Reference $_ }) } else { $null })
            History   = $History
        }) -PassThru
}

function Get-OmadaSqlHistorySummary {
    <#
    .SYNOPSIS
    Creator and last editor from history entries in any order. Pure.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [AllowEmptyCollection()]
        [object[]]$History = @()
    )

    $Dated = @($History | Where-Object { $null -ne $_ -and $null -ne $_.ChangedAt } | Sort-Object -Property ChangedAt)
    $Summary = [pscustomobject]@{ CreatedBy = $null; CreatedAt = $null; ChangedBy = $null; ChangedAt = $null }
    if ($Dated.Count -eq 0) {
        return $Summary
    }

    $Created = @($Dated | Where-Object { [string]$_.ChangeType -like 'Creat*' }) | Select-Object -First 1
    if ($null -eq $Created) {
        $Created = $Dated[0]
    }
    $Latest = $Dated[-1]
    $Summary.CreatedBy = $Created.ChangedBy
    $Summary.CreatedAt = $Created.ChangedAt
    $Summary.ChangedBy = $Latest.ChangedBy
    $Summary.ChangedAt = $Latest.ChangedAt
    return $Summary
}

function Get-OmadaSqlReferenceName {
    <#
    .SYNOPSIS
    The display text of an OData reference: DisplayName, then Name, then Id.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()]
        [object]$Reference
    )

    foreach ($Name in 'DisplayName', 'Name', 'Id') {
        $Value = Get-OmadaSqlPropertyValue -InputObject $Reference -Name $Name
        if ($null -ne $Value -and "$Value" -ne '') {
            return [string]$Value
        }
    }
    return [string]$Reference
}
