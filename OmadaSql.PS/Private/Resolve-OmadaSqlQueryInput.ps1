function Resolve-OmadaSqlQueryInput {
    <#
    .SYNOPSIS
    Decides what an object piped to Invoke-OmadaSqlQuery means: SQL text, or a saved object by its Id.

    .DESCRIPTION
    PowerShell binds a piped object whose Id is not a [long] (an [int] or a string) to -Query by
    converting the whole object to text, which would send something like '@{Id=42}' as SQL. Only a
    piped string is SQL text: an object with a positive numeric Id runs that saved object, and any
    other object is refused with OmadaSql.InvalidArgument.

    Returns the parameter set name and a copy of the bound parameters to run with.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ParameterSetName,

        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Parameter,

        [AllowNull()]
        [object]$InputObject,

        [switch]$ExpectingInput
    )

    $Bound = @{}
    foreach ($Key in $Parameter.Keys) {
        $Bound[$Key] = $Parameter[$Key]
    }
    $Resolved = [pscustomobject]@{ ParameterSetName = $ParameterSetName; Parameter = $Bound }
    if (-not $ExpectingInput -or $ParameterSetName -ne 'Query' -or $InputObject -is [string]) {
        return $Resolved
    }
    $Id = Get-OmadaSqlPipelineId -InputObject $InputObject
    if ($Id -le 0) {
        $TypeName = if ($null -eq $InputObject) { 'null' } else { $InputObject.GetType().FullName }
        throw (New-OmadaSqlErrorRecord -Kind 'InvalidArgument' -Message ("Pipeline input of type {0} is neither SQL text nor an object with a positive numeric Id. Pipe strings, the output of Get-OmadaSqlQuery, or use -Path for a file." -f $TypeName) -TargetObject $InputObject)
    }
    $null = $Bound.Remove('Query')
    $Bound['Id'] = $Id
    $Resolved.ParameterSetName = 'Id'
    return $Resolved
}

function Get-OmadaSqlPipelineId {
    <#
    .SYNOPSIS
    The Id property of a piped object as a [long], or 0 when it has none that is a whole number.
    #>
    [CmdletBinding()]
    [OutputType([long])]
    param(
        [AllowNull()]
        [object]$InputObject
    )

    $Value = Get-OmadaSqlPropertyValue -InputObject $InputObject -Name 'Id'
    $Id = [long]0
    if ($null -eq $Value -or -not [long]::TryParse([string]$Value, [ref]$Id)) {
        return [long]0
    }
    return $Id
}
