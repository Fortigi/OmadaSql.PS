<#
    Shared helpers for the unit tests. Dot-source from a test file's BeforeAll:

        . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers\OmadaSqlTestHelper.ps1')

    Import-OmadaWebStub replaces OmadaWeb.PS with an in-memory module of the same name whose
    Invoke-OmadaRestMethod declares, statically, the parameters this module passes. The real command
    adds its parameters through DynamicParam (some of them depending on the Edge profiles on the
    machine), which makes Pester mocks of it depend on the machine they run on. Tests mock the stub
    instead, with -ModuleName OmadaSql.PS, so every call the module makes is intercepted and the
    parameter filters can read each parameter by name.

    New-OmadaSqlTestHttpError builds the ErrorRecord an HTTP failure produces, with an exception
    whose Response.StatusCode is set, and optionally ErrorDetails (where Invoke-RestMethod puts the
    response body).
#>

if (-not ('OmadaSqlPSTests.FakeHttpException' -as [type])) {
    Add-Type -TypeDefinition @'
namespace OmadaSqlPSTests
{
    public class FakeResponse
    {
        public int StatusCode { get; set; }
    }

    public class FakeHttpException : System.Exception
    {
        public FakeHttpException(string message, int statusCode) : base(message)
        {
            Response = new FakeResponse { StatusCode = statusCode };
        }

        public FakeResponse Response { get; private set; }
    }
}
'@
}

function Import-OmadaWebStub {
    Get-Module -Name 'OmadaWeb.PS' -All | Remove-Module -Force -ErrorAction SilentlyContinue
    $Stub = New-Module -Name 'OmadaWeb.PS' -ScriptBlock {
        function Invoke-OmadaRestMethod {
            [CmdletBinding()]
            param(
                [System.Uri]$Uri,
                [string]$Method,
                [object]$Body,
                [string]$ContentType,
                [string]$AuthenticationType,
                [string]$SessionKey,
                [string]$ClientId,
                [string]$OAuthCertificateThumbprint,
                [string]$OAuthCertificatePath,
                [System.Security.SecureString]$OAuthCertificatePassword,
                [System.Security.Cryptography.X509Certificates.X509Certificate2]$OAuthCertificate,
                [System.Management.Automation.PSCredential]$Credential,
                [string]$EntraIdTenantId,
                [string]$EntraApplicationIdUri,
                [string]$OAuthScope,
                [string]$OAuthUri,
                [switch]$NoInteractiveAuthentication,
                [switch]$ForceAuthentication,
                [int]$MaximumRetryCount,
                [switch]$Paged,
                [string]$UserName
            )
            throw 'The OmadaWeb.PS test stub was called without a mock. Mock Invoke-OmadaRestMethod -ModuleName OmadaSql.PS in the test.'
        }
        Export-ModuleMember -Function 'Invoke-OmadaRestMethod'
    }
    $Stub | Import-Module -Global -Force
}

function New-OmadaSqlTestHttpError {
    param(
        [Parameter(Mandatory = $true)]
        [int]$StatusCode,

        [string]$Message = ('Response status code does not indicate success: {0}.' -f $StatusCode),

        [string]$Detail
    )

    $Exception = [OmadaSqlPSTests.FakeHttpException]::new($Message, $StatusCode)
    $ErrorRecord = [System.Management.Automation.ErrorRecord]::new($Exception, 'WebCmdletWebResponseException', [System.Management.Automation.ErrorCategory]::InvalidOperation, $null)
    if (-not [string]::IsNullOrEmpty($Detail)) {
        $ErrorRecord.ErrorDetails = [System.Management.Automation.ErrorDetails]::new($Detail)
    }
    return $ErrorRecord
}

function New-OmadaSqlTestSessionExpiredError {
    $Exception = [System.Security.Authentication.AuthenticationException]::new('There is no valid Omada session.')
    return [System.Management.Automation.ErrorRecord]::new($Exception, 'OmadaSessionExpired,Invoke-OmadaRestMethod', [System.Management.Automation.ErrorCategory]::AuthenticationError, $null)
}

function New-OmadaSqlTestODataQuery {
    # A C_P_SQLTROUBLESHOOTING object as OData returns it.
    param(
        [long]$Id = 101,
        [string]$Name = 'Daily export',
        [string]$Query = 'SELECT [Id] = 1',
        [long]$DataConnectionId = 1001,
        [string]$DataConnectionName = 'OISES',
        [bool]$Deleted = $false
    )
    [pscustomobject]@{
        Id                                  = $Id
        NAME                                = $Name
        DisplayName                         = $Name
        C_QUERY                             = $Query
        C_SQLTROUBLESHOOTING_DATACONNECTION = [pscustomobject]@{ Id = $DataConnectionId; DisplayName = $DataConnectionName }
        Deleted                             = $Deleted
    }
}

