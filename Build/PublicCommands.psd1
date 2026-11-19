<#
    Classification of the module's exported commands, read by Build/Test-CommentBasedHelp.ps1.

    WrappedCommands maps each exported function to the built-in cmdlet it wraps, or to an empty
    string when it is a command in its own right. The help check fails when an exported function is
    missing from this map, so adding a public function is a deliberate step rather than something
    that silently drops out of the help check.

    OmadaSql.PS wraps no built-in cmdlet: every command is standalone, declares its parameters
    normally and documents them with comment-based .PARAMETER help.
#>
@{
    WrappedCommands = @{
        'Connect-OmadaSql'           = ''
        'Disconnect-OmadaSql'        = ''
        'Get-OmadaSqlConnection'     = ''
        'Get-OmadaSqlDataConnection' = ''
        'Get-OmadaSqlQuery'          = ''
        'Get-OmadaSqlQueryHistory'   = ''
        'New-OmadaSqlQuery'          = ''
        'Remove-OmadaSqlQuery'       = ''
        'Restore-OmadaSqlQuery'      = ''
        'Set-OmadaSqlQuery'          = ''
        'Test-OmadaSqlQuery'         = ''
    }
}
