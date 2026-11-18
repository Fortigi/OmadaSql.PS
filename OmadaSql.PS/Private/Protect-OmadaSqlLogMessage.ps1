function Protect-OmadaSqlLogMessage {
    <#
    .SYNOPSIS
    Masks secrets in a message before it is written to the Verbose or Debug stream.

    .DESCRIPTION
    Pure text transformation, ported from OmadaSqlTroubleshooter's Protect-LogMessage. Masks
    authorization scheme tokens, JWTs, JSON members and key=value pairs whose name looks like a
    secret, and Set-Cookie values. When the redaction itself fails, the whole message is suppressed:
    an unredacted message is never the fallback.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $false, Position = 0, ValueFromPipeline = $true)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Message
    )

    process {
        if ([string]::IsNullOrEmpty($Message)) {
            return $Message
        }

        try {
            $Redacted = "***REDACTED***"
            $Result = $Message
            $Result = $Result -replace '(?i)\b(Basic|Bearer|Negotiate|NTLM|Digest)\s+([A-Za-z0-9+/=._\-]{8,})', ('$1 {0}' -f $Redacted)
            $Result = $Result -replace '\beyJ[A-Za-z0-9_\-]{4,}\.[A-Za-z0-9_\-]{4,}\.[A-Za-z0-9_\-]*', '***REDACTED-JWT***'
            $Result = $Result -replace '(?i)("[^"]*(?:authorization|cookie|credential|password|pwd|secret|token|apikey|api_key|clientsecret|sessionkey|csrf|assertion|privatekey|connectionstring)[^"]*"\s*:\s*)"[^"]*"', ('$1"{0}"' -f $Redacted)
            $Result = $Result -replace '(?i)\b([\w.\-]*(?:password|pwd|secret|token|apikey|api_key|sessionid|sessionkey|auth|csrf)[\w.\-]*)\s*=\s*([^\s;,&"'']+)', ('$1={0}' -f $Redacted)
            $Result = $Result -replace '(?i)(Set-Cookie:\s*)([^\s=;]+)=([^;\s]+)', ('$1$2={0}' -f $Redacted)
            return $Result
        }
        catch {
            return "***REDACTION FAILED - MESSAGE SUPPRESSED***"
        }
    }
}