function Initialize-OmadaSqlTestConnection {
    # A current connection without any request: the stub answers nothing, -SkipConnectionTest sends nothing.
    Disconnect-OmadaSql -All
    Connect-OmadaSql -Url 'https://tenant.omada.cloud' -AuthenticationType OAuth -ClientId 'client' -OAuthCertificateThumbprint 'AB12' -SkipConnectionTest -PassThru
}

function Get-OmadaSqlParameterContract {
    <#
        The declared contract of one parameter, read from the loaded command: whether it is mandatory,
        its position, whether it binds from the pipeline, and its ValidateRange bounds as text.
        Parameter declarations are not code any test executes, so only an assertion on this contract
        can tell a test run apart from one where, say, Mandatory was flipped (the mutation gate
        mutates those lines too).
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$CommandName,

        [Parameter(Mandatory = $true)]
        [string]$ParameterName,

        [string]$ParameterSetName
    )

    $Command = & (Get-Module -Name 'OmadaSql.PS') { param($Name) Get-Command -Name $Name -CommandType Function } $CommandName
    $Parameter = $Command.Parameters[$ParameterName]
    if ($null -eq $Parameter) {
        throw ("{0} has no parameter {1}." -f $CommandName, $ParameterName)
    }
    $Attribute = @($Parameter.Attributes | Where-Object {
            $_ -is [System.Management.Automation.ParameterAttribute] -and
            ([string]::IsNullOrEmpty($ParameterSetName) -or $_.ParameterSetName -eq $ParameterSetName)
        })[0]
    $Range = @($Parameter.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateRangeAttribute] })
    [pscustomobject]@{
        Mandatory                       = [bool]$Attribute.Mandatory
        Position                        = $(if ($Attribute.Position -eq [int]::MinValue) { $null } else { $Attribute.Position })
        ValueFromPipeline               = [bool]$Attribute.ValueFromPipeline
        ValueFromPipelineByPropertyName = [bool]$Attribute.ValueFromPipelineByPropertyName
        RangeMin                        = $(if ($Range.Count -gt 0) { [string]$Range[0].MinRange } else { $null })
        RangeMax                        = $(if ($Range.Count -gt 0) { [string]$Range[0].MaxRange } else { $null })
    }
}

function Get-OmadaSqlTestStatement {
    # The top-level statements of a T-SQL script, parsed by the module's own parser (real ScriptDom).
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Sql
    )
    & (Get-Module -Name 'OmadaSql.PS') {
        param($Text)
        $Parsed = ConvertTo-OmadaSqlScriptFragment -Sql $Text
        Split-OmadaSqlStatement -Fragment $Parsed.Fragment -Sql $Text
    } $Sql
}

function Set-OmadaSqlTestSetting {
    # Points the module at a settings file under TestDrive with a known profile id, and returns the id.
    param(
        [Parameter(Mandatory = $true)]
        [string]$Folder,

        [int]$MaxTempQuerySlots = 2
    )
    $Guid = [guid]::NewGuid().ToString('N')
    $Path = Join-Path $Folder ('{0}.json' -f $Guid)
    [System.IO.File]::WriteAllText($Path, (@{ InstanceGuid = $Guid; MaxTempQuerySlots = $MaxTempQuerySlots } | ConvertTo-Json))
    & (Get-Module -Name 'OmadaSql.PS') { param($P) $Script:OmadaSqlSettingsPath = $P } $Path
    return $Guid
}

function Get-OmadaSqlTestSchemaData {
    # A small schema in the GetSqlSchema answer shape: Person in dbo and audit, Event only outside dbo.
    [pscustomobject]@{
        'dbo.Person'    = @('Id int', 'DisplayName nvarchar(255)', 'Deleted bit')
        'dbo.Contract'  = @('Id int', 'PersonId int', 'Amount decimal(18,2)')
        'audit.Person'  = @('Id int', 'At datetime')
        'audit.Event'   = @('Id int', 'Payload nvarchar(max)')
        'graphql.Event' = @('Id int', 'Name nvarchar(50)')
    }
}

