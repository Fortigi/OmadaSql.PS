function Export-OmadaSqlResult {
    <#
    .SYNOPSIS
    Writes query result rows as CSV, JSON, XML, a text table, or T-SQL or PowerShell literals.

    .DESCRIPTION
    Collects the rows piped in (from Invoke-OmadaSqlQuery, or one OmadaSql.StatementResult from
    -AsStatementResult) and writes them in one format: to -Path, or as a string when no -Path is given.
    The columns, in order, are those of the first row.

    The built-in formats (see Get-OmadaSqlExportFormat for the details of each):

      Csv              every field quoted, semicolon by default (Option Delimiter, NoHeader)
      Json             an array of objects (Option Compress)
      Xml              <Result><Row><Field Name="...">
      Text             a plain text table
      SqlArray         (v1, v2) for an IN list, or (VALUES ...) AS t (...) for several columns
      PowerShellArray  @(v1, v2), or @([PSCustomObject]@{ ... }) for several columns

    Without -Format the format follows the extension of -Path (.csv, .json, .xml, .txt, .sql, .ps1),
    and is Csv without -Path. Numbers and dates are written culture-independently, so an export reads
    the same on every machine. Files are UTF-8, by default without a byte order mark; an existing file
    is only replaced with -Force. Register-OmadaSqlExportFormat adds a format.

    .PARAMETER InputObject
    The rows to export, or one OmadaSql.StatementResult. Accepts pipeline input.

    .PARAMETER Format
    The name of the export format, for example Csv or Json.

    .PARAMETER Path
    The file to write. Without it the export is returned as a string.

    .PARAMETER Option
    Options of the format, for example @{ Delimiter = ',' } for Csv. An option the format does not
    know is an error.

    .PARAMETER Encoding
    UTF8 (the default, no byte order mark) or UTF8BOM, which some versions of Excel need to read a
    CSV file with characters outside ASCII.

    .PARAMETER Force
    Replace -Path when it exists.

    .PARAMETER PassThru
    Return the written file.

    .EXAMPLE
    Invoke-OmadaSqlQuery -Name 'Daily export' | Export-OmadaSqlResult -Path .\daily.csv -Force

    Runs a saved query and replaces daily.csv with its rows.

    .EXAMPLE
    Invoke-OmadaSqlQuery -Query 'SELECT [Id] = Id FROM dbo.tblDataObject WHERE Deleted = 1' -DataConnection 'OISES' | Export-OmadaSqlResult -Format SqlArray

    Returns the ids as a T-SQL list, ready to paste after IN.

    .EXAMPLE
    Get-OmadaSqlQuery -Name 'Daily export' | Invoke-OmadaSqlQuery | Export-OmadaSqlResult -Path .\daily.csv -Option @{ Delimiter = ',' } -Encoding UTF8BOM -Force

    Writes a comma-separated file with a byte order mark, for a tool that expects commas.

    .LINK
    Get-OmadaSqlExportFormat

    .LINK
    Register-OmadaSqlExportFormat

    .LINK
    https://github.com/Fortigi/OmadaSql.PS
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([string], [System.IO.FileInfo])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [AllowNull()]
        [object]$InputObject,

        [Parameter(Position = 0)]
        [ArgumentCompleter({ param($Command, $Parameter, $Word) (Get-OmadaSqlExportFormat).Name | Where-Object { $_ -like ('{0}*' -f $Word) } })]
        [string]$Format,

        [string]$Path,

        [hashtable]$Option,

        [ValidateSet('UTF8', 'UTF8BOM')]
        [string]$Encoding = 'UTF8',

        [switch]$Force,

        [switch]$PassThru
    )

    begin {
        $Row = [System.Collections.Generic.List[object]]::new()
        $StatementCount = 0
        try {
            $Resolved = Resolve-OmadaSqlExportFormat -Format $Format -Path $Path
            Assert-OmadaSqlExportOption -Format $Resolved -Option $Option
        }
        catch {
            $PSCmdlet.ThrowTerminatingError($_)
        }
    }

    process {
        if ($null -eq $InputObject) {
            return
        }
        if ($InputObject.PSObject.TypeNames -contains 'OmadaSql.StatementResult') {
            $StatementCount++
            foreach ($Item in @($InputObject.Rows)) {
                $Row.Add($Item)
            }
            return
        }
        $Row.Add($InputObject)
    }

    end {
        try {
            if ($StatementCount -gt 1) {
                throw (New-OmadaSqlErrorRecord -Kind 'InvalidArgument' -Message ("Export one statement result at a time; {0} were piped in. Select one, for example with Where-Object Ordinal -eq 1." -f $StatementCount))
            }
            $Text = Invoke-OmadaSqlExportFormat -Format $Resolved -Row $Row.ToArray() -Option $Option
            if ([string]::IsNullOrEmpty($Path)) {
                return $Text
            }
            $FullPath = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($Path)
            if ($PSCmdlet.ShouldProcess($FullPath, ("Export {0} row(s) as {1}" -f $Row.Count, $Resolved.Name))) {
                Write-OmadaSqlExportFile -Path $FullPath -Text $Text -Encoding $Encoding -Force:$Force
                if ($PassThru) {
                    Get-Item -LiteralPath $FullPath
                }
            }
        }
        catch {
            $PSCmdlet.ThrowTerminatingError($_)
        }
    }
}
