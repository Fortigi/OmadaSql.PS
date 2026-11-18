function New-OmadaSqlErrorRecord {
    <#
    .SYNOPSIS
    Builds the ErrorRecord the module throws, with a stable FullyQualifiedErrorId per kind.

    .DESCRIPTION
    The FullyQualifiedErrorId is 'OmadaSql.<Kind>', so a script can branch on it
    ($_.FullyQualifiedErrorId -like 'OmadaSql.MissingPermission*') instead of parsing messages. The
    original error, when there is one, is kept as the inner exception.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds an object in memory and changes no state.')]
    [CmdletBinding()]
    [OutputType([System.Management.Automation.ErrorRecord])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Kind,

        [Parameter(Mandatory = $true)]
        [string]$Message,

        [System.Exception]$InnerException,

        [object]$TargetObject
    )

    $Category = switch ($Kind) {
        'NotConnected' { [System.Management.Automation.ErrorCategory]::ConnectionError }
        'EndpointNotEnabled' { [System.Management.Automation.ErrorCategory]::NotEnabled }
        'SessionExpired' { [System.Management.Automation.ErrorCategory]::AuthenticationError }
        'MissingPermission' { [System.Management.Automation.ErrorCategory]::PermissionDenied }
        'AccessDenied' { [System.Management.Automation.ErrorCategory]::PermissionDenied }
        'NotFound' { [System.Management.Automation.ErrorCategory]::ObjectNotFound }
        'InvalidArgument' { [System.Management.Automation.ErrorCategory]::InvalidArgument }
        default { [System.Management.Automation.ErrorCategory]::InvalidResult }
    }

    if ($null -ne $InnerException) {
        $Exception = [System.InvalidOperationException]::new($Message, $InnerException)
    }
    else {
        $Exception = [System.InvalidOperationException]::new($Message)
    }

    return [System.Management.Automation.ErrorRecord]::new($Exception, ("OmadaSql.{0}" -f $Kind), $Category, $TargetObject)
}
