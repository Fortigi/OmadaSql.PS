param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaSql.PS\OmadaSql.PS.psm1')
)

# The public commands end to end: OmadaSql.PS -> the real OmadaWeb.PS -> HTTP -> a local mock
# tenant that answers as Omada does. The unit tests mock every request; these prove the sequence
# of requests a command makes, their bodies, and that a temporary query object is removed again
# when a statement fails.
#
# The mock speaks plain http on 127.0.0.1, which Connect-OmadaSql refuses on purpose, so the
# connection is put in the module's connection store directly, with -AuthenticationType None,
# retries off and the data connection list already read.

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers\OmadaSqlMockServer.ps1')

    $RepositoryRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    $Pin = @((Import-PowerShellDataFile -Path (Join-Path $RepositoryRoot -ChildPath 'Build\BuildModules.psd1')).Modules | Where-Object { $_.Name -eq 'OmadaWeb.PS' })[0]
    Get-Module -Name 'OmadaWeb.PS' -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module -Name 'OmadaWeb.PS' -RequiredVersion $Pin.RequiredVersion -Force -Global -ErrorAction Stop
    Get-Module -Name OmadaSql.PS -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $ModulePath -Force -ErrorAction Stop

    $Script:Server = Start-OmadaSqlMockServer
    $Script:Entity = '/odata/dataobjects/C_P_SQLTROUBLESHOOTING'
    $Script:Paging = '/WebService/JQGridPopulationWebService.asmx/GetPagingData'
    $Script:Guid = [guid]::NewGuid().ToString('N')
    $Script:SlotName = 'TMP_{0}_1' -f $Script:Guid

    $SettingsPath = Join-Path $TestDrive 'settings.json'
    [System.IO.File]::WriteAllText($SettingsPath, (@{ InstanceGuid = $Script:Guid; MaxTempQuerySlots = 2 } | ConvertTo-Json))
    InModuleScope 'OmadaSql.PS' -Parameters @{ BaseUrl = $Script:Server.BaseUrl; SettingsPath = $SettingsPath } {
        param($BaseUrl, $SettingsPath)
        $Script:OmadaSqlSettingsPath = $SettingsPath
        $Script:OmadaSqlConnectionStore['integration'] = @{
            Connection          = [pscustomobject]@{ Id = 'integration'; BaseUrl = $BaseUrl }
            RequestParameter    = New-OmadaSqlRequestParameter -BoundParameter @{} -AuthenticationType 'None' -SessionKey ('OmadaSql.PS.Integration.{0}' -f [guid]::NewGuid().ToString('N')) -AdditionalParameter @{ MaximumRetryCount = 0 }
            ReadSucceeded       = $true
            DataConnectionCache = @([pscustomobject]@{ Name = 'OISES'; Id = 1001 })
        }
        $Script:OmadaSqlCurrentConnectionId = 'integration'
    }

    function Get-TestRequestLine {
        # The requests the mock received, as 'METHOD /path', in order; the site-root probe is left out.
        @(Get-OmadaSqlMockRequest -Server $Script:Server | Where-Object { $_.AbsolutePath -ne '/' } | ForEach-Object { '{0} {1}' -f $_.Method, $_.AbsolutePath })
    }

    function Get-TestRequestBody {
        param([string]$Method, [string]$Path)
        @(Get-OmadaSqlMockRequest -Server $Script:Server | Where-Object { $_.Method -eq $Method -and $_.AbsolutePath -eq $Path } | ForEach-Object { $_.Body | ConvertFrom-Json })
    }
}

AfterAll {
    if ($null -ne $Script:Server) {
        Stop-OmadaSqlMockServer -Server $Script:Server
    }
    Get-Module -Name OmadaSql.PS -All | Remove-Module -Force -ErrorAction SilentlyContinue
}

