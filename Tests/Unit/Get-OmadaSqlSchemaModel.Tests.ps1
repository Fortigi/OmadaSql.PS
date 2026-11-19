param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaSql.PS\OmadaSql.PS.psm1')
)

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers\OmadaSqlTestHelper.ps1')
    Import-OmadaWebStub
    Get-Module -Name OmadaSql.PS -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Get-OmadaSqlSchemaModel' -Tag 'Unit' {
    BeforeEach {
        $Script:Connection = Initialize-OmadaSqlTestConnection
        Mock Get-OmadaSqlDataConnectionList -ModuleName 'OmadaSql.PS' {
            [pscustomobject]@{ Name = 'OISES'; Id = 1001 }
            [pscustomobject]@{ Name = 'ODW'; Id = 1002 }
        }
        Mock Get-OmadaSqlSchemaData -ModuleName 'OmadaSql.PS' { [pscustomobject]@{ 'dbo.tblDataObject' = @('Id int', 'DisplayName nvarchar(255)') } }
    }

    It 'Reads the schema of a data connection by name once and keeps it on the connection' {
        InModuleScope 'OmadaSql.PS' {
            $Context = Get-OmadaSqlConnectionContext
            $First = Get-OmadaSqlSchemaModel -Context $Context -DataConnection 'OISES'
            $Second = Get-OmadaSqlSchemaModel -Context $Context -DataConnection 1001
            [object]::ReferenceEquals($First, $Second) | Should -BeTrue
            $First.DataConnection.Name | Should -Be 'OISES'
            $Context.SchemaCache['1001'] | Should -Be $First
        }
        Should -Invoke Get-OmadaSqlSchemaData -ModuleName 'OmadaSql.PS' -Times 1 -Exactly -ParameterFilter { $DataConnectionId -eq 1001 }
    }

    It 'Keeps one schema per data connection' {
        InModuleScope 'OmadaSql.PS' {
            $Context = Get-OmadaSqlConnectionContext
            $null = Get-OmadaSqlSchemaModel -Context $Context -DataConnection 'OISES'
            $null = Get-OmadaSqlSchemaModel -Context $Context -DataConnection 'ODW'
            @($Context.SchemaCache.Keys | Sort-Object) | Should -Be @('1001', '1002')
        }
        Should -Invoke Get-OmadaSqlSchemaData -ModuleName 'OmadaSql.PS' -Times 2 -Exactly
    }

    It 'Reads the schema again with -Force' {
        InModuleScope 'OmadaSql.PS' {
            $Context = Get-OmadaSqlConnectionContext
            $null = Get-OmadaSqlSchemaModel -Context $Context -DataConnection 'OISES'
            $null = Get-OmadaSqlSchemaModel -Context $Context -DataConnection 'OISES' -Force
        }
        Should -Invoke Get-OmadaSqlSchemaData -ModuleName 'OmadaSql.PS' -Times 2 -Exactly
    }
}

Describe 'Get-OmadaSqlSchemaData' -Tag 'Unit' {
    BeforeEach {
        $Script:Connection = Initialize-OmadaSqlTestConnection
    }

    It 'Posts the data connection id as a string to GetSqlSchema and returns the d object' {
        Mock Invoke-OmadaSqlRequest -ModuleName 'OmadaSql.PS' { [pscustomobject]@{ d = [pscustomobject]@{ 'dbo.T' = @('Id int') } } }
        $Data = InModuleScope 'OmadaSql.PS' { Get-OmadaSqlSchemaData -Context (Get-OmadaSqlConnectionContext) -DataConnectionId 1001 }
        @($Data.'dbo.T') | Should -Be @('Id int')
        Should -Invoke Invoke-OmadaSqlRequest -ModuleName 'OmadaSql.PS' -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'POST' -and $Path -ceq 'webservice/SyntaxHighlighting.asmx/GetSqlSchema' -and $Body.connectionId -is [string] -and $Body.connectionId -eq '1001' -and $Body.Count -eq 1
        }
    }

    It 'Fails with InvalidResult when the answer has no d object' {
        Mock Invoke-OmadaSqlRequest -ModuleName 'OmadaSql.PS' { [pscustomobject]@{ other = 1 } }
        $Caught = InModuleScope 'OmadaSql.PS' { try { $null = Get-OmadaSqlSchemaData -Context (Get-OmadaSqlConnectionContext) -DataConnectionId 7 } catch { $_ } }
        $Caught.FullyQualifiedErrorId | Should -Be 'OmadaSql.InvalidResult'
        $Caught.Exception.Message | Should -Be 'Omada returned no schema for data connection 7.'
    }
}

