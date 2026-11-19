function Write-OmadaSqlLog {
    <#
    .SYNOPSIS
    The module's single logging point: redacts the message, then writes it to the Verbose or Debug stream.

    .DESCRIPTION
    The module writes no log files of its own; a caller that wants a log captures the streams
    (for example with -Verbose 4>&1 or Start-Transcript). Every message passes through
    Protect-OmadaSqlLogMessage first, so no code path can put a secret on a stream by accident.
    Query text and query results are never passed to this function at Verbose level.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [AllowEmptyString()]
        [string]$Message,

        [ValidateSet('Verbose', 'Debug')]
        [string]$Level = 'Verbose'
    )

    process {
        $SafeMessage = "[OmadaSql.PS] {0}" -f (Protect-OmadaSqlLogMessage -Message $Message)
        if ($Level -eq 'Debug') {
            Write-Debug -Message $SafeMessage
        }
        else {
            Write-Verbose -Message $SafeMessage
        }
    }
}
