function Get-OmadaSqlDatabaseReference {
    <#
    .SYNOPSIS
    The databases one statement addresses: three-part names, a USE, and four-part names.

    .DESCRIPTION
    In this module a database name is the name of a data connection: [OISES].dbo.tblDataObject runs
    against the data connection OISES, and USE [OISES] does the same for the statements that follow.
    Names are read from the parse tree, so a database-looking word in a string or a comment is never
    taken for one. Each database is listed once, in the order it first appears, compared without
    regard to case.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Statement
    )

    $Database = [System.Collections.Generic.List[string]]::new()
    $Seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $FourPartName = $false
    $UseDatabase = $null
    foreach ($Name in @(Get-OmadaSqlFragmentDescendant -Fragment $Statement -TypeName 'SchemaObjectName' -IncludeSelf)) {
        if ($null -ne $Name.ServerIdentifier) {
            $FourPartName = $true
        }
        if ($null -ne $Name.DatabaseIdentifier -and $Name.DatabaseIdentifier.Value -ne '' -and $Seen.Add($Name.DatabaseIdentifier.Value)) {
            $Database.Add($Name.DatabaseIdentifier.Value)
        }
    }
    if ($Statement.GetType().Name -eq 'UseStatement') {
        $UseDatabase = $Statement.DatabaseName.Value
        if ($Seen.Add($UseDatabase)) {
            $Database.Add($UseDatabase)
        }
    }
    [pscustomobject]@{
        Database     = $Database.ToArray()
        UseDatabase  = $UseDatabase
        FourPartName = $FourPartName
    }
}