function Find-OmadaSqlTestSchemaFinding {
    # The schema findings of a script against Get-OmadaSqlTestSchemaData, as 'RuleId:name' labels in
    # document order, the name being the column or table as written.
    param(
        [Parameter(Mandatory = $true)]
        [string]$Sql
    )
    $Statement = @(Get-OmadaSqlTestStatement -Sql $Sql)
    & (Get-Module -Name 'OmadaSql.PS') {
        param($Statement, $Data)
        $Model = ConvertTo-OmadaSqlSchemaModel -Data $Data -DataConnection ([pscustomobject]@{ Name = 'OISES'; Id = 1001 })
        $Name = Get-OmadaSqlScriptDefinedName -Statement $Statement
        foreach ($Item in $Statement) {
            foreach ($Hit in @(Find-OmadaSqlSchemaFinding -Fragment $Item.Fragment -Model $Model -ScriptName $Name)) {
                $Part = if ($Hit.RuleId -eq 'OMD030') { $Hit.Fragment.SchemaObject.Identifiers } else { $Hit.Fragment.MultiPartIdentifier.Identifiers }
                '{0}:{1}' -f $Hit.RuleId, ((@($Part) | ForEach-Object { $_.Value }) -join '.')
            }
        }
    } $Statement (Get-OmadaSqlTestSchemaData)
}

