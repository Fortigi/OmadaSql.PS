function ConvertFrom-OmadaSqlHistoryRow {
    <#
    .SYNOPSIS
    Turns DataObjectHistory rows into one OmadaSql.HistoryEntry per changed field. Pure.

    .DESCRIPTION
    A history row (GetPagingData, dataType DataObjectHistory) carries Object, Who, What, When and
    ChangedFields, a JSON array of { Field, OldValue, NewValue }. OmadaSqlTroubleshooter keeps only
    the 'SQL Query' field; every field is kept here. A row without changed fields (a delete, for
    instance) still yields one entry, with Field $null, so no event is lost.

    '[N/A]' is Omada's placeholder for "no value" and becomes $null; values are HTML-decoded, as
    Omada stores them encoded. When cannot be read becomes $null rather than failing the whole
    history (OmadaSqlTroubleshooter issue #95: the server's date format and the client's culture
    need not agree).
    #>
    [CmdletBinding()]
    [OutputType('OmadaSql.HistoryEntry')]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [AllowNull()]
        [object]$Row,

        [Parameter(Mandatory = $true)]
        [long]$Id
    )

    process {
        if ($null -eq $Row) {
            return
        }

        $Base = [ordered]@{
            PSTypeName = 'OmadaSql.HistoryEntry'
            Id         = $Id
            Name       = [string](Get-OmadaSqlPropertyValue -InputObject $Row -Name 'Object')
            ChangedAt  = ConvertTo-OmadaSqlHistoryDate -Value ([string](Get-OmadaSqlPropertyValue -InputObject $Row -Name 'When'))
            ChangedBy  = [string](Get-OmadaSqlPropertyValue -InputObject $Row -Name 'Who')
            ChangeType = [string](Get-OmadaSqlPropertyValue -InputObject $Row -Name 'What')
            Field      = $null
            OldValue   = $null
            NewValue   = $null
        }

        $Fields = @(ConvertFrom-OmadaSqlChangedField -Value (Get-OmadaSqlPropertyValue -InputObject $Row -Name 'ChangedFields'))
        if ($Fields.Count -eq 0) {
            [pscustomobject]$Base
            return
        }
        foreach ($Field in $Fields) {
            $Entry = [ordered]@{}
            foreach ($Key in $Base.Keys) {
                $Entry[$Key] = $Base[$Key]
            }
            $Entry.Field = [string](Get-OmadaSqlPropertyValue -InputObject $Field -Name 'Field')
            $Entry.OldValue = ConvertFrom-OmadaSqlHistoryValue -Value (Get-OmadaSqlPropertyValue -InputObject $Field -Name 'OldValue')
            $Entry.NewValue = ConvertFrom-OmadaSqlHistoryValue -Value (Get-OmadaSqlPropertyValue -InputObject $Field -Name 'NewValue')
            [pscustomobject]$Entry
        }
    }
}

function ConvertFrom-OmadaSqlChangedField {
    <#
    .SYNOPSIS
    The ChangedFields of a history row as objects; it arrives as a JSON string or already parsed.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Value) {
        return
    }
    if ($Value -is [string]) {
        if ([string]::IsNullOrWhiteSpace($Value)) {
            return
        }
        try {
            $Value = ConvertFrom-Json -InputObject $Value
        }
        catch {
            Write-OmadaSqlLog -Message ("A history row has ChangedFields that are not JSON; they are skipped: {0}" -f $_.Exception.Message)
            return
        }
    }
    $Value | Where-Object { $null -ne $_ }
}

function ConvertFrom-OmadaSqlHistoryValue {
    <#
    .SYNOPSIS
    A history value as text: HTML-decoded, with Omada's '[N/A]' placeholder as $null.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Value -or [string]$Value -eq '[N/A]') {
        return $null
    }
    return [System.Net.WebUtility]::HtmlDecode([string]$Value)
}

function ConvertTo-OmadaSqlHistoryDate {
    <#
    .SYNOPSIS
    Parses a date the server formatted; $null when it cannot be read.

    .DESCRIPTION
    Invariant culture first, then the current culture, as OmadaSqlTroubleshooter does. Never Get-Date
    or a [datetime] cast: those use the current culture only, and a day-first culture reads
    '8/25/2026' as month 25.
    #>
    [CmdletBinding()]
    [OutputType([System.Nullable[datetime]])]
    param(
        [AllowEmptyString()]
        [AllowNull()]
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }
    $Parsed = [datetime]::MinValue
    foreach ($Culture in @([System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.CultureInfo]::CurrentCulture)) {
        if ([datetime]::TryParse($Value, $Culture, [System.Globalization.DateTimeStyles]::None, [ref]$Parsed)) {
            return $Parsed
        }
    }
    return $null
}
