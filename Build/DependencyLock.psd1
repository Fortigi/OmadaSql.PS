<#
    Pinned version and SHA-256 of every binary that ships inside the module.

    OmadaSql.PS bundles the T-SQL parser (Microsoft.SqlServer.TransactSql.ScriptDom, MIT licensed) so
    queries can be validated before anything is sent to the tenant. Nothing is downloaded at run time:
    Build/Get-BundledDependency.ps1 fetches the package during the build, refuses it unless the
    package hash matches, and extracts only the files listed here, each checked against its own hash.

    Keys per artefact:
      Id          - the NuGet package id; also the key linking the entry to Build/Dependencies
      Version     - the pinned version (must equal the version in Build/Dependencies/Dependencies.csproj)
      Url         - the exact URL the build downloads from
      Sha256      - expected SHA-256 of the .nupkg, lower-case hex
      License     - the SPDX expression the package declares
      Files       - the files taken out of the package:
                      Source - path inside the .nupkg
                      Target - path inside the module folder
                      Sha256 - expected SHA-256 of that file, lower-case hex

    net472 serves Windows PowerShell 5.1 (it needs .NET Framework 4.7.2 or later); net8.0 serves
    PowerShell 7.4 and later. Run ./Build/Update-DependencyLock.ps1 after changing the version.
#>
@{
    SchemaVersion = 1
    Artifacts     = @(
        @{
            Id      = 'Microsoft.SqlServer.TransactSql.ScriptDom'
            Version = '180.140.0'
            Url     = 'https://api.nuget.org/v3-flatcontainer/microsoft.sqlserver.transactsql.scriptdom/180.140.0/microsoft.sqlserver.transactsql.scriptdom.180.140.0.nupkg'
            Sha256  = 'e41dbe9238694c68d3a165c11880f9332905b4bb9759a604b1797bb3f282d217'
            License = 'MIT'
            Files   = @(
                @{
                    Source = 'lib/net472/Microsoft.SqlServer.TransactSql.ScriptDom.dll'
                    Target = 'lib/net472/Microsoft.SqlServer.TransactSql.ScriptDom.dll'
                    Sha256 = '5285a719b034730847284c514d454614bae137f4aef79868a1455abfdc6baf0b'
                }
                @{
                    Source = 'lib/net8.0/Microsoft.SqlServer.TransactSql.ScriptDom.dll'
                    Target = 'lib/net8.0/Microsoft.SqlServer.TransactSql.ScriptDom.dll'
                    Sha256 = '1f95f522e68d6232430fb2c00280f16f248bef46b50cb4fbc1ffd555edbf1604'
                }
            )
        }
    )
}
