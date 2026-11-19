function Test-OmadaSqlRestMethodParameter {
    <#
    .SYNOPSIS
    Whether the loaded Invoke-OmadaRestMethod accepts a parameter.

    .DESCRIPTION
    Invoke-OmadaRestMethod adds its parameters through DynamicParam, so the answer comes from
    Get-Command. Resolved once per module load and cached; a different OmadaWeb.PS version is a
    new session in practice.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if ($null -eq $Script:OmadaSqlRestMethodParameterCache) {
        $Command = Get-Command -Name 'Invoke-OmadaRestMethod' -ErrorAction SilentlyContinue
        if ($null -eq $Command) {
            return $false
        }
        $Script:OmadaSqlRestMethodParameterCache = @($Command.Parameters.Keys)
    }

    return ($Name -in $Script:OmadaSqlRestMethodParameterCache)
}
