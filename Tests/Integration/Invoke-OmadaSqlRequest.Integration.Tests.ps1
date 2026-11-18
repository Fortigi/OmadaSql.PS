param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaSql.PS\OmadaSql.PS.psm1')
)

# The request path end to end: OmadaSql.PS -> the real OmadaWeb.PS (Invoke-OmadaRestMethod, the
# version pinned in Build/BuildModules.psd1) -> HTTP -> a local mock tenant. The unit tests prove the
# classification against hand-made error records; these prove that the error records the real
# Invoke-OmadaRestMethod produces, on this PowerShell edition, are classified the same way, and that
# a body leaves the machine as UTF-8 JSON.
#
# The mock speaks plain http on 127.0.0.1, which Connect-OmadaSql refuses on purpose, so the
# connection context is built inside the module with -AuthenticationType None and retries off.

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers\OmadaSqlMockServer.ps1')

    $RepositoryRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    $Pin = @((Import-PowerShellDataFile -Path (Join-Path $RepositoryRoot -ChildPath 'Build\BuildModules.psd1')).Modules | Where-Object { $_.Name -eq 'OmadaWeb.PS' })[0]

    # A unit test file may have left the in-memory OmadaWeb.PS stub loaded; these tests need the real one.
    Get-Module -Name 'OmadaWeb.PS' -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module -Name 'OmadaWeb.PS' -RequiredVersion $Pin.RequiredVersion -Force -Global -ErrorAction Stop

    Get-Module -Name OmadaSql.PS -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $ModulePath -Force -ErrorAction Stop

    $Script:Server = Start-OmadaSqlMockServer
    $Script:Context = InModuleScope 'OmadaSql.PS' -Parameters @{ BaseUrl = $Script:Server.BaseUrl } {
        param($BaseUrl)
        @{
            Connection       = [pscustomobject]@{ Id = 'integration'; BaseUrl = $BaseUrl }
            RequestParameter = New-OmadaSqlRequestParameter -BoundParameter @{} -AuthenticationType 'None' -SessionKey ('OmadaSql.PS.Integration.{0}' -f [guid]::NewGuid().ToString('N')) -AdditionalParameter @{ MaximumRetryCount = 0 }
            ReadSucceeded    = $false
        }
    }
    $Script:ODataPath = '/odata/dataobjects/C_P_SQLTROUBLESHOOTING'

    function Invoke-TestRequest {
        param([string]$Method, [string]$Path, $Body)
        InModuleScope 'OmadaSql.PS' -Parameters @{ Context = $Script:Context; Method = $Method; Path = $Path; Body = $Body } {
            param($Context, $Method, $Path, $Body)
            Invoke-OmadaSqlRequest -Context $Context -Method $Method -Path $Path -Body $Body
        }
    }

    function Get-TestRequestError {
        param([string]$Method, [string]$Path, $Body)
        try {
            $null = Invoke-TestRequest -Method $Method -Path $Path -Body $Body
        }
        catch {
            return $_
        }
        throw "The request $Method $Path did not fail."
    }
}

AfterAll {
    if ($null -ne $Script:Server) {
        Stop-OmadaSqlMockServer -Server $Script:Server
    }
    Get-Module -Name OmadaSql.PS -All | Remove-Module -Force -ErrorAction SilentlyContinue
}

