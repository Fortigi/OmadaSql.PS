# Contributing to OmadaSql.PS

Thanks for helping improve the module. This page covers the few things that are specific to this
repository: the one rule we ask every change to follow, where the tests live, and how a pull
request gets validated.

## Every bug fix ships with its regression test

**A pull request that fixes a bug must also add the test that would have caught it.**

Not a test that exercises the area in general: the test that fails on the code as it was, and
passes on the code as it is. Write it first if you can; if you write it afterwards, revert your
fix once and watch the test go red, so you know it is actually testing the fix.

The same applies, in spirit, to a feature: land it with tests for the behaviour you are promising.

If a fix genuinely cannot be tested - it only reproduces against a live tenant - say so in the pull
request and explain why. Usually the answer is a seam: every request this module makes goes through
one private function that calls `Invoke-OmadaRestMethod`, so a test mocks that one call.

## Where the tests live

| Location | What it holds | When to add here |
|---|---|---|
| `Tests/Unit/<FunctionName>.Tests.ps1` | Pester unit tests for one function, usually via `InModuleScope 'OmadaSql.PS'`. Named after the function: the mutation gate maps a source file to its tests by that name. | Anything that is logic. Most tests belong here. |
| `Tests/Unit/*.Tests.ps1` (other names) | Repository invariants: workflow pins and permissions, the ruleset, the quality gate configuration, release packaging. | When you add a rule about the repository itself. |
| `Tests/Integration/*.Tests.ps1` | Tests that go through the real OmadaWeb.PS to a local `HttpListener` that answers like Omada (`Tests/Integration/Helpers/OmadaSqlMockServer.ps1`). | Behaviour that only appears once a real HTTP response comes back: the error records `Invoke-OmadaRestMethod` produces, body encoding, paging, temporary-object cleanup. |
| `Tests/Tenant` | The tenant test: the automated steps of [docs/TENANT-TEST.md](docs/TENANT-TEST.md), run by hand with `Tests/Tenant/Invoke-OmadaSqlTenantTest.ps1` against a test tenant. Its files do not end in `.Tests.ps1`, so the build never runs them; `Tests/Unit/TenantTest.Tests.ps1` keeps them parseable and in step with the checklist. | A behaviour that only a real tenant can show. Add the step to the checklist and the test file together, with general queries only (constants, `VALUES`, the data connection's schema). |
| Tests tagged `E2E` | Runs against a real Omada tenant. | Excluded from every build. There is no tenant-backed CI lane yet. |

Three things worth knowing before you write one:

- **Tests run against the built module**, not the source tree: the build passes `-ModulePath` to
  each file pointing at `buildoutput`. Keep the `param([string]$ModulePath = ...)` header the
  existing files use, so the file works both ways.
- **Every test run enables `Set-StrictMode -Version Latest`** inside the module, and that reaches
  into `InModuleScope` blocks. Reading a variable or property that does not exist is an error, not
  `$null`.
- **Nothing may reach the network or a real tenant.** Mock `Invoke-OmadaRestMethod`, or bring an
  `HttpListener`.

Tests run on Windows PowerShell 5.1 and PowerShell 7. A test file that needs PowerShell 7 (the
repository-level suites do) starts with `#Requires -Version 7.0` and is skipped on the 5.1 leg.

## Running the tests

```powershell
# Analyzer + build + import on both editions + help check + tests. This is what CI runs on a pull request.
./Build/build.ps1 -Task TestBuildOnly -BuildVersion '0.0.0'

# A single file, against the source module
Invoke-Pester -Path ./Tests/Unit/StrictMode.Tests.ps1 -Output Detailed
```

PSScriptAnalyzer gates the build. The repository's PowerShell conventions are Stroustrup braces,
no aliases, full cmdlet names in correct casing, spaces around operators, and aligned hashtable
values. Commands that change state in Omada support `-WhatIf` and `-Confirm`.

Every exported command needs comment-based help with a synopsis, a description, a `.PARAMETER`
entry per parameter, at least three examples and a related link; `Build/Test-CommentBasedHelp.ps1`
fails the build otherwise. Add each new public command to `Build/PublicCommands.psd1`, and run
`./Build/Update-ReadmeHelp.ps1` to regenerate the command table in the README: the build fails while
it is out of date.

## Complexity and mutation gates

Two more gates judge the code rather than the tests' pass/fail result. Both are requirements: a
pull request is not merged while either fails. Both need PowerShell 7.4 and read their policy from
`Build/QualityGates.psd1`.

| Gate | Tool | Bar |
|---|---|---|
| Complexity | [PSComplexity](https://github.com/Fortigi/PSComplexity) | Every function at or under 15 cyclomatic and 15 cognitive. Functions over that are recorded in `complexity-baseline.json` and may not get worse. The baseline starts empty. |
| Mutation | [PSMutant](https://github.com/Fortigi/PSMutant) | Small faults injected into the source (`-eq` to `-ne`, `$true` to `$false`, a dropped `-not`) must make a test fail. The score over all mutated files must stay at or above `Thresholds.Break`, and every single file with mutants at or above `Thresholds.FileBreak`, so a weakly tested file cannot hide behind well-tested ones. Every line is mutated, including lines no test executes (`CoveredLinesOnly = $false`), so untested code lowers the score. That includes parameter declarations (`Mandatory`, `Position`, pipeline binding, `ValidateRange`), which no test executes: each test file ends with a `<File> parameter contract` block asserting them through `Get-OmadaSqlParameterContract`, and a literal default needs a test that omits the parameter. Changed source without an owning `Tests/Unit/<FunctionName>.Tests.ps1` fails the gate (`RequireOwningTest`). A mutant no test can tell apart from the original is declared in `Equivalents` with the reason, never left to lower the score. |

On a pull request both run on **the files the pull request changed only**, after the tests, on the
pwsh leg of `/validate`, and report as the `Quality gates (changed code)` check. Every week both
run on the whole tree (`.github/workflows/quality-weekly.yml`) together with a freshness check of
the pinned build modules, and file one issue per failing gate; the issue closes itself once the
gate passes again.

```powershell
# What the weekly run does
./Build/build.ps1 -Task QualityFull

# After simplifying a function recorded in the baseline
./Build/build.ps1 -Task UpdateComplexityBaseline
```

## Bundled binaries

The module ships one third-party binary: the T-SQL parser `Microsoft.SqlServer.TransactSql.ScriptDom`
(MIT), in a `net472` build for Windows PowerShell 5.1 and a `net8.0` build for PowerShell 7. It is not
committed. The build runs `Build/Get-BundledDependency.ps1`, which downloads the package, checks the
package and each extracted file against the SHA-256 in `Build/DependencyLock.psd1`, and places the
files under `OmadaSql.PS/lib` (gitignored) and in the package.

Dependabot proposes new versions in `Build/Dependencies/Dependencies.csproj`. On such a branch run

```powershell
./Build/Update-DependencyLock.ps1
```

to pin the new hashes, review the diff of `Build/DependencyLock.psd1`, and commit it.
`Tests/Unit/DependencyLock.Tests.ps1` fails while the two disagree. The SBOM attached to each
nightly and release (`Build/New-Sbom.ps1`) is built from the same lock file, so it follows without
a separate change.

## Pinning GitHub Actions

Every `uses:` in `.github/workflows` references a full 40-character commit SHA with the release it
belongs to as a trailing comment:

```yaml
uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
```

Not a tag: a tag can be moved after review. Dependabot reads the comment and updates the SHA and the
comment together. `Tests/Unit/WorkflowActionPins.Tests.ps1` fails PR validation on any reference
that is not pinned this way, and `Tests/Unit/WorkflowPermissions.Tests.ps1` on any workflow-level
write permission.

## Branches

| Kind | Format |
|---|---|
| Feature | `feature/<description>` |
| Bug fix | `bugfix/<description>` |
| Hotfix | `hotfix/<description>` |
| Docs | `docs/<description>` |
| Release | `release/v<major>.<minor>.<patch>.<build>[-nightly]` |

`<description>` is lowercase, words separated by hyphens or underscores. Branch from `main`.

## Pull requests

1. Open the pull request against `main`. Describe what broke or was missing, what changed, and how
   you verified it, including the judgement calls a reviewer could reasonably have made
   differently.
2. **Validation does not start on its own.** Comment `/validate` on the pull request. Post it as
   the most recent comment; a newer `/validate` supersedes an earlier run rather than racing it.
   The branch has to be up to date with `main`.
3. Resolve every review thread, automated ones included, before asking for a merge. Merges are
   squash merges (see [the ruleset](SECURITY.md#branch-ruleset-on-main)).

Please do not add AI-attribution trailers (`Co-Authored-By: Claude` and similar) to commits or
pull request descriptions.
