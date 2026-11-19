Properties {
    $Version = $BuildVersion
    $Date = Get-Date
    $ModuleName = "OmadaSql.PS"
    $ParentPath = (Get-Item -Path $PSScriptRoot -Verbose:$false).Parent.FullName
    $ModuleSource = Join-Path -Path $ParentPath -ChildPath $ModuleName
    $TestSource = Join-Path -Path $ParentPath -ChildPath 'Tests'
    $OutputDir = Join-Path -Path $ParentPath -ChildPath ('buildoutput\{0}' -f $ModuleName)
    New-Item -Path $OutputDir -ItemType Directory -Force | Out-Null
    $QualityOutputDir = Join-Path -Path $ParentPath -ChildPath 'buildoutput\quality'
    $QualityGateSettingPath = Join-Path -Path $PSScriptRoot -ChildPath 'QualityGates.psd1'
}

# Every lane gets the same package: Build produces the complete module on its own, and the test
# tasks run against what Build produced, not against the source tree.
Task default -depends Analyze, Build, ImportModule, TestHelp, Test
# QualityChanged is a no-op outside pull request validation (no PR_CHANGED_FILES) and under Windows
# PowerShell 5.1 (PSComplexity and PSMutant need 7.4), so a local TestBuildOnly does not pay for
# mutation testing and the powershell leg of PR validation is unaffected.
Task TestBuildOnly -depends Analyze, Build, ImportModule, TestHelp, Test, QualityChanged

# Complexity and mutation-testing gates. Policy in Build\QualityGates.psd1, functions in
# Build\QualityGates.ps1, accepted legacy complexity in complexity-baseline.json.
. (Join-Path -Path $PSScriptRoot -ChildPath 'QualityGates.ps1')

Task Analyze {
    $SaProfile = @{
        Severity     = @('Error', 'Warning')
        IncludeRules = '*'
        ExcludeRules = '*WriteHost', '*AvoidUsingEmptyCatchBlock*', '*AvoidOverwritingBuiltInCmdlets*', '*UseToExportFieldsInManifest*', '*UseProcessBlockForPipelineCommand*'
    }
    $SaResults = @(Invoke-ScriptAnalyzer -Path $ModuleSource -Severity @('Error', 'Warning') -Recurse -Profile $SaProfile -Verbose:$false)
    if ($SaResults.Count -gt 0) {
        $SaResults | Format-Table -AutoSize | Out-String -Width 4096 | Write-Host
        Write-Error -Message 'One or more Script Analyzer errors/warnings were found. Build cannot continue!' -ErrorAction "Stop"
    }
}