Describe 'Invoke-OmadaSqlQuery against a mock tenant' -Tag 'Integration' {
    BeforeEach {
        Reset-OmadaSqlMockServer -Server $Script:Server
        Set-OmadaSqlMockRoute -Server $Script:Server -Method POST -Path $Script:Paging -Body '{"d":{"Records":2,"Rows":[{"Id":"1","Name":"Users"},{"Id":"2","Name":"Admins"}]}}'
        Set-OmadaSqlMockRoute -Server $Script:Server -Method DELETE -Path "$($Script:Entity)(7001)" -Body '{}'
    }

    It 'Creates the temporary object, runs it and soft-deletes it again' {
        Set-OmadaSqlMockRoute -Server $Script:Server -Method GET -Path $Script:Entity -AnyQuery -Body '{"value":[]}'
        Set-OmadaSqlMockRoute -Server $Script:Server -Method POST -Path $Script:Entity -Body '{"Id":7001}'
        $Sql = 'SELECT [Id] = Id, [Name] = DisplayName FROM dbo.tblDataObject'

        $Rows = @(Invoke-OmadaSqlQuery -Query $Sql -DataConnection 'OISES')

        @($Rows.Name) | Should -Be @('Users', 'Admins')
        Get-TestRequestLine | Should -Be @("GET $($Script:Entity)", "POST $($Script:Entity)", "POST $($Script:Paging)", "DELETE $($Script:Entity)(7001)")
        $Probe = @(Get-OmadaSqlMockRequest -Server $Script:Server | Where-Object { $_.Method -eq 'GET' -and $_.AbsolutePath -eq $Script:Entity })[0]
        $Probe.Query | Should -BeLike '*DeletedStatus=Both*'
        $Probe.Query | Should -BeLike ("*NAME eq '{0}'*" -f $Script:SlotName)
        $Created = @(Get-TestRequestBody -Method POST -Path $Script:Entity)[0]
        $Created.NAME | Should -BeExactly $Script:SlotName
        $Created.C_QUERY | Should -BeExactly $Sql
        $Created.C_SQLTROUBLESHOOTING_DATACONNECTION.Id | Should -Be 1001
        $Run = @(Get-TestRequestBody -Method POST -Path $Script:Paging)[0]
        $Run.dataType | Should -Be 'SqlDataProducer'
        $Run.dataTypeArgs.targetId | Should -Be 7001
        $Run.rows | Should -Be 100000
    }

    It 'Restores and updates the soft-deleted slot left by an earlier run' {
        $Existing = '{{"value":[{{"Id":7001,"NAME":"{0}","Deleted":true,"C_QUERY":"SELECT 1","C_SQLTROUBLESHOOTING_DATACONNECTION":{{"Id":1001}}}}]}}' -f $Script:SlotName
        Set-OmadaSqlMockRoute -Server $Script:Server -Method GET -Path $Script:Entity -AnyQuery -Body $Existing
        Set-OmadaSqlMockRoute -Server $Script:Server -Method POST -Path '/WebService/DataObjectWebService.asmx/UndeleteDataObject' -Body '{"d":null}'
        Set-OmadaSqlMockRoute -Server $Script:Server -Method PUT -Path "$($Script:Entity)(7001)" -Body '{}'

        $null = Invoke-OmadaSqlQuery -Query 'SELECT [Id] = Id FROM dbo.tblDataObject' -DataConnection 'OISES'

        $Line = Get-TestRequestLine
        $Line | Should -Contain 'POST /WebService/DataObjectWebService.asmx/UndeleteDataObject'
        $Line | Should -Contain "PUT $($Script:Entity)(7001)"
        $Line | Should -Not -Contain "POST $($Script:Entity)"
        $Line[-1] | Should -Be "DELETE $($Script:Entity)(7001)"
        (Get-OmadaSqlMockRequest -Server $Script:Server | Where-Object { $_.AbsolutePath -like '*UndeleteDataObject' })[0].Body | Should -Be '{"id":7001}'
        (@(Get-TestRequestBody -Method PUT -Path "$($Script:Entity)(7001)")[0]).C_QUERY | Should -BeExactly 'SELECT [Id] = Id FROM dbo.tblDataObject'
    }

    It 'Soft-deletes the temporary object when the statement fails, and reports the failure' {
        Set-OmadaSqlMockRoute -Server $Script:Server -Method GET -Path $Script:Entity -AnyQuery -Body '{"value":[]}'
        Set-OmadaSqlMockRoute -Server $Script:Server -Method POST -Path $Script:Entity -Body '{"Id":7001}'
        Set-OmadaSqlMockRoute -Server $Script:Server -Method POST -Path $Script:Paging -StatusCode 500 -Body '{"Message":"The query pipeline failed at step ''ExecuteQuery''"}'

        $Rows = @(Invoke-OmadaSqlQuery -Query 'SELECT [Id] = Nope FROM dbo.tblDataObject' -DataConnection 'OISES' -ErrorVariable Failed -ErrorAction SilentlyContinue)

        $Rows.Count | Should -Be 0
        # -ErrorVariable also collects the errors commands inside OmadaWeb.PS write and handle
        # themselves; the one Invoke-OmadaSqlQuery reports carries its own name in the error id.
        $Reported = @($Failed | Where-Object { $_.FullyQualifiedErrorId -like '*,Invoke-OmadaSqlQuery' })
        $Reported.Count | Should -Be 1
        $Reported[0].FullyQualifiedErrorId | Should -BeLike 'OmadaSql.ServerError*'
        $Reported[0].Exception.Message | Should -BeLike 'Statement 1 (line 1) failed:*ExecuteQuery*'
        (Get-TestRequestLine)[-1] | Should -Be "DELETE $($Script:Entity)(7001)"
    }

    It 'Runs a saved object as it is and writes nothing' {
        Set-OmadaSqlMockRoute -Server $Script:Server -Method GET -Path "$($Script:Entity)(42)" -Body '{"Id":42,"NAME":"Daily export","C_QUERY":"SELECT [Id] = Id FROM dbo.tblDataObject","C_SQLTROUBLESHOOTING_DATACONNECTION":{"Id":1001}}'

        $Rows = @(Invoke-OmadaSqlQuery -Id 42)

        $Rows.Count | Should -Be 2
        Get-TestRequestLine | Should -Be @("GET $($Script:Entity)(42)", "POST $($Script:Paging)")
        (@(Get-TestRequestBody -Method POST -Path $Script:Paging)[0]).dataTypeArgs.targetId | Should -Be 42
    }

    It 'Writes the rows of a run to a CSV file' {
        Set-OmadaSqlMockRoute -Server $Script:Server -Method GET -Path "$($Script:Entity)(42)" -Body '{"Id":42,"NAME":"Daily export","C_QUERY":"SELECT [Id] = Id FROM dbo.tblDataObject","C_SQLTROUBLESHOOTING_DATACONNECTION":{"Id":1001}}'
        $Path = Join-Path $TestDrive 'daily.csv'

        Invoke-OmadaSqlQuery -Id 42 | Export-OmadaSqlResult -Path $Path -Force

        [System.IO.File]::ReadAllText($Path) | Should -BeExactly "`"Id`";`"Name`"`r`n`"1`";`"Users`"`r`n`"2`";`"Admins`"`r`n"
    }
}

