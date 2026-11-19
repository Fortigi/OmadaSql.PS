function Resolve-OmadaSqlStatementTarget {
    <#
    .SYNOPSIS
    Decides, per statement, which data connection it runs against and the text to send for it.

    .DESCRIPTION
    A database name in a statement is the name of a data connection. A three-part name binds only its
    own statement. A USE binds its own statement and every later one, as in SQL Server Management
    Studio, and runs nothing itself: a USE statement is dropped from the result. A statement that
    names no database runs against the connection the last USE chose, else against -DataConnection,
    else DataConnection is $null and the caller decides.

    Nothing is sent before this has resolved every statement: a statement that addresses two
    databases, uses a four-part (linked server) name or names an unknown data connection fails the
    whole script with an OmadaSql.InvalidArgument error.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Context,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Statement,

        [AllowNull()]
        [object]$DataConnection
    )

    $Current = $null
    if ($null -ne $DataConnection) {
        $Current = Resolve-OmadaSqlDataConnection -Context $Context -DataConnection $DataConnection
    }
    foreach ($Item in $Statement) {
        $Reference = Get-OmadaSqlDatabaseReference -Statement $Item.Fragment
        Assert-OmadaSqlSingleDatabase -Statement $Item -Reference $Reference
        if ($null -ne $Reference.UseDatabase) {
            $Current = Resolve-OmadaSqlDataConnection -Context $Context -DataConnection $Reference.UseDatabase
            continue
        }
        $Target = $Current
        if (@($Reference.Database).Count -gt 0) {
            $Target = Resolve-OmadaSqlDataConnection -Context $Context -DataConnection $Reference.Database[0]
        }
        [pscustomobject]@{
            PSTypeName     = 'OmadaSql.StatementTarget'
            Ordinal        = $Item.Ordinal
            Line           = $Item.Line
            Text           = ConvertTo-OmadaSqlUnqualifiedText -Statement $Item
            DataConnection = $Target
        }
    }
}

function Assert-OmadaSqlSingleDatabase {
    <#
    .SYNOPSIS
    Throws OmadaSql.InvalidArgument for a statement that cannot run against one data connection.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Statement,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$Reference
    )

    if ($Reference.FourPartName) {
        throw (New-OmadaSqlErrorRecord -Kind 'InvalidArgument' -Message ("Statement {0} (line {1}) uses a four-part (linked server) name. A query runs against one data connection, which cannot reach another server." -f $Statement.Ordinal, $Statement.Line) -TargetObject $Statement.Text)
    }
    if (@($Reference.Database).Count -gt 1) {
        throw (New-OmadaSqlErrorRecord -Kind 'InvalidArgument' -Message ("Statement {0} (line {1}) addresses more than one database ({2}). A statement runs against one data connection; split it into one statement per database." -f $Statement.Ordinal, $Statement.Line, ($Reference.Database -join ', ')) -TargetObject $Statement.Text)
    }
}