Task Build -depends Analyze {

    $FormattingSettings = @{
        IncludeRules = @("PSPlaceOpenBrace", "PSUseConsistentIndentation", "PsAvoidUsingCmdletAliases", "PSUseConsistentWhitespace", "PSAlignAssignmentStatement", "PSPlaceCloseBrace")
        Rules        = @{
            PSPlaceOpenBrace           = @{
                Enable             = $true
                OnSameLine         = $true
                NewLineAfter       = $true
                IgnoreOneLineBlock = $true
            }
            PSUseConsistentIndentation = @{
                Enable = $true
            }
            PsAvoidUsingCmdletAliases  = @{
                Enable = $true
            }
            PSUseConsistentWhitespace  = @{
                Enable                                  = $false
                CheckInnerBrace                         = $true
                CheckOpenBrace                          = $false
                CheckOpenParen                          = $false
                CheckOperator                           = $true
                CheckPipe                               = $true
                CheckPipeForRedundantWhitespace         = $false
                CheckSeparator                          = $true
                CheckParameter                          = $true
                IgnoreAssignmentOperatorInsideHashTable = $false
            }
            PSAlignAssignmentStatement = @{
                Enable         = $true
                CheckHashtable = $true
            }
            PSPlaceCloseBrace          = @{
                Enable             = $true
                NoEmptyLineBefore  = $false
                IgnoreOneLineBlock = $true
                NewLineAfter       = $true
            }
        }
    }

    function New-HeaderRow {
        param(
            [string]$Text,
            [int]$Length = 100,
            [char]$BeginChar = "#",
            [char]$FillChar = " ",
            [char]$EndChar = "#"
        )
        $HeaderRow = "{0}{1}" -f $BeginChar, $FillChar
        $HeaderRow += $Text
        do {
            $HeaderRow += $FillChar
        }
        until ($HeaderRow.Length -gt ($Length - 1))
        $HeaderRow += "{0}`n" -f $EndChar
        return $HeaderRow
    }

    function Select-ModuleSourceLine {
        # The single .psm1 that ships to the Gallery is assembled by concatenating the source files,
        # dropping their comments to keep it compact. Comment-based help has to survive that though,
        # otherwise Get-Help returns nothing for the exported commands, so lines inside a block
        # comment are kept for the public functions (-KeepCommentBasedHelp) and dropped for
        # everything else.
        param(
            [string[]]$Line,
            [switch]$KeepCommentBasedHelp
        )

        $Output = [System.Collections.Generic.List[string]]::new()
        $InBlockComment = $false

        foreach ($CurrentLine in $Line) {
            if ($InBlockComment) {
                if ($KeepCommentBasedHelp) {
                    $Output.Add($CurrentLine)
                }
                if ($CurrentLine -match '#>') {
                    $InBlockComment = $false
                }
                continue
            }
            if ($CurrentLine -match '^\s*<#' -and $CurrentLine -notmatch '#>') {
                $InBlockComment = $true
                if ($KeepCommentBasedHelp) {
                    $Output.Add($CurrentLine)
                }
                continue
            }
            if ($CurrentLine -match '^\s*#') {
                continue
            }
            $Output.Add($CurrentLine)
        }
        return $Output.ToArray()
    }

    . (Join-Path $PSScriptRoot -ChildPath 'ConvertTo-HashtableDeep.ps1')

    $Public = @(Get-ChildItem -Path (Join-Path $ModuleSource -ChildPath 'Public\*.ps1') -Recurse | Where-Object { $_.Name -notlike "_*.ps1" } | Sort-Object -Property Name)
    $Private = @(Get-ChildItem -Path (Join-Path $ModuleSource -ChildPath 'Private\*.ps1') -Recurse | Where-Object { $_.Name -notlike "_*.ps1" } | Sort-Object -Property Name)
    $PublicFunctionNames = @($Public | ForEach-Object { $_.BaseName })

    $ModulePsd1 = Import-PowerShellDataFile (Join-Path $ModuleSource -ChildPath ("{0}.psd1" -f $ModuleName))
    $ModulePsd1.FunctionsToExport = $PublicFunctionNames

    try {
        $CurrentModulePsd1 = Import-PowerShellDataFile (Join-Path -Path $OutputDir -ChildPath ("{0}.psd1" -f $ModuleName))
    }
    catch {
        $CurrentModulePsd1 = $null
    }

    if (![String]::IsNullOrWhiteSpace($Version)) {
        [System.Version]$NewVersion = "{0}" -f $Version
    }
    else {
        [System.Version]$NewVersion = $Date.ToString('yyyy.MM.dd.001')
        if ($CurrentModulePsd1) {
            [System.Version]$CurrentModuleVersion = $CurrentModulePsd1.ModuleVersion
            if ($CurrentModuleVersion -ge $NewVersion) {
                $NewVersion = New-Object System.Version($CurrentModuleVersion.Major, $CurrentModuleVersion.Minor, $CurrentModuleVersion.Build, ($CurrentModuleVersion.Revision + 1))
            }
        }
    }

    $ModulePsd1.ModuleVersion = $NewVersion
    $ModulePsd1.Copyright = $ModulePsd1.Copyright -f $Date.ToString("yyyy")

    # Work-around for the bug in New-ModuleManifest that breaks the PrivateData key
    # (https://github.com/PowerShell/PowerShell/issues/5922).
    $PrivateData = ConvertTo-HashtableDeep ($ModulePsd1.PrivateData | ConvertTo-Json -Depth 10 | ConvertFrom-Json)
    $ModulePsd1.Remove("PrivateData")

    $SerializedContent = $PrivateData.GetEnumerator() | ForEach-Object {
        if ($_ -is [System.Collections.DictionaryEntry]) {
            $String = "$($_.Key) = @{"
            if ($_.Value -is [System.Collections.Hashtable]) {
                $_.Value.GetEnumerator() | ForEach-Object {
                    $String += "`n"
                    if (($_.Value | Measure-Object).Count -gt 1) {
                        $String += "{0} = @({1})" -f $_.Key, (($_.Value | ForEach-Object { "`"{0}`"" -f $_ }) -join ",")
                    }
                    else {
                        $String += "{0} = `"{1}`"" -f $($_.Key) , $($_.Value)
                    }
                }
                return $String
            }
        }
    }

    $ModulePsd1Path = Join-Path $OutputDir -ChildPath ("{0}.psd1" -f $ModuleName)
    New-ModuleManifest -Path $ModulePsd1Path @ModulePsd1
    (Get-Content -Path $ModulePsd1Path) -replace 'PSData = @{', $SerializedContent | Set-Content -Path $ModulePsd1Path -Encoding UTF8 -Force
    "Module psd1 output file: {0}" -f $ModulePsd1Path | Write-Host -ForegroundColor Magenta
    (Get-Content $ModulePsd1Path -Raw) -replace "`r?`n", "`r`n" | Invoke-Formatter -Settings $FormattingSettings | Set-Content -Path $ModulePsd1Path -Encoding UTF8 -Force

    $Length = 150
    $ModuleContent = New-HeaderRow -Text "" -Length $Length -FillChar "#"
    $ModuleContent += New-HeaderRow -Text "WARNING: DO NOT EDIT THIS FILE AS IT IS GENERATED AND WILL BE OVERWRITTEN ON THE NEXT UPDATE!" -Length $Length -FillChar " "
    $ModuleContent += New-HeaderRow -Text "" -Length $Length -FillChar " "
    $ModuleContent += New-HeaderRow -Text ('Generated via psake on: {0}' -f $Date.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")) -Length $Length -FillChar " "
    $ModuleContent += New-HeaderRow -Text ("Version: {0}" -f $NewVersion.ToString()) -Length $Length -FillChar " "
    $ModuleContent += New-HeaderRow -Text ("Copyright Fortigi (C) {0}" -f $Date.ToString("yyyy")) -Length $Length -FillChar " "
    $ModuleContent += New-HeaderRow -Text "" -Length $Length -FillChar "#"
    $ModuleContent += "`n`n"

    $ScriptContent = Get-Content -Path (Join-Path $ModuleSource -ChildPath ("{0}.psm1" -f $ModuleName)) -Encoding UTF8 -ErrorAction Stop
    $ExcludeRegion = $false
    $FunctionsAdded = $false
    foreach ($Line in $ScriptContent) {
        if ($Line -match "^\s*#region\s+exclude") {
            $ExcludeRegion = $true
            continue
        }
        if ($ExcludeRegion) {
            if ($Line -match "^\s*#endregion") {
                $ExcludeRegion = $false
            }
            if (!$FunctionsAdded) {
                "Adding functions" | Write-Host -ForegroundColor Magenta
                $ModuleContent += "#region public functions`n"
                foreach ($Import in $Public) {
                    $Content = Select-ModuleSourceLine -Line (Get-Content $Import.FullName -Encoding UTF8) -KeepCommentBasedHelp
                    $ModuleContent += ($Content -join "`n").Trim()
                    $ModuleContent += "`n`n"
                }
                $ModuleContent += "#endregion`n`n#region private functions`n"
                foreach ($Import in $Private) {
                    $Content = Select-ModuleSourceLine -Line (Get-Content $Import.FullName -Encoding UTF8)
                    $ModuleContent += ($Content -join "`n").Trim()
                    $ModuleContent += "`n`n"
                }
                $ModuleContent += "#endregion`n`n"
                $FunctionsAdded = $true
            }
            continue
        }
        if ($Line -notmatch '^\s*#') {
            $ModuleContent += $Line + "`n"
        }
    }
    if (!$FunctionsAdded) {
        Write-Error -Message ("{0}.psm1 has no '#region exclude' block, so no functions were added to the built module." -f $ModuleName) -ErrorAction Stop
    }

    if ($PublicFunctionNames.Count -gt 0) {
        $ModuleContent += "Export-ModuleMember -Function @(""{0}"")`n" -f ($PublicFunctionNames -join '", "')
    }

    $ModuleContent = $ModuleContent -replace "`r?`n", "`r`n" | Invoke-Formatter -Settings $FormattingSettings
    if (($ModuleContent | Select-String -SimpleMatch "Wait-Debugger" -AllMatches | Measure-Object).Count -gt 0) {
        Write-Error -Message "Use of 'Wait-Debugger' found in the module source. Remove it before building the module." -ErrorAction Stop
    }
    $OutputDirFile = Join-Path -Path $OutputDir -ChildPath ("{0}.psm1" -f $ModuleName)
    "Module psm1 output file: {0}" -f $OutputDirFile | Write-Host -ForegroundColor Magenta
    $ModuleContent | Out-File -FilePath $OutputDirFile -Encoding UTF8 -Force

    "Copy nuspec file" | Write-Host -ForegroundColor Magenta
    Copy-Item -Path (Join-Path $ParentPath -ChildPath ("{0}.nuspec" -f $ModuleName)) -Destination $OutputDir -Force

    # Everything the manifest promises has to be on disk before anything downstream believes it.
    "Verify package contents against the manifest" | Write-Host -ForegroundColor Magenta
    & (Join-Path $PSScriptRoot -ChildPath "Confirm-PackageFileList.ps1") -PackagePath $OutputDir
}

Task ImportModule -depends Build {
    # The manifest requires OmadaWeb.PS. Install-Module -Scope CurrentUser puts it under the module
    # path of the edition that ran InstallModules.ps1 only (Documents\PowerShell\Modules for pwsh,
    # Documents\WindowsPowerShell\Modules for powershell.exe), which the other edition does not
    # search. Its folder is therefore handed to each child process explicitly.
    $BuildModules = Import-PowerShellDataFile -Path (Join-Path -Path $PSScriptRoot -ChildPath 'BuildModules.psd1')
    $OmadaWebPin = @($BuildModules.Modules | Where-Object { $_.Name -eq 'OmadaWeb.PS' })[0]
    $OmadaWebModule = @(Get-Module -Name 'OmadaWeb.PS' -ListAvailable | Where-Object { $_.Version -eq [version]$OmadaWebPin.RequiredVersion })[0]
    if ($null -eq $OmadaWebModule) {
        Write-Error -Message ("OmadaWeb.PS {0} is not installed. Run ./Build/InstallModules.ps1 first." -f $OmadaWebPin.RequiredVersion) -ErrorAction Stop
    }
    # ModuleBase is <modules folder>\OmadaWeb.PS\<version>.
    $DependencyModulePath = Split-Path -Path (Split-Path -Path $OmadaWebModule.ModuleBase -Parent) -Parent

    $ScriptBlock = {
        param (
            [string]$OutputDir,
            [string]$ModuleName,
            [string]$DependencyModulePath
        )
        $ErrorActionPreference = "Stop"
        try {
            $Env:PSModulePath = "{0}{1}{2}" -f $DependencyModulePath, [System.IO.Path]::PathSeparator, $Env:PSModulePath
            $null = Test-ModuleManifest -Path "$OutputDir\$ModuleName.psd1"

            # The module runs in its own session state and reads OMADASQLPS_STRICTMODE itself.
            $PreviousStrictMode = $Env:OMADASQLPS_STRICTMODE
            $Env:OMADASQLPS_STRICTMODE = "1"
            try {
                $Imported = Import-Module "$OutputDir\$ModuleName.psd1" -Force -PassThru
            }
            finally {
                $Env:OMADASQLPS_STRICTMODE = $PreviousStrictMode
            }

            if (!$Imported) {
                throw "Module failed to load"
            }
            "Module loaded successfully on {0} {1}" -f $PSVersionTable.PSEdition, $PSVersionTable.PSVersion | Write-Host
            Remove-Module -Name $Imported.Name -Force
        }
        catch {
            $PSCmdlet.ThrowTerminatingError($PSItem)
        }
    }

    # Both editions are supported, so both have to load the package. A child process per edition
    # also keeps this session free of the imported module.
    foreach ($Shell in 'powershell.exe', 'pwsh.exe') {
        $ShellCommand = Get-Command -Name $Shell -ErrorAction SilentlyContinue
        if ($null -eq $ShellCommand) {
            Write-Error -Message ("{0} is not available; the module has to be import-tested on both Windows PowerShell and PowerShell 7." -f $Shell) -ErrorAction Stop
        }
        "Testing module import on {0}" -f $Shell | Write-Host -ForegroundColor Magenta
        & $ShellCommand.Source -NoProfile -NoLogo -ExecutionPolicy Bypass -Command $ScriptBlock -Args @($OutputDir, $ModuleName, $DependencyModulePath)
        if ($LASTEXITCODE -ne 0) {
            Write-Error -Message ("Importing the built module failed on {0}." -f $Shell) -ErrorAction Stop
        }
    }
}

# Checks the assembled module rather than the source files, so it also proves the comment-based help
# survived being concatenated into the single .psm1 that ships to the Gallery.
Task TestHelp -depends ImportModule {
    & (Join-Path $PSScriptRoot -ChildPath "Test-CommentBasedHelp.ps1") -ModuleManifestPath (Join-Path -Path $OutputDir -ChildPath ("{0}.psd1" -f $ModuleName))
    & (Join-Path $PSScriptRoot -ChildPath "Update-ReadmeHelp.ps1") -Check -ModuleManifestPath (Join-Path -Path $OutputDir -ChildPath ("{0}.psd1" -f $ModuleName))
}

Task Test -depends ImportModule {
    $Tests = @(Get-ChildItem -Path $TestSource -Filter *.Tests.ps1 -Recurse)
    if ($PSVersionTable.PSVersion.Major -lt 7) {
        # Repository-level suites (workflows, quality gates, release packaging) declare
        # '#Requires -Version 7.0' and only run on the pwsh leg. Pester would report each of them as
        # a failed container under Windows PowerShell, so they are left out here instead.
        $Skipped = @($Tests | Where-Object { (Get-Content -LiteralPath $_.FullName -TotalCount 5) -match '^\s*#Requires\s+-Version\s+7' })
        foreach ($SkippedTest in $Skipped) {
            "Skip {0}: requires PowerShell 7 (running {1})" -f $SkippedTest.Name, $PSVersionTable.PSVersion | Write-Host
        }
        $Tests = @($Tests | Where-Object { $_.FullName -notin $Skipped.FullName })
    }
    if ($Tests.Count -eq 0) {
        'No tests found' | Write-Warning
        return
    }

    $ModulePsm1Path = Join-Path -Path $OutputDir -ChildPath ("{0}.psm1" -f $ModuleName)
    $Container = New-PesterContainer -Path $Tests.FullName -Data @{ ModulePath = $ModulePsm1Path }

    $PesterConfiguration = New-PesterConfiguration
    $PesterConfiguration.Run.Container = $Container
    $PesterConfiguration.Run.PassThru = $true
    $PesterConfiguration.TestResult.Enabled = $true
    $PesterConfiguration.TestResult.OutputFormat = 'JUnitXml'
    $PesterConfiguration.TestResult.OutputPath = (Join-Path -Path $ParentPath -ChildPath 'buildoutput\TestResults.xml')
    $PesterConfiguration.Output.Verbosity = 'Detailed'
    # E2E tests need a real tenant; they are never part of a build.
    $PesterConfiguration.Filter.ExcludeTag = 'E2E'

    # Every test run exercises the module under Set-StrictMode -Version Latest (see OmadaSql.PS.psm1).
    $PreviousStrictMode = $Env:OMADASQLPS_STRICTMODE
    $Env:OMADASQLPS_STRICTMODE = "1"
    try {
        $Result = Invoke-Pester -Configuration $PesterConfiguration
    }
    finally {
        $Env:OMADASQLPS_STRICTMODE = $PreviousStrictMode
        # Every copy the test files imported, in whatever scope, is removed: the mutation gate runs
        # the tests again in this session, and Pester's InModuleScope refuses to run while two
        # modules of the same name are loaded.
        Get-Module -Name $ModuleName -All | Remove-Module -Force -ErrorAction SilentlyContinue
    }

    if ($Result.FailedCount -gt 0) {
        Write-Error -Message ("{0} Pester test(s) failed." -f $Result.FailedCount) -ErrorAction Stop
    }
}

# Pull request lane: holds only the code the pull request changed to the bar. Writes
# buildoutput\quality\changed-summary.json for the "Quality gates (changed code)" check run, then
# fails the build if a gate failed.
Task QualityChanged -precondition { $PSVersionTable.PSVersion -ge [version]'7.4' } {
    New-Item -Path $QualityOutputDir -ItemType Directory -Force | Out-Null
    $SummaryPath = Join-Path -Path $QualityOutputDir -ChildPath 'changed-summary.json'

    if (-not $env:PR_CHANGED_FILES) {
        "Quality gates (changed code): not a pull request validation run, skipped." | Write-Host
        return
    }

    $Setting = Get-QualityGateSetting -Path $QualityGateSettingPath
    $Changed = @(Select-QualityChangedFile -RepositoryRoot $ParentPath -ChangedFile ($env:PR_CHANGED_FILES -split ';') -SourcePath $Setting.Complexity.SourcePath)
    if ($Changed.Count -eq 0) {
        $Message = ('No PowerShell source under `{0}` changed, so there was nothing to measure.' -f ($Setting.Complexity.SourcePath -join '`, `'))
        $Message | Write-Host
        [pscustomobject]@{ Status = 'skipped'; Title = 'No PowerShell source changed'; Markdown = $Message } |
            ConvertTo-Json | Set-Content -Path $SummaryPath -Encoding utf8
        return
    }
    "Quality gates (changed code) for {0} file(s):`n  {1}" -f $Changed.Count, ($Changed -join "`n  ") | Write-Host

    Push-Location -Path $ParentPath
    try {
        $BaselinePath = Join-Path -Path $ParentPath -ChildPath $Setting.Complexity.BaselineFile
        $Orphaned = @(Get-OrphanedBaselineEntry -BaselineFile $BaselinePath -RepositoryRoot $ParentPath)
        $ScopedBaseline = New-ScopedComplexityBaseline -BaselineFile $BaselinePath -ChangedFile $Changed -OutputPath (Join-Path -Path $QualityOutputDir -ChildPath 'complexity-baseline.changed.json')
        $Complexity = Invoke-ComplexityGate -RepositoryRoot $ParentPath -Setting $Setting.Complexity -ChangedFile $Changed -BaselineFile $ScopedBaseline -ReportPath (Join-Path -Path $QualityOutputDir -ChildPath 'complexity.changed.json')
        $Mutation = Invoke-MutationGate -RepositoryRoot $ParentPath -Setting $Setting.Mutation -ChangedFile $Changed -OutputDirectory $QualityOutputDir
    }
    finally {
        Pop-Location
    }

    $ComplexityPassed = $Complexity.Passed -and $Orphaned.Count -eq 0
    $Passed = $ComplexityPassed -and $Mutation.Passed

    $Markdown = [System.Collections.Generic.List[string]]::new()
    $Markdown.Add(('Measured {0} changed file(s): {1}' -f $Changed.Count, (($Changed | ForEach-Object { '`{0}`' -f $_ }) -join ', ')))
    $Markdown.Add('')
    $Markdown.Add(('## {0} Complexity (max {1} cyclomatic / {2} cognitive per unit)' -f $(if ($ComplexityPassed) { 'PASS' } else { 'FAIL' }), $Setting.Complexity.MaxCyclomatic, $Setting.Complexity.MaxCognitive))
    $Markdown.Add('')
    $Markdown.Add('A unit listed in `complexity-baseline.json` may not get worse; any other unit must be under the ceilings.')
    $Markdown.Add('')
    $Markdown.Add($Complexity.Markdown)
    if ($Orphaned.Count -gt 0) {
        $Markdown.Add('')
        $Markdown.Add(('`complexity-baseline.json` names files that no longer exist: {0}. Run `./Build/build.ps1 -Task UpdateComplexityBaseline` and commit the result.' -f (($Orphaned | ForEach-Object { '`{0}`' -f $_.file } | Sort-Object -Unique) -join ', ')))
    }
    $Markdown.Add('')
    $Markdown.Add(('## {0} Mutation testing' -f $(if (-not $Mutation.Passed) { 'FAIL' } elseif ($Mutation.Skipped) { 'SKIPPED' } else { 'PASS' })))
    $Markdown.Add('')
    $Markdown.Add($Mutation.Markdown)
    if ($Mutation.Untested.Count -gt 0) {
        $Markdown.Add('')
        $Markdown.Add(('Changed source with no owning unit test file (`Tests/Unit/<FunctionName>.Tests.ps1`), so no test strength could be measured: {0}' -f (($Mutation.Untested | ForEach-Object { '`{0}`' -f $_ }) -join ', ')))
    }

    $Title = if ($Passed) { 'Changed code meets the quality gates' } else { 'Changed code does not meet the quality gates' }
    if (-not $Mutation.Skipped) {
        $Title = '{0} (mutation score {1}%)' -f $Title, $Mutation.Score
    }
    [pscustomobject]@{
        Status   = if ($Passed) { 'passed' } else { 'failed' }
        Title    = $Title
        Markdown = Limit-MarkdownLength -Text ($Markdown -join "`n")
    } | ConvertTo-Json | Set-Content -Path $SummaryPath -Encoding utf8

    if (-not $Passed) {
        Write-Error -Message 'The changed code does not meet the complexity and/or mutation-testing gates. See buildoutput\quality\changed-summary.json.' -ErrorAction Stop
    }
}

# Weekly lane (.github/workflows/quality-weekly.yml): holds the whole tree to the bar. One result per
# gate - complexity, mutation, build module pins - in buildoutput\quality\weekly.json, from which the
# workflow opens, updates or closes one issue per gate.
Task QualityFull -precondition { $PSVersionTable.PSVersion -ge [version]'7.4' } {
    New-Item -Path $QualityOutputDir -ItemType Directory -Force | Out-Null
    $Setting = Get-QualityGateSetting -Path $QualityGateSettingPath

    Push-Location -Path $ParentPath
    try {
        $Complexity = Invoke-ComplexityGate -RepositoryRoot $ParentPath -Setting $Setting.Complexity -ReportPath (Join-Path -Path $QualityOutputDir -ChildPath 'complexity.json') -SarifPath (Join-Path -Path $QualityOutputDir -ChildPath 'complexity.sarif')
        $Baseline = Invoke-ComplexityGate -RepositoryRoot $ParentPath -Setting $Setting.Complexity -BaselineFile (Join-Path -Path $ParentPath -ChildPath $Setting.Complexity.BaselineFile) -ReportPath (Join-Path -Path $QualityOutputDir -ChildPath 'complexity.baseline.json')
        $Mutation = Invoke-MutationGate -RepositoryRoot $ParentPath -Setting $Setting.Mutation -OutputDirectory $QualityOutputDir
    }
    finally {
        Pop-Location
    }
    $BuildModules = Import-PowerShellDataFile -Path (Join-Path -Path $PSScriptRoot -ChildPath 'BuildModules.psd1')
    $Pins = @(Get-ModulePinStatus -Pin $BuildModules.Modules)

    $ComplexityBody = @(
        ('**{0} unit(s) in {1} file(s)** are over {2} cyclomatic / {3} cognitive.' -f $Complexity.Violations.Count, @($Complexity.Violations | ForEach-Object { $_.File } | Sort-Object -Unique).Count, $Setting.Complexity.MaxCyclomatic, $Setting.Complexity.MaxCognitive)
        ''
        'Pull requests already hold changed code to the ceilings, with `complexity-baseline.json` letting a unit that was over them stay - but not get worse. Bring a unit under the ceilings, then run `./Build/build.ps1 -Task UpdateComplexityBaseline` to ratchet the baseline down.'
        ''
        $(if ($Baseline.Passed) { '**Baseline:** `complexity-baseline.json` describes the tree exactly.' } else { "**Baseline:** does not describe the tree.`n`n$($Baseline.Markdown)" })
        ''
        $Complexity.Markdown
    ) -join "`n"

    $StalePins = @($Pins | Where-Object { $_.IsStale })
    $UncheckedPins = @($Pins | Where-Object { $_.Error })
    $PinRows = $Pins | ForEach-Object { '| {0} | {1} | {2} | {3} |' -f $_.Name, $_.Pinned, $(if ($_.Latest) { $_.Latest } else { "_lookup failed: $($_.Error)_" }), $(if ($_.IsStale) { 'update available' } elseif ($_.Error) { 'unknown' } else { 'current' }) }
    $PinBody = @(
        'Pinned in `Build/BuildModules.psd1`. Dependabot does not cover the PowerShell Gallery, so this is where a new release shows up. Bump the version there and run `./Build/build.ps1 -Task TestBuildOnly` to adopt it.'
        ''
        '| Module | Pinned | Latest | Status |'
        '|---|---|---|---|'
        $PinRows
    ) -join "`n"

    $Gates = @(
        [pscustomobject]@{
            Key    = 'complexity'
            Title  = 'Weekly quality: complexity above {0}/{1}' -f $Setting.Complexity.MaxCyclomatic, $Setting.Complexity.MaxCognitive
            Passed = $Complexity.Passed -and $Baseline.Passed
            Metric = $Complexity.Violations.Count
            Body   = Limit-MarkdownLength -Text $ComplexityBody
        }
        [pscustomobject]@{
            Key    = 'mutation'
            Title  = 'Weekly quality: mutation score below threshold'
            Passed = $Mutation.Passed
            Metric = $Mutation.Score
            Body   = Limit-MarkdownLength -Text $Mutation.Markdown
        }
        [pscustomobject]@{
            Key    = 'pins'
            # A lookup that failed counts as a failure too: a freshness check that silently stopped
            # checking is the same as no check.
            Title  = 'Weekly quality: build module pins need attention'
            Passed = $StalePins.Count -eq 0 -and $UncheckedPins.Count -eq 0
            Metric = $StalePins.Count
            Body   = $PinBody
        }
    )
    [pscustomobject]@{ Gates = $Gates } | ConvertTo-Json -Depth 4 | Set-Content -Path (Join-Path -Path $QualityOutputDir -ChildPath 'weekly.json') -Encoding utf8

    foreach ($Gate in $Gates) {
        "{0} {1}" -f $(if ($Gate.Passed) { 'PASS' } else { 'FAIL' }), $Gate.Title | Write-Host
    }
    $Failed = @($Gates | Where-Object { -not $_.Passed })
    if ($Failed.Count -gt 0) {
        Write-Error -Message ('{0} quality gate(s) failed: {1}' -f $Failed.Count, (($Failed | ForEach-Object { $_.Key }) -join ', ')) -ErrorAction Stop
    }
}

# Ratchets complexity-baseline.json down after units improved, were renamed or were removed. Refuses
# to record a unit that got worse - that is a regression to fix, not to absorb.
Task UpdateComplexityBaseline -precondition { $PSVersionTable.PSVersion -ge [version]'7.4' } {
    $Setting = Get-QualityGateSetting -Path $QualityGateSettingPath
    $Files = @(Get-QualitySourceFile -RepositoryRoot $ParentPath -SourcePath $Setting.Complexity.SourcePath)
    if ($Files.Count -eq 0) {
        "No source files to measure." | Write-Host
        return
    }
    Push-Location -Path $ParentPath
    try {
        $null = Test-PSComplexity -Path ([string[]]$Files.FullName) -MaxCyclomatic $Setting.Complexity.MaxCyclomatic -MaxCognitive $Setting.Complexity.MaxCognitive -BaselineFile (Join-Path -Path $ParentPath -ChildPath $Setting.Complexity.BaselineFile) -UpdateBaseline -WarningAction SilentlyContinue
    }
    finally {
        Pop-Location
    }
    "Updated {0}. Review the diff and commit it." -f $Setting.Complexity.BaselineFile | Write-Host
}