Describe 'Schema commands against a mock tenant' -Tag 'Integration' {
    BeforeAll {
        $Script:SchemaPath = '/webservice/SyntaxHighlighting.asmx/GetSqlSchema'
    }

    BeforeEach {
        Reset-OmadaSqlMockServer -Server $Script:Server
        InModuleScope 'OmadaSql.PS' { $Script:OmadaSqlConnectionStore['integration'].Remove('SchemaCache') }
        Set-OmadaSqlMockRoute -Server $Script:Server -Method POST -Path $Script:SchemaPath -Body '{"d":{"dbo.tblDataObject":["Id int","DisplayName nvarchar(255)","Deleted bit"],"adhoc.viewUserGroupAccess":["IdentityId int"]}}'
    }

    It 'Reads the schema once with the data connection id as a string' {
        $Tables = @(Get-OmadaSqlSchema -DataConnection 'OISES')
        $null = Get-OmadaSqlSchema -DataConnection 'OISES' -Name 'dbo.*'

        @($Tables.Name) | Should -Be @('adhoc.viewUserGroupAccess', 'dbo.tblDataObject')
        @($Tables[1].Column.Type) | Should -Be @('int', 'nvarchar(255)', 'bit')
        Get-TestRequestLine | Should -Be @("POST $($Script:SchemaPath)")
        (Get-OmadaSqlMockRequest -Server $Script:Server -Path $Script:SchemaPath)[0].Body | Should -Be '{"connectionId":"1001"}'
    }

    It 'Checks column names in Test-OmadaSqlQuery -DataConnection' {
        $Diagnostic = @(Test-OmadaSqlQuery -Query 'SELECT [Name] = o.DisplayNam FROM dbo.tblDataObject AS o' -DataConnection 'OISES')

        @($Diagnostic.RuleId) | Should -Be @('OMD031')
        $Diagnostic[0].Message | Should -BeLike "Column 'DisplayNam' is not on 'dbo.tblDataObject'*"
    }
}

Describe 'Clear-OmadaSqlTempQuery against a mock tenant' -Tag 'Integration' {
    BeforeEach {
        Reset-OmadaSqlMockServer -Server $Script:Server
    }

    It 'Soft-deletes a live slot and purges every slot of this profile with -Purge' {
        $List = '{{"value":[{{"Id":8001,"NAME":"TMP_{0}_1","Deleted":false}},{{"Id":8002,"NAME":"TMP_{0}_2","Deleted":true}},{{"Id":8003,"NAME":"TMP_{1}_1","Deleted":true}}]}}' -f $Script:Guid, ([guid]::NewGuid().ToString('N'))
        Set-OmadaSqlMockRoute -Server $Script:Server -Method GET -Path $Script:Entity -AnyQuery -Body $List
        Set-OmadaSqlMockRoute -Server $Script:Server -Method DELETE -Path "$($Script:Entity)(8001)" -Body '{}'
        Set-OmadaSqlMockRoute -Server $Script:Server -Method POST -Path '/WebService/DataObjectWebService.asmx/PurgeDataObject' -Body '{"d":null}'

        $Result = @(Clear-OmadaSqlTempQuery -Purge -Confirm:$false)

        @($Result.Id) | Should -Be @(8001, 8002)
        $Line = @(Get-TestRequestLine | Where-Object { $_ -notlike 'GET *' })
        $Line | Should -Be @("DELETE $($Script:Entity)(8001)", 'POST /WebService/DataObjectWebService.asmx/PurgeDataObject', 'POST /WebService/DataObjectWebService.asmx/PurgeDataObject')
        @(Get-OmadaSqlMockRequest -Server $Script:Server | Where-Object { $_.AbsolutePath -like '*PurgeDataObject' } | ForEach-Object { $_.Body }) | Should -Be @('{"id":8001}', '{"id":8002}')
    }
}
