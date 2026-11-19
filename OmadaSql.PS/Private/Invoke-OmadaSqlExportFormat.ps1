function Invoke-OmadaSqlExportFormat {
    <#
    .SYNOPSIS
    Runs a format's ScriptBlock on the rows and returns its text, its output lines joined with CRLF.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Format,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Row,

        [AllowNull()]
        [hashtable]$Option
    )

    if ($null -eq $Option) {
        $Option = @{}
    }
    $Column = Get-OmadaSqlExportColumn -Row $Row
    $Output = & $Format.ScriptBlock $Row $Column $Option
    return (@($Output | ForEach-Object { [string]$_ }) -join "`r`n")
}

function Write-OmadaSqlExportFile {
    <#
    .SYNOPSIS
    Writes an export as UTF-8, with or without a byte order mark, ending in a line break.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Export-OmadaSqlResult asks ShouldProcess before it calls this.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Text,

        [Parameter(Mandatory = $true)]
        [ValidateSet('UTF8', 'UTF8BOM')]
        [string]$Encoding,

        [switch]$Force
    )

    if (-not $Force -and (Test-Path -LiteralPath $Path)) {
        throw (New-OmadaSqlErrorRecord -Kind 'InvalidArgument' -Message ("'{0}' exists. Use -Force to replace it." -f $Path) -TargetObject $Path)
    }
    $Content = if ($Text -eq '') { '' } else { "{0}`r`n" -f $Text }
    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($Encoding -eq 'UTF8BOM'))
    Write-OmadaSqlLog -Message ("Wrote {0}." -f $Path)
}