Describe 'ConvertTo-OmadaSqlSchemaModel' -Tag 'Unit' {
    It 'Splits keys on the first dot and columns on the first white space, in order' {
        $Model = InModuleScope 'OmadaSql.PS' {
            $Data = [pscustomobject]@{
                'dbo.tblDataObject'         = @('Id int', 'DisplayName  nvarchar(255) ', '   ', 'Flag')
                'adhoc.viewUserGroupAccess' = @('IdentityId int')
                'odd.name.with.dots'        = @('A int')
            }
            ConvertTo-OmadaSqlSchemaModel -Data $Data -DataConnection ([pscustomobject]@{ Name = 'OISES'; Id = 1001 })
        }
        @($Model.Table.Keys | Sort-Object) | Should -Be @('adhoc.viewUserGroupAccess', 'dbo.tblDataObject', 'odd.name.with.dots')
        $Table = $Model.Table['DBO.TBLDATAOBJECT']
        $Table.PSObject.TypeNames[0] | Should -Be 'OmadaSql.SchemaTable'
        $Table.DataConnection | Should -Be 'OISES'
        $Table.Schema | Should -Be 'dbo'
        $Table.Table | Should -Be 'tblDataObject'
        $Table.Name | Should -Be 'dbo.tblDataObject'
        @($Table.Column.Name) | Should -Be @('Id', 'DisplayName', 'Flag')
        @($Table.Column.Type) | Should -Be @('int', 'nvarchar(255)', '')
        $Table.Column[0].PSObject.TypeNames[0] | Should -Be 'OmadaSql.SchemaColumn'
        $Model.Table['odd.name.with.dots'].Schema | Should -Be 'odd'
        $Model.Table['odd.name.with.dots'].Table | Should -Be 'name.with.dots'
        $Model.Column['dbo.tblDataObject']['displayname'] | Should -Be 'nvarchar(255)'
        $Model.DataConnection.Id | Should -Be 1001
    }

    It 'Skips keys without a schema or a table' {
        $Model = InModuleScope 'OmadaSql.PS' {
            ConvertTo-OmadaSqlSchemaModel -Data ([pscustomobject]@{ 'NoDot' = @('A int'); '.T' = @('A int'); 'S.' = @('A int'); 'dbo.Ok' = @('A int') }) -DataConnection ([pscustomobject]@{ Name = 'X'; Id = 1 })
        }
        @($Model.Table.Keys) | Should -Be @('dbo.Ok')
    }

    It 'Lists every schema that has a table of a name, and reads a dictionary answer' {
        $Model = InModuleScope 'OmadaSql.PS' {
            $Data = [ordered]@{ 'dbo.Person' = @('Id int'); 'audit.Person' = @('Id int', 'At datetime'); 'dbo.Contract' = @() }
            ConvertTo-OmadaSqlSchemaModel -Data $Data -DataConnection ([pscustomobject]@{ Name = 'X'; Id = 1 })
        }
        @($Model.ByName['person'].Name) | Should -Be @('dbo.Person', 'audit.Person')
        @($Model.ByName['Contract'].Name) | Should -Be @('dbo.Contract')
        @($Model.Table['dbo.Contract'].Column).Count | Should -Be 0
    }

    It 'Returns an empty model for an empty schema' {
        $Model = InModuleScope 'OmadaSql.PS' { ConvertTo-OmadaSqlSchemaModel -Data ([pscustomobject]@{}) -DataConnection ([pscustomobject]@{ Name = 'X'; Id = 1 }) }
        $Model.Table.Count | Should -Be 0
        $Model.ByName.Count | Should -Be 0
    }
}

Describe 'Get-OmadaSqlSchemaModel parameter contract' -Tag 'Unit' {
    # Parameter declarations run no code a test could observe, so the mutation gate's mutants of
    # Mandatory, Position, pipeline binding and ValidateRange are caught only by asserting the contract.
    It '<Command> -<Parameter> <ParameterSet>' -ForEach @(
        @{ Command = 'Get-OmadaSqlSchemaModel'; Parameter = 'Context'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Get-OmadaSqlSchemaModel'; Parameter = 'DataConnection'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Get-OmadaSqlSchemaData'; Parameter = 'Context'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Get-OmadaSqlSchemaData'; Parameter = 'DataConnectionId'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'ConvertTo-OmadaSqlSchemaModel'; Parameter = 'Data'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'ConvertTo-OmadaSqlSchemaModel'; Parameter = 'DataConnection'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'Get-OmadaSqlSchemaEntry'; Parameter = 'Data'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'New-OmadaSqlSchemaTable'; Parameter = 'Schema'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'New-OmadaSqlSchemaTable'; Parameter = 'Table'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
        @{ Command = 'New-OmadaSqlSchemaTable'; Parameter = 'DataConnectionName'; ParameterSet = ''; Mandatory = $true; Position = $null; ValueFromPipeline = $false; ValueFromPipelineByPropertyName = $false; RangeMin = $null; RangeMax = $null }
    ) {
        $Contract = Get-OmadaSqlParameterContract -CommandName $Command -ParameterName $Parameter -ParameterSetName $ParameterSet
        $Contract.Mandatory | Should -Be $Mandatory
        if ($null -ne $Position) {
            $Contract.Position | Should -Be $Position
        }
        $Contract.ValueFromPipeline | Should -Be $ValueFromPipeline
        $Contract.ValueFromPipelineByPropertyName | Should -Be $ValueFromPipelineByPropertyName
        $Contract.RangeMin | Should -Be $RangeMin
        $Contract.RangeMax | Should -Be $RangeMax
    }
}
