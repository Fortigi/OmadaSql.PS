#
# Module manifest for module 'OmadaSql.PS'
#
# ModuleVersion and FunctionsToExport are placeholders: the build (Build/psakeBuild.ps1, task Build)
# writes the real version and the list of Public/*.ps1 functions into the manifest it ships.
#
@{
    RootModule           = 'OmadaSql.PS.psm1'
    ModuleVersion        = '0.0'
    CompatiblePSEditions = @(
        'Desktop',
        'Core'
    )
    GUID                 = 'cbccf0ae-806f-432a-9353-9717eb986651'
    Author               = 'Mark van Eijken'
    CompanyName          = 'Fortigi'
    Copyright            = '(C) {0} Fortigi All rights reserved.'
    Description          = 'PowerShell module to run SQL queries against Omada Identity Cloud through the SQL Troubleshooting endpoints, manage SQL Troubleshooting objects over OData, retrieve schema and history, validate queries and export results. Authentication is handled by OmadaWeb.PS.'
    PowerShellVersion    = '5.1'
    DotNetFrameworkVersion = '4.7.2'
    # The one runtime dependency. Every request goes through Invoke-OmadaRestMethod, so the minimum
    # version is the first that has NoInteractiveAuthentication and SkipBodyRedaction, which the
    # module relies on for unattended use.
    RequiredModules      = @(
        @{
            ModuleName    = 'OmadaWeb.PS'
            ModuleVersion = '2026.9.23.47'
        }
    )
    FunctionsToExport    = @()
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()
    FileList             = @(
        'OmadaSql.PS.psd1',
        'OmadaSql.PS.psm1',
        'THIRD-PARTY-NOTICES.md',
        'lib\net472\Microsoft.SqlServer.TransactSql.ScriptDom.dll',
        'lib\net8.0\Microsoft.SqlServer.TransactSql.ScriptDom.dll'
    )
    PrivateData          = @{
        PSData = @{
            Tags       = @('Omada', 'OmadaIdentity', 'SQL', 'OData', 'IdentityGovernance', 'Windows')
            LicenseUri = 'https://github.com/Fortigi/OmadaSql.PS/blob/main/LICENSE'
            ProjectUri = 'https://github.com/Fortigi/OmadaSql.PS'
        }
    }
}
