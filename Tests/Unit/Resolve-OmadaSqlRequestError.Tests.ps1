param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaSql.PS\OmadaSql.PS.psm1')
)

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers\OmadaSqlTestHelper.ps1')
    Get-Module -Name OmadaSql.PS -All | Remove-Module -Force -ErrorAction SilentlyContinue
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

    It 'Assumes no earlier read when -ReadSucceeded is omitted' {
        $ErrorRecord = New-OmadaSqlTestHttpError -StatusCode 401
        InModuleScope 'OmadaSql.PS' -Parameters @{ ErrorRecord = $ErrorRecord; Uri = $Script:ODataUri } {
            param($ErrorRecord, $Uri)
            (Resolve-OmadaSqlRequestError -ErrorRecord $ErrorRecord -Method POST -Uri $Uri).Kind | Should -Be 'SessionExpired'
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

    It 'Uses the exception message when ErrorDetails is empty' {
        $ErrorRecord = New-OmadaSqlTestHttpError -StatusCode 400 -Message 'exception text'
        $ErrorRecord.ErrorDetails = [System.Management.Automation.ErrorDetails]::new(' ')
        InModuleScope 'OmadaSql.PS' -Parameters @{ ErrorRecord = $ErrorRecord; Uri = $Script:ODataUri } {
            param($ErrorRecord, $Uri)
            (Resolve-OmadaSqlRequestError -ErrorRecord $ErrorRecord -Method GET -Uri $Uri).Message | Should -BeLike '*exception text*'
        }
    }

    It 'Classifies an error without any status code as RequestFailed' {
        $ErrorRecord = [System.Management.Automation.ErrorRecord]::new([System.Exception]::new('connection reset'), 'Test', [System.Management.Automation.ErrorCategory]::ConnectionError, $null)
        InModuleScope 'OmadaSql.PS' -Parameters @{ ErrorRecord = $ErrorRecord; Uri = $Script:ODataUri } {
            param($ErrorRecord, $Uri)
            $Result = Resolve-OmadaSqlRequestError -ErrorRecord $ErrorRecord -Method GET -Uri $Uri
            $Result.Kind | Should -Be 'RequestFailed'
            $Result.Message | Should -BeLike '*connection reset*'
        }
    }

    It 'Does not treat a GET on OData as a write' {
        $ErrorRecord = New-OmadaSqlTestHttpError -StatusCode 401
        InModuleScope 'OmadaSql.PS' -Parameters @{ ErrorRecord = $ErrorRecord; Uri = $Script:ODataUri } {
            param($ErrorRecord, $Uri)
            (Resolve-OmadaSqlRequestError -ErrorRecord $ErrorRecord -Method get -Uri $Uri -ReadSucceeded $true).Kind | Should -Be 'SessionExpired'
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

Describe 'Get-OmadaSqlRequestErrorKind' -Tag 'Unit' {
    It 'Returns <Expected> for <Case>' -ForEach @(
        @{ Case = 'the missing endpoint, whatever the status'; Parameter = @{ StatusCode = 401; Detail = "Resource not found for the segment 'C_P_SQLTROUBLESHOOTING'"; Unauthorized = $true; IsODataWrite = $true; ReadSucceeded = $true }; Expected = 'EndpointNotEnabled' }
        @{ Case = 'a refused write after a read'; Parameter = @{ StatusCode = 401; Detail = ''; Unauthorized = $true; IsODataWrite = $true; ReadSucceeded = $true }; Expected = 'MissingPermission' }
        @{ Case = 'a refused write before any read'; Parameter = @{ StatusCode = 401; Detail = ''; Unauthorized = $true; IsODataWrite = $true; ReadSucceeded = $false }; Expected = 'SessionExpired' }
        @{ Case = 'a refused read after a read'; Parameter = @{ StatusCode = 401; Detail = ''; Unauthorized = $true; IsODataWrite = $false; ReadSucceeded = $true }; Expected = 'SessionExpired' }
        @{ Case = 'HTTP 499'; Parameter = @{ StatusCode = 499; Detail = ''; Unauthorized = $false; IsODataWrite = $false; ReadSucceeded = $false }; Expected = 'RequestFailed' }
        @{ Case = 'HTTP 500'; Parameter = @{ StatusCode = 500; Detail = ''; Unauthorized = $false; IsODataWrite = $false; ReadSucceeded = $false }; Expected = 'ServerError' }
        @{ Case = 'no status code'; Parameter = @{ StatusCode = $null; Detail = ''; Unauthorized = $false; IsODataWrite = $false; ReadSucceeded = $false }; Expected = 'RequestFailed' }
    ) {
        InModuleScope 'OmadaSql.PS' -Parameters @{ Parameter = $Parameter; Expected = $Expected } {
            param($Parameter, $Expected)
            Get-OmadaSqlRequestErrorKind @Parameter | Should -Be $Expected
        }
    }
}

Describe 'Get-OmadaSqlRequestErrorMessage' -Tag 'Unit' {
    It 'Names the <Permission> permission for a refused <Method>' -ForEach @(
        @{ Method = 'POST'; Permission = 'Create' }
        @{ Method = 'PUT'; Permission = 'Update' }
        @{ Method = 'PATCH'; Permission = 'Update' }
        @{ Method = 'DELETE'; Permission = 'Delete' }
    ) {
        InModuleScope 'OmadaSql.PS' -Parameters @{ Method = $Method; Permission = $Permission } {
            param($Method, $Permission)
            Get-OmadaSqlRequestErrorMessage -Kind 'MissingPermission' -Method $Method -Uri 'https://tenant.omada.cloud/odata/x' -StatusCode 401 -Detail '' | Should -BeLike "*'$Permission' permission*"
        }
    }

    It 'Includes the status code and the detail for a server error' {
        InModuleScope 'OmadaSql.PS' {
            $Message = Get-OmadaSqlRequestErrorMessage -Kind 'ServerError' -Method 'POST' -Uri 'https://tenant.omada.cloud/webservice/x' -StatusCode 502 -Detail 'gateway'
            $Message | Should -BeLike '*HTTP 502*'
            $Message | Should -BeLike '*gateway*'
        }
    }
}

Describe 'Get-OmadaSqlErrorDetail' -Tag 'Unit' {
    It 'Puts the response body first, then every distinct exception message in the chain' {
        $Inner = [System.Exception]::new("Resource not found for the segment 'C_P_SQLTROUBLESHOOTING'.")
        $ErrorRecord = [System.Management.Automation.ErrorRecord]::new([System.Exception]::new('outer', $Inner), 'Test', [System.Management.Automation.ErrorCategory]::InvalidOperation, $null)
        $ErrorRecord.ErrorDetails = [System.Management.Automation.ErrorDetails]::new('body text')
        InModuleScope 'OmadaSql.PS' -Parameters @{ ErrorRecord = $ErrorRecord } {
            param($ErrorRecord)
            Get-OmadaSqlErrorDetail -ErrorRecord $ErrorRecord | Should -Be "body text | outer | Resource not found for the segment 'C_P_SQLTROUBLESHOOTING'."
        }
    }

    It 'Classifies a missing segment reported only in an inner exception as EndpointNotEnabled' {
        $Inner = [System.Exception]::new("Resource not found for the segment 'C_P_SQLTROUBLESHOOTING'.")
        $ErrorRecord = [System.Management.Automation.ErrorRecord]::new([System.Exception]::new('Response status code does not indicate success: 404 (Not Found).', $Inner), 'Test', [System.Management.Automation.ErrorCategory]::InvalidOperation, $null)
        InModuleScope 'OmadaSql.PS' -Parameters @{ ErrorRecord = $ErrorRecord } {
            param($ErrorRecord)
            (Resolve-OmadaSqlRequestError -ErrorRecord $ErrorRecord -Method GET -Uri 'https://tenant.omada.cloud/odata/dataobjects/C_P_SQLTROUBLESHOOTING').Kind | Should -Be 'EndpointNotEnabled'
        }
    }
}

Describe 'Get-OmadaSqlErrorDetail escapes' -Tag 'Unit' {
    It 'Decodes the \u escapes PowerShell 7 writes into a re-serialized JSON error body' {
        $Body = "{`n  ""error"": {`n    ""message"": ""Resource not found for the segment \u0027C_P_SQLTROUBLESHOOTING\u0027.""`n  }`n}"
        $ErrorRecord = New-OmadaSqlTestHttpError -StatusCode 404 -Detail $Body
        InModuleScope 'OmadaSql.PS' -Parameters @{ ErrorRecord = $ErrorRecord } {
            param($ErrorRecord)
            Get-OmadaSqlErrorDetail -ErrorRecord $ErrorRecord | Should -BeLike "*segment 'C_P_SQLTROUBLESHOOTING'.*"
            (Resolve-OmadaSqlRequestError -ErrorRecord $ErrorRecord -Method GET -Uri 'https://tenant.omada.cloud/odata/dataobjects/C_P_SQLTROUBLESHOOTING').Kind | Should -Be 'EndpointNotEnabled'
        }
    }
}

Describe 'Resolve-OmadaSqlRequestError parameter contract' -Tag 'Unit' {
    # Parameter declarations run no code a test could observe, so the mutation gate's mutants of
    # Mandatory, Position, pipeline binding and ValidateRange are caught only by asserting the contract.
    It '<Command> -<Parameter> <ParameterSet>' -ForEach @(
        @{ Command = 'Resolve-OmadaSqlRequestError'; Parameter = 'ErrorRecord'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Resolve-OmadaSqlRequestError'; Parameter = 'Method'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Resolve-OmadaSqlRequestError'; Parameter = 'Uri'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Get-OmadaSqlErrorDetail'; Parameter = 'ErrorRecord'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Get-OmadaSqlRequestErrorMessage'; Parameter = 'Kind'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Get-OmadaSqlRequestErrorMessage'; Parameter = 'Method'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Get-OmadaSqlRequestErrorMessage'; Parameter = 'Uri'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
    ) {
        $Contract = Get-OmadaSqlParameterContract -CommandName $Command -ParameterName $Parameter -ParameterSetName $ParameterSet
        $Contract.Mandatory | Should -Be $Mandatory
        # Only a declared position is part of the contract: without one PowerShell numbers the
        # parameters of an advanced function in declaration order, which no mutant can change.
        if ($null -ne $Position) {
            $Contract.Position | Should -Be $Position
        }
        $Contract.ValueFromPipeline | Should -Be $ValueFromPipeline
        $Contract.ValueFromPipelineByPropertyName | Should -Be $ValueFromPipelineByPropertyName
        $Contract.RangeMin | Should -Be $RangeMin
        $Contract.RangeMax | Should -Be $RangeMax
    }
}
