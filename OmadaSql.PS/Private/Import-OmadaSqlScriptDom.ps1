function Import-OmadaSqlScriptDom {
    <#
    .SYNOPSIS
    Returns the loaded T-SQL parser assembly (ScriptDom), loading the bundled copy when needed.

    .DESCRIPTION
    The assembly is loaded on first use rather than at import, so importing the module stays cheap
    and a command that never validates a query never loads it. A ScriptDom assembly another module
    already loaded is used as it is: a second copy of the same assembly name cannot be loaded into
    one session, and every ScriptDom version carries the parsers this module uses.

    A missing or unloadable assembly is a terminating OmadaSql.ParserUnavailable error, not a skipped
    check: validation is on by default, and silently skipping it would let a query through that the
    caller expected to be checked. -SkipValidation remains the explicit way past it.
    #>
    [CmdletBinding()]
    [OutputType([System.Reflection.Assembly])]
    param()

    $Loaded = Get-OmadaSqlLoadedScriptDom
    if ($null -ne $Loaded) {
        return $Loaded
    }

    $Path = Get-OmadaSqlScriptDomPath -ModuleRoot $Script:OmadaSqlModuleRoot -Edition $PSVersionTable.PSEdition
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw (New-OmadaSqlErrorRecord -Kind 'ParserUnavailable' -Message ("The bundled T-SQL parser was not found at '{0}'. Reinstall the module, or use -SkipValidation." -f $Path) -TargetObject $Path)
    }
    try {
        Add-Type -LiteralPath $Path -ErrorAction Stop
    }
    catch {
        throw (New-OmadaSqlErrorRecord -Kind 'ParserUnavailable' -Message ("The bundled T-SQL parser at '{0}' could not be loaded: {1}" -f $Path, $_.Exception.Message) -InnerException $_.Exception -TargetObject $Path)
    }
    Write-OmadaSqlLog -Message ("Loaded the T-SQL parser from '{0}'." -f $Path)
    return (Get-OmadaSqlLoadedScriptDom)
}

function Get-OmadaSqlLoadedScriptDom {
    <#
    .SYNOPSIS
    The ScriptDom assembly already loaded in this session, or $null.
    #>
    [CmdletBinding()]
    [OutputType([System.Reflection.Assembly])]
    param()

    foreach ($Assembly in [System.AppDomain]::CurrentDomain.GetAssemblies()) {
        if ($Assembly.GetName().Name -eq 'Microsoft.SqlServer.TransactSql.ScriptDom') {
            return $Assembly
        }
    }
    return $null
}

function Get-OmadaSqlScriptDomPath {
    <#
    .SYNOPSIS
    The bundled ScriptDom assembly for a PowerShell edition: net472 for Desktop, net8.0 for Core. Pure.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ModuleRoot,

        [Parameter(Mandatory = $true)]
        [string]$Edition
    )

    $Framework = 'net8.0'
    if ($Edition -eq 'Desktop') {
        $Framework = 'net472'
    }
    return [System.IO.Path]::Combine($ModuleRoot, 'lib', $Framework, 'Microsoft.SqlServer.TransactSql.ScriptDom.dll')
}
