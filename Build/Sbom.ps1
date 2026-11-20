<#
    The software bill of materials of a release: what ships inside the module package that the
    module did not write itself. Today that is the bundled T-SQL parser, pinned by version and
    SHA-256 in Build/DependencyLock.psd1. OmadaWeb.PS is a required module, installed from the
    PowerShell Gallery next to this one, and not part of the package, so it is not listed.

    The SBOM is CycloneDX 1.5 JSON and is built only from the lock file, so the same lock and
    version always give the same document: it has no timestamp and no random serial number.
#>

function New-OmadaSqlSbom {
    <#
    .SYNOPSIS
        Builds the CycloneDX 1.5 document for one module version from the dependency lock.
    .PARAMETER Lock
        The contents of Build/DependencyLock.psd1.
    .PARAMETER Version
        The module version the package carries, for example 2026.11.20.1 or 2026.11.20.1-nightly.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Lock,

        [Parameter(Mandatory = $true)]
        [ValidatePattern('^\d+\.\d+\.\d+\.\d+(-[A-Za-z0-9]+)?$')]
        [string]$Version
    )

    $ModuleRef = 'pkg:nuget/OmadaSql.PS@{0}' -f $Version
    $Component = @(foreach ($Artifact in $Lock.Artifacts) { ConvertTo-OmadaSqlSbomComponent -Artifact $Artifact })
    [ordered]@{
        bomFormat    = 'CycloneDX'
        specVersion  = '1.5'
        version      = 1
        metadata     = [ordered]@{
            component = [ordered]@{
                type       = 'library'
                'bom-ref'  = $ModuleRef
                name       = 'OmadaSql.PS'
                version    = $Version
                purl       = $ModuleRef
                licenses   = @([ordered]@{ license = [ordered]@{ id = 'MIT' } })
            }
        }
        components   = $Component
        dependencies = @([ordered]@{ ref = $ModuleRef; dependsOn = @($Component | ForEach-Object { $_['bom-ref'] }) })
    }
}

function ConvertTo-OmadaSqlSbomComponent {
    <#
    .SYNOPSIS
        One bundled package as a CycloneDX component, with the files the module takes from it.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Artifact
    )

    $Ref = 'pkg:nuget/{0}@{1}' -f $Artifact.Id, $Artifact.Version
    [ordered]@{
        type               = 'library'
        'bom-ref'          = $Ref
        name               = $Artifact.Id
        version            = $Artifact.Version
        purl               = $Ref
        hashes             = @([ordered]@{ alg = 'SHA-256'; content = $Artifact.Sha256 })
        licenses           = @([ordered]@{ license = [ordered]@{ id = $Artifact.License } })
        externalReferences = @([ordered]@{ type = 'distribution'; url = $Artifact.Url })
        components         = @(foreach ($File in $Artifact.Files) {
                [ordered]@{
                    type      = 'file'
                    'bom-ref' = '{0}#{1}' -f $Ref, $File.Target
                    name      = $File.Target
                    hashes    = @([ordered]@{ alg = 'SHA-256'; content = $File.Sha256 })
                }
            })
    }
}
