# Security Policy

OmadaSql.PS is used by identity administrators and unattended automation to run SQL against Omada
environments, so it handles tenant access, and query results that often contain production
identity data. Security reports are taken seriously and are handled privately.

## Supported versions

Only the most recent version published to the [PowerShell Gallery](https://www.powershellgallery.com/packages/OmadaSql.PS)
receives security fixes. Fixes are shipped as a new release rather than as patches to older versions.

| Version | Supported |
|---|---|
| Latest release on the PowerShell Gallery | :white_check_mark: |
| Any earlier release | :x: |

Run `Update-Module -Name OmadaSql.PS` to move to the supported version.

## Reporting a vulnerability

**Do not open a public GitHub issue for a security problem.**

Report privately through GitHub Security Advisories:

1. Go to <https://github.com/Fortigi/OmadaSql.PS/security/advisories/new>
2. Describe the issue and submit the draft advisory.

The report is visible only to the maintainers until an advisory is published. If GitHub is not
available to you, email `devops@fortigi.nl` with `OmadaSql.PS security` in the subject line.

### What to include

- The module version (`Get-Module OmadaSql.PS -ListAvailable`), the OmadaWeb.PS version and your
  PowerShell version (`$PSVersionTable`).
- Steps to reproduce, ideally as a minimal command sequence.
- The impact you believe the issue has.

Please redact real tokens, credentials, tenant names and query results from anything you send.

### Response expectations

| Stage | Target |
|---|---|
| Acknowledgement of your report | 3 business days |
| Initial assessment and severity classification | 10 business days |
| Fix or documented mitigation for high/critical findings | 30 calendar days after assessment |
| Public advisory | Published together with the fix release |

If a fix takes longer than these targets, you will be told why and given a revised date. Reporters
are credited in the advisory unless they ask not to be.

We ask that you give us a reasonable opportunity to ship a fix before disclosing publicly, and that
testing is limited to environments you own or are authorized to test.

## Scope

In scope:

- The PowerShell code in this repository.
- What the module writes to disk (exports, the temporary-query settings file) and what it writes to
  the Verbose and Debug streams.
- How the module creates, reuses and removes temporary SQL Troubleshooting objects in the tenant.
- How the module loads bundled assemblies (the SQL parser used by the syntax checker). The parser is
  pinned by version and SHA-256 in `Build/DependencyLock.psd1`; the build refuses a package or file
  whose hash differs, and the module downloads nothing at run time.

Out of scope:

- The Omada product itself. Report those to [Omada](https://www.omadaidentity.com/) directly.
- [OmadaWeb.PS](https://github.com/Fortigi/OmadaWeb.PS), which handles all authentication and REST
  traffic. Report those at that project, which has its own security policy.
- Vulnerabilities in third-party components. Report those to their maintainers; if this module
  ships an unsafe version or configuration of one, that part *is* in scope, so tell us as well.
- Findings that require an attacker to already have interactive access to the Windows account the
  module runs under.

## Automated security tooling

| Control | Where it is configured |
|---|---|
| Private vulnerability reporting | Repository settings - *Settings > Advanced Security > Private vulnerability reporting* |
| Secret scanning and push protection | Repository settings - *Settings > Advanced Security* |
| Dependabot version and security updates | [.github/dependabot.yml](.github/dependabot.yml) |
| Pre-merge vulnerability and licence gate on the dependency graph diff | [.github/workflows/dependency-review.yml](.github/workflows/dependency-review.yml) |
| Every external GitHub Actions `uses:` pinned to a full commit SHA | every workflow in [.github/workflows](.github/workflows), enforced by [Tests/Unit/WorkflowActionPins.Tests.ps1](Tests/Unit/WorkflowActionPins.Tests.ps1) |
| Least-privilege workflow permissions (no workflow-level write scope) | enforced by [Tests/Unit/WorkflowPermissions.Tests.ps1](Tests/Unit/WorkflowPermissions.Tests.ps1) |
| Runner egress monitoring (audit only) | `step-security/harden-runner`, first step of every job in every workflow |
| Static analysis (PSScriptAnalyzer) and Pester suites on Windows PowerShell 5.1 and PowerShell 7 | [Build/psakeBuild.ps1](Build/psakeBuild.ps1), run in PR validation |
| Branch protection | [.github/rulesets/protect-main.json](.github/rulesets/protect-main.json), see below |

### Branch ruleset on `main`

Branch protection is kept as code in [.github/rulesets/protect-main.json](.github/rulesets/protect-main.json),
the exact body of the GitHub rulesets API, and is applied by a maintainer with admin rights:

```powershell
./Build/Set-RepositoryRuleset.ps1 -WhatIf
./Build/Set-RepositoryRuleset.ps1
```

No workflow applies it: changing the rules that protect `main` is a maintainer's action, never an
automated one. [Tests/Unit/RepositoryRuleset.Tests.ps1](Tests/Unit/RepositoryRuleset.Tests.ps1)
keeps the file consistent with the checks the workflows actually report.

The ruleset **"Protect Main"**:

- requires a pull request, squash merges only, with every review thread resolved;
- blocks force pushes and deletion of `main`, with no bypass actors;
- requires the `PR Validation` and `Dependency Review` checks, on a branch that is up to date
  with `main`.

Deliberate choices:

- **`PR Validation` as a required check is a human gate.** It is a commit status from the
  comment-triggered `/validate` workflow, so every pull request stays blocked until a maintainer
  comments `/validate`.
- **No required approving review count.** With a single maintainer, a required approval would make
  every pull request unmergeable, because GitHub does not let an author approve their own pull
  request. Raise `required_approving_review_count` once there is a second maintainer.
- **Signed commits are not required**, so that commits made by automation through the REST API
  remain possible.

### Release environment

[.github/workflows/publish-psgallery.yml](.github/workflows/publish-psgallery.yml) is the only
workflow that uses the PowerShell Gallery key for a stable release. It runs in the `release`
environment, which must have required reviewers configured (*Settings > Environments > release*),
and publishes the exact package the release workflow built and attached to the draft release, after
fail-closed checks in [Build/ReleasePackage.ps1](Build/ReleasePackage.ps1). The nightly pre-release
uses the same key from the `PSGALLERY_API_KEY` repository secret.

Two caveats worth stating plainly:

- **Harden-Runner is audit-only on Windows.** The build, validation and release jobs run on
  `windows-latest`, where Harden-Runner has no block mode. It gives detection after the fact, not
  prevention.
- **SHA pinning protects against a moved tag, not against a malicious release.** A new action
  version still arrives through a Dependabot pull request that a maintainer reviews and validates.
