#Requires -Version 7.0

# Guards .github/rulesets/protect-main.json, the branch protection kept as code. The required status
# checks are plain strings that have to match what the workflows report; a rename on either side
# leaves main requiring a check that never arrives, which blocks every merge.

BeforeAll {
    $Script:RepositoryRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    $Script:Ruleset = Get-Content -LiteralPath (Join-Path $Script:RepositoryRoot -ChildPath '.github\rulesets\protect-main.json') -Raw | ConvertFrom-Json
    $Script:Rule = @{}
    foreach ($Rule in $Script:Ruleset.rules) {
        $Script:Rule[$Rule.type] = $Rule
    }
    $Script:WorkflowsPath = Join-Path $Script:RepositoryRoot -ChildPath '.github\workflows'
}

Describe 'Ruleset Protect Main' -Tag 'Unit' {

    It 'Should be active on the default branch' {
        $Script:Ruleset.enforcement | Should -Be 'active'
        $Script:Ruleset.target | Should -Be 'branch'
        $Script:Ruleset.conditions.ref_name.include | Should -Contain '~DEFAULT_BRANCH'
    }

    It 'Should have no bypass actors' {
        @($Script:Ruleset.bypass_actors).Count | Should -Be 0
    }

    It 'Should block force pushes and deletion' {
        $Script:Rule.ContainsKey('non_fast_forward') | Should -BeTrue
        $Script:Rule.ContainsKey('deletion') | Should -BeTrue
    }

    It 'Should require a pull request merged by squash, with every conversation resolved' {
        $Script:Rule['pull_request'].parameters.allowed_merge_methods | Should -Be @('squash')
        $Script:Rule['pull_request'].parameters.required_review_thread_resolution | Should -BeTrue
    }

    It 'Should require the branch to be up to date before merging' {
        $Script:Rule['required_status_checks'].parameters.strict_required_status_checks_policy | Should -BeTrue
    }

    It 'Should require the <Context> check, which <Workflow> reports' -ForEach @(
        @{ Context = 'PR Validation'; Workflow = 'pr-validation.yml'; Pattern = "context: 'PR Validation'" }
        @{ Context = 'Dependency Review'; Workflow = 'dependency-review.yml'; Pattern = 'name: Dependency Review' }
    ) {
        @($Script:Rule['required_status_checks'].parameters.required_status_checks.context) | Should -Contain $Context
        Get-Content -LiteralPath (Join-Path $Script:WorkflowsPath -ChildPath $Workflow) -Raw | Should -Match ([regex]::Escape($Pattern))
    }

    It 'Should require only checks that report on every pull request' {
        # A required check that is paths-filtered or schedule-only never reports on most pull
        # requests and blocks them forever.
        @($Script:Rule['required_status_checks'].parameters.required_status_checks.context) | Should -Be @('PR Validation', 'Dependency Review')
    }
}
