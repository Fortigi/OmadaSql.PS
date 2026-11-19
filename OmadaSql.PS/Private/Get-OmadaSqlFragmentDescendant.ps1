function Get-OmadaSqlFragmentDescendant {
    <#
    .SYNOPSIS
    Every fragment below a ScriptDom fragment, in document order, optionally filtered by type name.

    .DESCRIPTION
    ScriptDom offers a visitor class for this, but deriving from it needs a PowerShell class that is
    resolved when the module is parsed, before the bundled assembly is loaded. Reading the child
    fragments through reflection needs nothing at parse time. A fragment reachable along two paths
    is returned once.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$Fragment,

        [string[]]$TypeName,

        [switch]$IncludeSelf
    )

    if ($null -eq $Fragment) {
        return @()
    }
    $Seen = [System.Collections.Generic.HashSet[object]]::new()
    $null = $Seen.Add($Fragment)
    $Result = [System.Collections.Generic.List[object]]::new()
    $Pending = [System.Collections.Generic.Stack[object]]::new()
    $Pending.Push($Fragment)
    while ($Pending.Count -gt 0) {
        $Node = $Pending.Pop()
        if ($IncludeSelf -or -not [object]::ReferenceEquals($Node, $Fragment)) {
            $Result.Add($Node)
        }
        $Child = @(Get-OmadaSqlFragmentChild -Fragment $Node)
        for ($Index = $Child.Count - 1; $Index -ge 0; $Index--) {
            if ($Seen.Add($Child[$Index])) {
                $Pending.Push($Child[$Index])
            }
        }
    }
    if ($null -eq $TypeName -or $TypeName.Count -eq 0) {
        return $Result.ToArray()
    }
    return @($Result | Where-Object { $TypeName -contains $_.GetType().Name })
}

function Get-OmadaSqlFragmentChild {
    <#
    .SYNOPSIS
    The fragments a ScriptDom fragment holds directly, in property order.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Fragment
    )

    $FragmentType = [Microsoft.SqlServer.TransactSql.ScriptDom.TSqlFragment]
    $Child = [System.Collections.Generic.List[object]]::new()
    foreach ($Property in (Get-OmadaSqlFragmentChildProperty -Type $Fragment.GetType())) {
        $Value = $Property.GetValue($Fragment)
        if ($Value -is $FragmentType) {
            $Child.Add($Value)
            continue
        }
        if ($Value -is [System.Collections.IEnumerable]) {
            foreach ($Item in $Value) {
                if ($Item -is $FragmentType) {
                    $Child.Add($Item)
                }
            }
        }
    }
    return $Child.ToArray()
}

function Get-OmadaSqlFragmentChildProperty {
    <#
    .SYNOPSIS
    The properties of a fragment type that can hold a child fragment, resolved once per type.

    .DESCRIPTION
    A property qualifies when its type is a fragment, or a collection. ScriptTokenStream is left out:
    it is the token list of the whole script, hung off every fragment. Indexers are left out because
    they cannot be read without an argument.
    #>
    [CmdletBinding()]
    [OutputType([System.Reflection.PropertyInfo[]])]
    param(
        [Parameter(Mandatory = $true)]
        [type]$Type
    )

    if ($Script:OmadaSqlFragmentPropertyCache.ContainsKey($Type)) {
        return , $Script:OmadaSqlFragmentPropertyCache[$Type]
    }
    $FragmentType = [Microsoft.SqlServer.TransactSql.ScriptDom.TSqlFragment]
    $Selected = @($Type.GetProperties() | Where-Object {
            $_.Name -ne 'ScriptTokenStream' -and $_.GetIndexParameters().Length -eq 0 -and
            ($FragmentType.IsAssignableFrom($_.PropertyType) -or ($_.PropertyType -ne [string] -and [System.Collections.IEnumerable].IsAssignableFrom($_.PropertyType)))
        })
    $Script:OmadaSqlFragmentPropertyCache[$Type] = [System.Reflection.PropertyInfo[]]$Selected
    return , $Script:OmadaSqlFragmentPropertyCache[$Type]
}