Describe 'Invoke-OmadaSqlRequest through OmadaWeb.PS' -Tag 'Integration' {
    BeforeEach {
        Reset-OmadaSqlMockServer -Server $Script:Server
        $Script:Context.ReadSucceeded = $false
    }

    It 'Returns the parsed JSON of a successful read' {
        Set-OmadaSqlMockRoute -Server $Script:Server -Method GET -Path "$($Script:ODataPath)?`$top=1" -Body '{"value":[{"Id":42,"NAME":"Query"}]}'

        $Result = Invoke-TestRequest -Method GET -Path "$($Script:ODataPath)?`$top=1"

        @($Result.value).Count | Should -Be 1
        $Result.value[0].Id | Should -Be 42
        $Script:Context.ReadSucceeded | Should -BeTrue
    }

    It 'Sends the body as UTF-8 JSON, characters outside ASCII intact' {
        $QueryText = "SELECT N'Zo{0} {1} {2}' AS [Name]" -f [char]0x00EB, [char]0x20AC, [char]0x6D4B
        Set-OmadaSqlMockRoute -Server $Script:Server -Method POST -Path $Script:ODataPath -Body '{"Id":7}'

        $Result = Invoke-TestRequest -Method POST -Path $Script:ODataPath -Body @{ NAME = 'TMP_test'; C_QUERY = $QueryText; C_SQLTROUBLESHOOTING_DATACONNECTION = @{ Id = 1001 } }

        $Result.Id | Should -Be 7
        $Request = @(Get-OmadaSqlMockRequest -Server $Script:Server -Path $Script:ODataPath)
        $Request.Count | Should -Be 1
        $Request[0].Method | Should -Be 'POST'
        $Request[0].ContentType | Should -BeLike 'application/json*'
        $Sent = ConvertFrom-Json -InputObject $Request[0].Body
        $Sent.C_QUERY | Should -BeExactly $QueryText
        $Sent.C_SQLTROUBLESHOOTING_DATACONNECTION.Id | Should -Be 1001
    }

    It 'Sends a pre-serialized string body unchanged' {
        Set-OmadaSqlMockRoute -Server $Script:Server -Method POST -Path '/WebService/DataObjectWebService.asmx/UndeleteDataObject' -Body '{"d":null}'

        $null = Invoke-TestRequest -Method POST -Path '/WebService/DataObjectWebService.asmx/UndeleteDataObject' -Body '{"id":42}'

        (Get-OmadaSqlMockRequest -Server $Script:Server -Path '/WebService/DataObjectWebService.asmx/UndeleteDataObject')[0].Body | Should -Be '{"id":42}'
    }

    It 'Classifies the OData error for a missing C_P_SQLTROUBLESHOOTING segment as EndpointNotEnabled' {
        $Body = '{"error":{"code":"","message":"Resource not found for the segment ''C_P_SQLTROUBLESHOOTING''."}}'
        Set-OmadaSqlMockRoute -Server $Script:Server -Method GET -Path "$($Script:ODataPath)?`$top=1" -StatusCode 404 -Body $Body

        $ErrorRecord = Get-TestRequestError -Method GET -Path "$($Script:ODataPath)?`$top=1"
        $Inner = $ErrorRecord.Exception.InnerException
        $Diagnostic = "message: {0}; inner: {1}" -f $ErrorRecord.Exception.Message, $(if ($null -ne $Inner) { '{0}: {1}' -f $Inner.GetType().FullName, $Inner.Message } else { '<none>' })
        $ErrorRecord.FullyQualifiedErrorId | Should -BeLike 'OmadaSql.EndpointNotEnabled*' -Because $Diagnostic
    }

    It 'Classifies HTTP 401 on a read as SessionExpired' {
        Set-OmadaSqlMockRoute -Server $Script:Server -Method GET -Path $Script:ODataPath -StatusCode 401 -Body '{"error":"unauthorized"}'

        (Get-TestRequestError -Method GET -Path $Script:ODataPath).FullyQualifiedErrorId | Should -BeLike 'OmadaSql.SessionExpired*'
    }

    It 'Classifies HTTP 401 on an OData write after a successful read as MissingPermission' {
        Set-OmadaSqlMockRoute -Server $Script:Server -Method GET -Path "$($Script:ODataPath)?`$top=1" -Body '{"value":[]}'
        Set-OmadaSqlMockRoute -Server $Script:Server -Method POST -Path $Script:ODataPath -StatusCode 401 -Body '{"error":"unauthorized"}'

        $null = Invoke-TestRequest -Method GET -Path "$($Script:ODataPath)?`$top=1"
        $ErrorRecord = Get-TestRequestError -Method POST -Path $Script:ODataPath -Body @{ NAME = 'TMP_test' }

        $ErrorRecord.FullyQualifiedErrorId | Should -BeLike 'OmadaSql.MissingPermission*'
        $ErrorRecord.Exception.Message | Should -BeLike "*'Create' permission*"
    }

    It 'Classifies HTTP <StatusCode> as <Kind> and keeps the response body in the message' -ForEach @(
        @{ StatusCode = 403; Kind = 'AccessDenied' }
        @{ StatusCode = 500; Kind = 'ServerError' }
    ) {
        Set-OmadaSqlMockRoute -Server $Script:Server -Method POST -Path '/webservice/jQGridPopulationWebService.asmx/GetPagingData' -StatusCode $StatusCode -Body '{"Message":"marker-detail-text"}'

        $ErrorRecord = Get-TestRequestError -Method POST -Path '/webservice/jQGridPopulationWebService.asmx/GetPagingData' -Body @{ dataType = 'SqlDataProducer' }

        $ErrorRecord.FullyQualifiedErrorId | Should -BeLike "OmadaSql.$Kind*"
        $ErrorRecord.Exception.Message | Should -BeLike '*marker-detail-text*'
    }

    It 'Sends a failing request once when retries are off' {
        Set-OmadaSqlMockRoute -Server $Script:Server -Method POST -Path '/webservice/jQGridPopulationWebService.asmx/GetPagingData' -StatusCode 500 -Body '{}'

        $null = Get-TestRequestError -Method POST -Path '/webservice/jQGridPopulationWebService.asmx/GetPagingData' -Body @{ dataType = 'SqlDataProducer' }

        @(Get-OmadaSqlMockRequest -Server $Script:Server -Path '/webservice/jQGridPopulationWebService.asmx/GetPagingData').Count | Should -Be 1
    }
}
