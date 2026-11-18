param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaSql.PS\OmadaSql.PS.psm1')
)

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers\OmadaSqlTestHelper.ps1')
    Import-OmadaWebStub
    Get-Module OmadaSql.PS | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Invoke-OmadaSqlRequest' -Tag 'Unit' {
    BeforeEach {
        $Script:Context = @{
            Connection       = [pscustomobject]@{ Id = 'c1'; BaseUrl = 'https://tenant.omada.cloud' }
            RequestParameter = @{ AuthenticationType = 'OAuth'; SessionKey = 'OmadaSql.PS'; ClientId = 'client' }
            ReadSucceeded    = $false
        }
    }

    It 'Builds the URI from the base URL and the path, and passes the connection parameters' {
        Mock Invoke-OmadaRestMethod -ModuleName 'OmadaSql.PS' { [pscustomobject]@{ value = @() } }
        InModuleScope 'OmadaSql.PS' -Parameters @{ Context = $Script:Context } {
            param($Context)
            $null = Invoke-OmadaSqlRequest -Context $Context -Method GET -Path '/odata/dataobjects/C_P_SQLTROUBLESHOOTING?$top=1'
        }
        Should -Invoke Invoke-OmadaRestMethod -ModuleName 'OmadaSql.PS' -Times 1 -Exactly -ParameterFilter {
            [string]$Uri -eq 'https://tenant.omada.cloud/odata/dataobjects/C_P_SQLTROUBLESHOOTING?$top=1' -and
            $Method -eq 'GET' -and
            $AuthenticationType -eq 'OAuth' -and
            $SessionKey -eq 'OmadaSql.PS' -and
            $ClientId -eq 'client' -and
            $ContentType -eq 'application/json; charset=utf-8' -and
            $null -eq $Body
        }
    }

    It 'Serializes an object body deeply' {
        Mock Invoke-OmadaRestMethod -ModuleName 'OmadaSql.PS' { $null }
        InModuleScope 'OmadaSql.PS' -Parameters @{ Context = $Script:Context } {
            param($Context)
            $Body = @{ dataTypeArgs = @{ level1 = @{ level2 = @{ level3 = 'deep' } } } }
            $null = Invoke-OmadaSqlRequest -Context $Context -Method POST -Path 'webservice/x.asmx/Y' -Body $Body
        }
        Should -Invoke Invoke-OmadaRestMethod -ModuleName 'OmadaSql.PS' -Times 1 -Exactly -ParameterFilter {
            $Body -is [string] -and (ConvertFrom-Json -InputObject $Body).dataTypeArgs.level1.level2.level3 -eq 'deep'
        }
    }

    It 'Sends a string body exactly as given' {
        Mock Invoke-OmadaRestMethod -ModuleName 'OmadaSql.PS' { $null }
        InModuleScope 'OmadaSql.PS' -Parameters @{ Context = $Script:Context } {
            param($Context)
            $null = Invoke-OmadaSqlRequest -Context $Context -Method POST -Path 'WebService/DataObjectWebService.asmx/UndeleteDataObject' -Body '{"id":42}'
        }
        Should -Invoke Invoke-OmadaRestMethod -ModuleName 'OmadaSql.PS' -Times 1 -Exactly -ParameterFilter { $Body -eq '{"id":42}' }
    }

    It 'Does not change the stored connection parameters' {
        Mock Invoke-OmadaRestMethod -ModuleName 'OmadaSql.PS' { $null }
        InModuleScope 'OmadaSql.PS' -Parameters @{ Context = $Script:Context } {
            param($Context)
            $null = Invoke-OmadaSqlRequest -Context $Context -Method GET -Path 'odata/x'
            $Context.RequestParameter.ContainsKey('Uri') | Should -BeFalse
            $Context.RequestParameter.ContainsKey('Method') | Should -BeFalse
        }
    }

    It 'Records a successful read on the connection, but not a successful write' {
        Mock Invoke-OmadaRestMethod -ModuleName 'OmadaSql.PS' { $null }
        InModuleScope 'OmadaSql.PS' -Parameters @{ Context = $Script:Context } {
            param($Context)
            $null = Invoke-OmadaSqlRequest -Context $Context -Method POST -Path 'odata/x' -Body @{}
            $Context.ReadSucceeded | Should -BeFalse
            $null = Invoke-OmadaSqlRequest -Context $Context -Method GET -Path 'odata/x'
            $Context.ReadSucceeded | Should -BeTrue
        }
    }

    It 'Returns the response' {
        Mock Invoke-OmadaRestMethod -ModuleName 'OmadaSql.PS' { [pscustomobject]@{ Id = 7 } }
        InModuleScope 'OmadaSql.PS' -Parameters @{ Context = $Script:Context } {
            param($Context)
            (Invoke-OmadaSqlRequest -Context $Context -Method GET -Path 'odata/x').Id | Should -Be 7
        }
    }

    It 'Turns a failure into an OmadaSql.<Kind> error that keeps the original' {
        Mock Invoke-OmadaRestMethod -ModuleName 'OmadaSql.PS' { throw (New-OmadaSqlTestHttpError -StatusCode 404) }
        InModuleScope 'OmadaSql.PS' -Parameters @{ Context = $Script:Context } {
            param($Context)
            $Caught = $null
            try {
                $null = Invoke-OmadaSqlRequest -Context $Context -Method GET -Path 'odata/dataobjects/C_P_SQLTROUBLESHOOTING(1)'
            }
            catch {
                $Caught = $_
            }
            $Caught.FullyQualifiedErrorId | Should -Be 'OmadaSql.NotFound'
            $Caught.TargetObject | Should -Be 'https://tenant.omada.cloud/odata/dataobjects/C_P_SQLTROUBLESHOOTING(1)'
            $Caught.Exception.InnerException | Should -Not -BeNullOrEmpty
        }
    }

    It 'Classifies a refused write after a successful read as a missing permission' {
        Mock Invoke-OmadaRestMethod -ModuleName 'OmadaSql.PS' { throw (New-OmadaSqlTestHttpError -StatusCode 401) }
        InModuleScope 'OmadaSql.PS' -Parameters @{ Context = $Script:Context } {
            param($Context)
            $Context.ReadSucceeded = $true
            { Invoke-OmadaSqlRequest -Context $Context -Method POST -Path 'odata/dataobjects/C_P_SQLTROUBLESHOOTING' -Body @{ NAME = 'x' } } | Should -Throw -ErrorId 'OmadaSql.MissingPermission'
        }
    }

    It 'Never writes the request body to the Verbose stream' {
        Mock Invoke-OmadaRestMethod -ModuleName 'OmadaSql.PS' { $null }
        InModuleScope 'OmadaSql.PS' -Parameters @{ Context = $Script:Context } {
            param($Context)
            $Verbose = Invoke-OmadaSqlRequest -Context $Context -Method POST -Path 'odata/x' -Body @{ C_QUERY = 'SELECT secret_marker_value' } -Verbose 4>&1 |
                Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
            @($Verbose).Count | Should -BeGreaterThan 0
            ($Verbose.Message -join "`n") | Should -Not -BeLike '*secret_marker_value*'
        }
    }
}
