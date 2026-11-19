# deploy.ps1 installs the built module into a module folder, replacing what is there. It declares
# SupportsShouldProcess, so -WhatIf has to leave the target untouched.

BeforeDiscovery {
    $RepositoryRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    $Script:HasBuild = Test-Path -LiteralPath (Join-Path $RepositoryRoot 'buildoutput\OmadaSql.PS\OmadaSql.PS.psd1')
}

BeforeAll {
    $Script:RepositoryRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    $Script:DeployScript = Join-Path $Script:RepositoryRoot 'deploy.ps1'
}

Describe 'deploy.ps1' -Tag 'Unit' {
    It 'Changes nothing with -WhatIf' -Skip:(-not $Script:HasBuild) {
        $Manifest = Import-PowerShellDataFile -Path (Join-Path $Script:RepositoryRoot 'buildoutput\OmadaSql.PS\OmadaSql.PS.psd1')
        $Folder = if ($PSVersionTable.PSEdition -eq 'Desktop') { 'Documents\WindowsPowerShell\Modules' } else { 'Documents\PowerShell\Modules' }
        $Target = Join-Path $HOME -ChildPath ('{0}\OmadaSql.PS\{1}' -f $Folder, $Manifest.ModuleVersion)
        $ExistedBefore = Test-Path -LiteralPath $Target
        & $Script:DeployScript -Scope CurrentUser -WhatIf 6>$null
        Test-Path -LiteralPath $Target | Should -Be $ExistedBefore
    }

    It 'Keeps the license notice of the bundled parser in the deployed folder' {
        (Get-Content -LiteralPath $Script:DeployScript -Raw) | Should -Match '\$KeepFile = @\([^)]*"THIRD-PARTY-NOTICES\.md"'
    }
}
