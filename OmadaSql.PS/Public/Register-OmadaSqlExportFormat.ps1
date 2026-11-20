function Register-OmadaSqlExportFormat {
    <#
    .SYNOPSIS
    Adds an export format to Export-OmadaSqlResult for this session.

    .DESCRIPTION
    A format is a script block that turns rows into text. Export-OmadaSqlResult calls it with three
    arguments: the rows (an array), the column names in order (a string array) and the -Option
    hashtable of the export (empty when none was given). Its output is the export; several output
    lines are joined with CRLF.

    The built-in formats cannot be replaced. A format registered earlier is only replaced with
    -Force. Registrations last for the session; put them in a profile or a script to keep them.

    .PARAMETER Name
    The format name: letters and digits, starting with a letter.

    .PARAMETER ScriptBlock
    The script block that writes the format: param($Row, $Column, $Option).

    .PARAMETER Extension
    The file extension, for example .md. Export-OmadaSqlResult -Path picks the format by it when no
    -Format is given.

    .PARAMETER Description
    What the format writes, shown by Get-OmadaSqlExportFormat.

    .PARAMETER Option
    The option names the format accepts in -Option. Any other option is an error.

    .PARAMETER Force
    Replace a format registered earlier under the same name.

    .PARAMETER PassThru
    Return the registered format.

    .EXAMPLE
    Register-OmadaSqlExportFormat -Name Markdown -Extension .md -ScriptBlock {
        param($Row, $Column, $Option)
        '| {0} |' -f ($Column -join ' | ')
        '|{0}|' -f ((@($Column) | ForEach-Object { ' --- ' }) -join '|')
        foreach ($Item in $Row) { '| {0} |' -f ((@($Column) | ForEach-Object { $Item.$_ }) -join ' | ') }
    }

    Adds a Markdown table format; Export-OmadaSqlResult -Path .\result.md then uses it.

    .EXAMPLE
    Register-OmadaSqlExportFormat -Name IdList -Option Separator -ScriptBlock {
        param($Row, $Column, $Option)
        $Separator = if ($Option.ContainsKey('Separator')) { $Option['Separator'] } else { ',' }
        (@($Row) | ForEach-Object { $_.($Column[0]) }) -join $Separator
    }

    Adds a format that joins the first column on one line; Export-OmadaSqlResult -Format IdList
    -Option @{ Separator = ' ' } passes a separator.

    .EXAMPLE
    Register-OmadaSqlExportFormat -Name Markdown -Extension .md -Force -ScriptBlock { param($Row, $Column) '| {0} |' -f ($Column -join ' | ') }

    Replaces the Markdown format registered earlier in the session.

    .LINK
    Export-OmadaSqlResult

    .LINK
    https://github.com/Fortigi/OmadaSql.PS
    #>
    [CmdletBinding()]
    [OutputType('OmadaSql.ExportFormat')]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidatePattern('^[A-Za-z][A-Za-z0-9]*$')]
        [string]$Name,

        [Parameter(Mandatory = $true, Position = 1)]
        [scriptblock]$ScriptBlock,

        [ValidatePattern('^(\.[A-Za-z0-9]+)?$')]
        [string]$Extension = '',

        [string]$Description = '',

        [string[]]$Option = @(),

        [switch]$Force,

        [switch]$PassThru
    )

    try {
        $Table = Get-OmadaSqlExportFormatTable
        if ($Table.ContainsKey($Name) -and $Table[$Name].BuiltIn) {
            throw (New-OmadaSqlErrorRecord -Kind 'InvalidArgument' -Message ("'{0}' is a built-in export format and cannot be replaced. Register the format under another name." -f $Table[$Name].Name) -TargetObject $Name)
        }
        if ($Table.ContainsKey($Name) -and -not $Force) {
            throw (New-OmadaSqlErrorRecord -Kind 'InvalidArgument' -Message ("An export format named '{0}' is registered. Use -Force to replace it." -f $Name) -TargetObject $Name)
        }
        $Format = New-OmadaSqlExportFormat -Name $Name -Extension $Extension -ScriptBlock $ScriptBlock -Description $Description -Option $Option
        $Table.Remove($Name)
        $Table[$Name] = $Format
        Write-OmadaSqlLog -Message ("Registered export format {0}." -f $Name)
        if ($PassThru) {
            $Format
        }
    }
    catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}
