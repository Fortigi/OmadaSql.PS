param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaSql.PS\OmadaSql.PS.psm1')
)

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers\OmadaSqlTestHelper.ps1')
    Get-Module OmadaSql.PS | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $ModulePath -Force -ErrorAction Stop
    $Script:ODataUri = 'https://tenant.omada.cloud/odata/dataobjects/C_P_SQLTROUBLESHOOTING'
}

Describe 'Resolve-OmadaSqlRequestError' -Tag 'Unit' {
    It 'Classifies a missing C_P_SQLTROUBLESHOOTING segment as EndpointNotEnabled' {
        $ErrorRecord = New-OmadaSqlTestHttpError -StatusCode 404 -Detail "Resource not found for the segment 'C_P_SQLTROUBLESHOOTING'."
        InModuleScope 'OmadaSql.PS' -Parameters @{ ErrorRecord = $ErrorRecord; Uri = $Script:ODataUri } {
            param($ErrorRecord, $Uri)
            $Result = Resolve-OmadaSqlRequestError -ErrorRecord $ErrorRecord -Method GET -Uri $Uri
            $Result.Kind | Should -Be 'EndpointNotEnabled'
            $Result.Message | Should -BeLike "*tenant.omada.cloud*"
        }
    }

    It 'Classifies a 401 on an OData <Method> after a successful read as MissingPermission <Permission>' -ForEach @(
        @{ Method = 'POST'; Permission = 'Create' }
        @{ Method = 'PUT'; Permission = 'Update' }
        @{ Method = 'DELETE'; Permission = 'Delete' }
    ) {
        $ErrorRecord = New-OmadaSqlTestHttpError -StatusCode 401
        InModuleScope 'OmadaSql.PS' -Parameters @{ ErrorRecord = $ErrorRecord; Uri = $Script:ODataUri; Method = $Method; Permission = $Permission } {
            param($ErrorRecord, $Uri, $Method, $Permission)
            $Result = Resolve-OmadaSqlRequestError -ErrorRecord $ErrorRecord -Method $Method -Uri $Uri -ReadSucceeded $true
            $Result.Kind | Should -Be 'MissingPermission'
            $Result.Message | Should -BeLike "*'$Permission' permission*"
        }
    }

    It 'Classifies the OmadaWeb.PS session-expired error on an OData write after a read as MissingPermission' {
        $ErrorRecord = New-OmadaSqlTestSessionExpiredError
        InModuleScope 'OmadaSql.PS' -Parameters @{ ErrorRecord = $ErrorRecord; Uri = $Script:ODataUri } {
            param($ErrorRecord, $Uri)
            (Resolve-OmadaSqlRequestError -ErrorRecord $ErrorRecord -Method POST -Uri $Uri -ReadSucceeded $true).Kind | Should -Be 'MissingPermission'
        }
    }

    It 'Classifies a 401 before any read succeeded as SessionExpired, not as a missing permission' {
        $ErrorRecord = New-OmadaSqlTestHttpError -StatusCode 401
        InModuleScope 'OmadaSql.PS' -Parameters @{ ErrorRecord = $ErrorRecord; Uri = $Script:ODataUri } {
            param($ErrorRecord, $Uri)
            (Resolve-OmadaSqlRequestError -ErrorRecord $ErrorRecord -Method POST -Uri $Uri -ReadSucceeded $false).Kind | Should -Be 'SessionExpired'
        }
    }

    It 'Classifies a 401 on a read as SessionExpired even after an earlier read' {
        $ErrorRecord = New-OmadaSqlTestHttpError -StatusCode 401
        InModuleScope 'OmadaSql.PS' -Parameters @{ ErrorRecord = $ErrorRecord; Uri = $Script:ODataUri } {
            param($ErrorRecord, $Uri)
            (Resolve-OmadaSqlRequestError -ErrorRecord $ErrorRecord -Method GET -Uri $Uri -ReadSucceeded $true).Kind | Should -Be 'SessionExpired'
        }
    }

    It 'Does not treat a 401 on a web service write as an OData permission problem' {
        $ErrorRecord = New-OmadaSqlTestHttpError -StatusCode 401
        InModuleScope 'OmadaSql.PS' -Parameters @{ ErrorRecord = $ErrorRecord } {
            param($ErrorRecord)
            (Resolve-OmadaSqlRequestError -ErrorRecord $ErrorRecord -Method POST -Uri 'https://tenant.omada.cloud/webservice/jQGridPopulationWebService.asmx/GetPagingData' -ReadSucceeded $true).Kind | Should -Be 'SessionExpired'
        }
    }

    It 'Classifies HTTP <StatusCode> as <Kind>' -ForEach @(
        @{ StatusCode = 403; Kind = 'AccessDenied' }
        @{ StatusCode = 404; Kind = 'NotFound' }
        @{ StatusCode = 500; Kind = 'ServerError' }
        @{ StatusCode = 503; Kind = 'ServerError' }
        @{ StatusCode = 400; Kind = 'RequestFailed' }
    ) {
        $ErrorRecord = New-OmadaSqlTestHttpError -StatusCode $StatusCode
        InModuleScope 'OmadaSql.PS' -Parameters @{ ErrorRecord = $ErrorRecord; Uri = $Script:ODataUri; Kind = $Kind; StatusCode = $StatusCode } {
            param($ErrorRecord, $Uri, $Kind, $StatusCode)
            $Result = Resolve-OmadaSqlRequestError -ErrorRecord $ErrorRecord -Method GET -Uri $Uri
            $Result.Kind | Should -Be $Kind
            $Result.StatusCode | Should -Be $StatusCode
        }
    }

    It 'Puts the response body (ErrorDetails) in the message when there is one' {
        $ErrorRecord = New-OmadaSqlTestHttpError -StatusCode 400 -Detail 'The query pipeline failed'
        InModuleScope 'OmadaSql.PS' -Parameters @{ ErrorRecord = $ErrorRecord; Uri = $Script:ODataUri } {
            param($ErrorRecord, $Uri)
            (Resolve-OmadaSqlRequestError -ErrorRecord $ErrorRecord -Method GET -Uri $Uri).Message | Should -BeLike '*The query pipeline failed*'
        }
    }
}
