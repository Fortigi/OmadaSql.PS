<#
    Policy for the complexity and mutation-testing gates.

    The PR lane (Task QualityChanged) holds the code a pull request changed to these numbers; the
    weekly lane (Task QualityFull, .github/workflows/quality-weekly.yml) holds the whole tree to them
    and files an issue per failing gate. Both read this file and nothing else, so a threshold is
    changed in exactly one place.

    Complexity
      MaxCyclomatic / MaxCognitive - the per-unit ceilings.
      BaselineFile                 - units that are over the ceilings, with the score each may not
                                     exceed. It only ratchets down: run
                                     ./Build/build.ps1 -Task UpdateComplexityBaseline after a unit
                                     improves, and commit the result. Starts empty: new code meets
                                     the ceilings from the first commit.
      SourcePath                   - what is measured, relative to the repository root. Files named
                                     _*.ps1 are excluded, as they are from the build itself.

    Mutation
      SourcePath       - the source tree whose files are mutated, relative to the repository root.
      TestPath         - where the owning unit test files live: Tests/Unit/<FunctionName>.Tests.ps1.
      Operators        - PSMutant operator classes. Adding one renumbers every mutant and lowers the
                         score, so move Thresholds.Break in the same change.
      CoveredLinesOnly - only mutate lines the mapped tests execute; an uncovered mutant teaches
                         nothing.
      SandboxSubtrees  - what PSMutant copies into its sandbox.
      Workers          - mutants evaluated in parallel. 3 on the 4-vCPU windows-latest runner.
      Thresholds       - High/Low colour the console score only. Break fails the gate when the
                         score over all mutated files is below it. FileBreak fails the gate when any
                         single file with mutants scores below it, so one weakly tested file cannot
                         hide behind a strong aggregate. Raise both as the score rises, never lower
                         them to make a red run green.
      RequireOwningTest - fail the PR lane when changed source has no owning unit test file
                         (Tests/Unit/<FunctionName>.Tests.ps1): its test strength cannot be measured.
      Equivalents      - 'path:Function:original -> mutated' = 'why no test can tell the two apart'.
                         PSMutant fails the run if a declaration is ever killed or stops matching.
#>
@{
    Complexity = @{
        MaxCyclomatic = 15
        MaxCognitive  = 15
        BaselineFile  = 'complexity-baseline.json'
        SourcePath    = @('OmadaSql.PS/Public', 'OmadaSql.PS/Private')
    }

    Mutation   = @{
        SourcePath       = 'OmadaSql.PS'
        TestPath         = 'Tests/Unit'
        Operators        = @('BinaryOperator', 'BooleanLiteral', 'NegationRemoval', 'NumberLiteral')
        CoveredLinesOnly = $true
        SandboxSubtrees  = @('OmadaSql.PS', 'Tests', 'Build')
        Workers          = 3
        Thresholds       = @{
            High      = 85
            Low       = 75
            Break     = 75
            FileBreak = 75
        }
        RequireOwningTest = $true
        Equivalents      = @{}
    }
}