function Get-OmadaSqlTestSchemaCase {
    # Scripts and the schema findings they must give (see Find-OmadaSqlTestSchemaFinding).
    @{ Case = 'a known qualified column'; Sql = 'SELECT [a] = p.DisplayName FROM dbo.Person AS p'; Expected = @() }
    @{ Case = 'an unknown qualified column'; Sql = 'SELECT [a] = p.Nope FROM dbo.Person AS p'; Expected = @('OMD031:p.Nope') }
    @{ Case = 'an unknown unqualified column'; Sql = 'SELECT [a] = Nope FROM dbo.Person'; Expected = @('OMD031:Nope') }
    @{ Case = 'a column without any table'; Sql = 'SELECT [a] = Nope'; Expected = @('OMD031:Nope') }
    @{ Case = 'a column two joined tables have'; Sql = 'SELECT [a] = Id FROM dbo.Person AS p JOIN dbo.Contract AS c ON c.PersonId = p.Id'; Expected = @('OMD032:Id') }
    @{ Case = 'an unknown table with a schema'; Sql = 'SELECT [a] = 1 FROM dbo.Nope'; Expected = @('OMD030:dbo.Nope') }
    @{ Case = 'an unknown table without a schema'; Sql = 'SELECT [a] = 1 FROM Nope'; Expected = @('OMD030:Nope') }
    @{ Case = 'an unknown table with a database name'; Sql = 'SELECT [a] = 1 FROM OISES.dbo.Nope'; Expected = @('OMD030:OISES.dbo.Nope') }
    @{ Case = 'a known table with a database name'; Sql = 'SELECT [a] = Deleted FROM OISES.dbo.Person'; Expected = @() }
    @{ Case = 'a name in dbo and another schema'; Sql = 'SELECT [a] = DisplayName FROM Person'; Expected = @() }
    @{ Case = 'a name in two schemas, neither dbo'; Sql = 'SELECT [a] = Nope FROM Event'; Expected = @() }
    @{ Case = 'a table outside dbo'; Sql = 'SELECT [a] = At FROM audit.Person'; Expected = @() }
    @{ Case = 'names in another case'; Sql = 'SELECT [a] = p.displayname FROM DBO.PERSON AS p'; Expected = @() }
    @{ Case = 'a temporary table'; Sql = 'SELECT [a] = x FROM #t'; Expected = @() }
    @{ Case = 'a table variable'; Sql = 'SELECT [a] = x FROM @t'; Expected = @() }
    @{ Case = 'a four-part name'; Sql = 'SELECT [a] = x FROM srv.db.dbo.T'; Expected = @() }
    @{ Case = 'a CTE'; Sql = 'WITH c AS (SELECT [Id] = Id FROM dbo.Person) SELECT [a] = Nope FROM c'; Expected = @() }
    @{ Case = 'a column a CTE body does not have'; Sql = 'WITH c AS (SELECT [x] = Nope FROM dbo.Person) SELECT [a] = x FROM c'; Expected = @('OMD031:Nope') }
    @{ Case = 'a derived table'; Sql = 'SELECT [a] = d.x FROM (SELECT [x] = Id FROM dbo.Person) AS d'; Expected = @() }
    @{ Case = 'an unknown column inside a derived table'; Sql = 'SELECT [a] = Nope FROM (SELECT [x] = Nope FROM dbo.Person) AS d'; Expected = @('OMD031:Nope') }
    @{ Case = 'a correlated subquery'; Sql = 'SELECT [a] = p.Id FROM dbo.Person AS p WHERE EXISTS (SELECT [x] = 1 FROM dbo.Contract AS c WHERE c.PersonId = p.Id)'; Expected = @() }
    @{ Case = 'an outer column without a table name'; Sql = 'SELECT [a] = 1 FROM dbo.Person AS p WHERE EXISTS (SELECT [x] = 1 FROM dbo.Contract AS c WHERE DisplayName = 1)'; Expected = @() }
    @{ Case = 'an inner column that shadows an outer one'; Sql = 'SELECT [a] = 1 FROM dbo.Person AS p WHERE EXISTS (SELECT [x] = 1 FROM dbo.Contract AS c WHERE Id = 1)'; Expected = @() }
    @{ Case = 'an unknown column in a subquery'; Sql = 'SELECT [a] = 1 FROM dbo.Person AS p WHERE EXISTS (SELECT [x] = 1 FROM dbo.Contract AS c WHERE c.Nope = p.Id)'; Expected = @('OMD031:c.Nope') }
    @{ Case = 'a SELECT-list alias in ORDER BY'; Sql = 'SELECT [Label] = DisplayName FROM dbo.Person ORDER BY Label'; Expected = @() }
    @{ Case = 'the date part of DATEADD'; Sql = 'SELECT [a] = DATEADD(day, 1, Nope) FROM dbo.Person'; Expected = @('OMD031:Nope') }
    @{ Case = 'the date part of DATEDIFF'; Sql = 'SELECT [a] = DATEDIFF(month, Deleted, Deleted) FROM dbo.Person'; Expected = @() }
    @{ Case = 'a column named like a date part outside a date function'; Sql = 'SELECT [a] = ISNULL(day, 1) FROM dbo.Person'; Expected = @('OMD031:day') }
    @{ Case = 'a wildcard'; Sql = 'SELECT * FROM dbo.Person AS p JOIN dbo.Contract AS c ON c.PersonId = p.Id'; Expected = @() }
    @{ Case = 'a qualified wildcard'; Sql = 'SELECT p.* FROM dbo.Person AS p'; Expected = @() }
    @{ Case = 'an unknown qualifier'; Sql = 'SELECT [a] = x.Nope FROM dbo.Person AS p'; Expected = @() }
    @{ Case = 'a table name as qualifier'; Sql = 'SELECT [a] = Person.Nope FROM dbo.Person'; Expected = @('OMD031:Person.Nope') }
    @{ Case = 'a parenthesised join'; Sql = 'SELECT [a] = c.Nope FROM (dbo.Person AS p JOIN dbo.Contract AS c ON c.PersonId = p.Id)'; Expected = @('OMD031:c.Nope') }
    @{ Case = 'a cross join'; Sql = 'SELECT [a] = c.Nope FROM dbo.Person AS p CROSS JOIN dbo.Contract AS c'; Expected = @('OMD031:c.Nope') }
    @{ Case = 'a derived table beside a known table'; Sql = 'SELECT [a] = p.Id FROM dbo.Person AS p JOIN (SELECT [x] = Nope FROM dbo.Contract) AS d ON d.x = p.Id'; Expected = @('OMD031:Nope') }
    @{ Case = 'an outer source used inside CROSS APPLY'; Sql = 'SELECT [a] = 1 FROM dbo.Person AS p CROSS APPLY (SELECT [x] = c.Amount FROM dbo.Contract AS c WHERE c.PersonId = p.Id AND DisplayName = 1) AS d'; Expected = @() }
    @{ Case = 'an unknown column inside CROSS APPLY'; Sql = 'SELECT [a] = 1 FROM dbo.Person AS p CROSS APPLY (SELECT [x] = c.Nope FROM dbo.Contract AS c WHERE c.PersonId = p.Id) AS d'; Expected = @('OMD031:c.Nope') }
    @{ Case = 'a join with a table function'; Sql = 'SELECT [a] = Nope FROM dbo.Person AS p CROSS APPLY OPENJSON(p.DisplayName) AS j'; Expected = @() }
    @{ Case = 'an unknown and a known table'; Sql = 'SELECT [a] = Nope FROM dbo.Person AS p JOIN dbo.Nope AS n ON n.Id = p.Id'; Expected = @('OMD030:dbo.Nope') }
    @{ Case = 'a SELECT INTO target used later'; Sql = 'SELECT [a] = 1 INTO Staging FROM dbo.Person; SELECT [b] = 1 FROM Staging'; Expected = @() }
    @{ Case = 'a SELECT INTO target with a schema'; Sql = 'SELECT [a] = 1 INTO Staging FROM dbo.Person; SELECT [b] = 1 FROM dbo.Staging'; Expected = @('OMD030:dbo.Staging') }
    @{ Case = 'a UNION'; Sql = 'SELECT [a] = Nope FROM dbo.Person UNION ALL SELECT [a] = Amount FROM dbo.Contract'; Expected = @('OMD031:Nope') }
    @{ Case = 'two findings in order'; Sql = "SELECT [a] = p.Nope, [b] = Missing`nFROM dbo.Person AS p"; Expected = @('OMD031:p.Nope', 'OMD031:Missing') }
}
