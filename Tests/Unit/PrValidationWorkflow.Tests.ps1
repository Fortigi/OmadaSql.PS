#Requires -Version 7.0

# pr-validation.yml runs on every issue_comment, also on comments that are not /validate (the
# Dispatch job then skips). A comment like that must not land in the concurrency group of a
# validation that is running, or cancel-in-progress cancels that validation and the PR is left
# without a result.

BeforeAll {
    $Script:RepositoryRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    $Script:WorkflowText = Get-Content -LiteralPath (Join-Path $Script:RepositoryRoot '.github\workflows\pr-validation.yml') -Raw
    $Script:GroupLine = ($Script:WorkflowText -split "`r?`n" | Where-Object { $_ -match '^\s*group:\s*pr-validation-' } | Select-Object -First 1)
}

Describe 'pr-validation.yml concurrency' -Tag 'Unit' {
    It 'cancels a superseded validation of the same pull request' {
        $Script:WorkflowText | Should -Match '(?m)^\s*cancel-in-progress:\s*true\s*$'
        $Script:GroupLine | Should -Match 'github\.event\.issue\.number \|\| inputs\.pr_number'
    }

    It 'gives a comment that is not /validate a group of its own, so it cannot cancel a running validation' {
        $Script:GroupLine | Should -Match "startsWith\(github\.event\.comment\.body, '/validate'\)"
        $Script:GroupLine | Should -Match 'github\.event\.comment\.id'
    }
}
