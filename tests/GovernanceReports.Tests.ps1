<#
    Pester 5 tests for GovernanceReports.psm1

    These tests never touch a real tenant. Every Microsoft Graph command is
    replaced by a MOCK: a fake version that returns sample data we control.
    That lets us check the report logic exactly, offline and in CI.

    Run from the repo root:
      Invoke-Pester -Path ./tests -Output Detailed
#>

BeforeAll {
    # Pester can only mock a command that exists. If the Microsoft Graph
    # modules are not installed (for example on a CI runner), create empty
    # placeholder commands first. The mocks below replace them anyway.
    # The placeholders declare the same parameters the real commands use,
    # so that -ParameterFilter checks like { $GroupId -eq 'g1' } still work.
    $placeholders = @{
        'Get-MgUser'                                             = { param([switch]$All, [string[]]$Property, [string]$Filter) }
        'Get-MgGroup'                                            = { param([switch]$All, [string[]]$Property, [string]$Filter) }
        'Get-MgGroupOwner'                                       = { param([string]$GroupId, [switch]$All) }
        'Get-MgReportAuthenticationMethodUserRegistrationDetail' = { param([switch]$All) }
    }
    foreach ($name in $placeholders.Keys) {
        if (-not (Get-Command -Name $name -ErrorAction SilentlyContinue)) {
            New-Item -Path "Function:\global:$name" -Value $placeholders[$name] | Out-Null
        }
    }

    Import-Module (Join-Path $PSScriptRoot '../src/GovernanceReports.psm1') -Force

    # Helper that builds a fake Graph user
    function New-TestUser {
        param(
            [string]$Name,
            [bool]$Enabled = $true,
            [string]$UserType = 'Member',
            $LastSignIn = $null,
            [string[]]$SkuIds = @()
        )
        [pscustomobject]@{
            DisplayName       = $Name
            UserPrincipalName = "$($Name.ToLower())@lab.example"
            Mail              = "$($Name.ToLower())@lab.example"
            AccountEnabled    = $Enabled
            UserType          = $UserType
            CreatedDateTime   = (Get-Date).AddDays(-30)
            ExternalUserState = 'Accepted'
            SignInActivity    = [pscustomobject]@{ LastSignInDateTime = $LastSignIn }
            AssignedLicenses  = @($SkuIds | ForEach-Object { [pscustomobject]@{ SkuId = $_ } })
        }
    }
}

Describe 'Get-InactiveUsers' {
    BeforeAll {
        Mock Get-MgUser -ModuleName GovernanceReports {
            @(
                New-TestUser -Name 'Recent'   -LastSignIn (Get-Date).AddDays(-5)
                New-TestUser -Name 'Old'      -LastSignIn (Get-Date).AddDays(-200)
                New-TestUser -Name 'Never'    -LastSignIn $null
                New-TestUser -Name 'Disabled' -LastSignIn (Get-Date).AddDays(-200) -Enabled $false
                New-TestUser -Name 'Guest'    -LastSignIn (Get-Date).AddDays(-200) -UserType 'Guest'
            )
        }
    }

    It 'returns enabled members with no sign-in in the period, including never signed in' {
        $result = Get-InactiveUsers -Days 90
        ($result.DisplayName -join ',') | Should -Be 'Old,Never'
    }

    It 'marks accounts that have never signed in as Never' {
        (Get-InactiveUsers -Days 90 | Where-Object DisplayName -eq 'Never').LastSignIn | Should -Be 'Never'
    }

    It 'ignores disabled accounts and guests' {
        $result = Get-InactiveUsers -Days 90
        $result.DisplayName | Should -Not -Contain 'Disabled'
        $result.DisplayName | Should -Not -Contain 'Guest'
    }

    It 'respects the Days parameter' {
        (@(Get-InactiveUsers -Days 365).DisplayName -join ',') | Should -Be 'Never'
    }

    It 'rejects a Days value of zero' {
        { Get-InactiveUsers -Days 0 } | Should -Throw
    }
}

Describe 'Get-MfaGaps' {
    BeforeAll {
        Mock Get-MgReportAuthenticationMethodUserRegistrationDetail -ModuleName GovernanceReports {
            @(
                [pscustomobject]@{ UserPrincipalName = 'alice@lab.example';  IsAdmin = $false; IsMfaRegistered = $true }
                [pscustomobject]@{ UserPrincipalName = 'bob@lab.example';    IsAdmin = $false; IsMfaRegistered = $false }
                [pscustomobject]@{ UserPrincipalName = 'admin1@lab.example'; IsAdmin = $true;  IsMfaRegistered = $false }
            )
        }
    }

    It 'returns only users without MFA registered' {
        (Get-MfaGaps).UserPrincipalName | Should -Not -Contain 'alice@lab.example'
        @(Get-MfaGaps).Count | Should -Be 2
    }

    It 'lists admins first' {
        (Get-MfaGaps)[0].UserPrincipalName | Should -Be 'admin1@lab.example'
    }
}

Describe 'Get-OwnerlessTeams' {
    BeforeAll {
        Mock Get-MgGroup -ModuleName GovernanceReports {
            @(
                [pscustomobject]@{ Id = 'g1'; DisplayName = 'Finance Team';  ResourceProvisioningOptions = @('Team') }
                [pscustomobject]@{ Id = 'g2'; DisplayName = 'Orphaned Team'; ResourceProvisioningOptions = @('Team') }
                [pscustomobject]@{ Id = 'g3'; DisplayName = 'Plain Group';   ResourceProvisioningOptions = @() }
            )
        }
        Mock Get-MgGroupOwner -ModuleName GovernanceReports { @([pscustomobject]@{ Id = 'owner1' }) } -ParameterFilter { $GroupId -eq 'g1' }
        Mock Get-MgGroupOwner -ModuleName GovernanceReports { @() } -ParameterFilter { $GroupId -ne 'g1' }
    }

    It 'returns only teams that have no owner' {
        $result = @(Get-OwnerlessTeams)
        $result.Count | Should -Be 1
        $result[0].Team | Should -Be 'Orphaned Team'
    }

    It 'ignores Microsoft 365 groups that are not teams' {
        (Get-OwnerlessTeams).Team | Should -Not -Contain 'Plain Group'
    }
}

Describe 'Get-LicenceWaste' {
    BeforeAll {
        Mock Get-MgUser -ModuleName GovernanceReports {
            @(
                New-TestUser -Name 'Active'     -LastSignIn (Get-Date).AddDays(-3)   -SkuIds 'sku-premium'
                New-TestUser -Name 'Unused'     -LastSignIn (Get-Date).AddDays(-100) -SkuIds 'sku-premium', 'sku-p2'
                New-TestUser -Name 'NeverUsed'  -LastSignIn $null                    -SkuIds 'sku-premium'
                New-TestUser -Name 'NoLicence'  -LastSignIn $null
            )
        }
    }

    It 'returns licensed accounts with no sign-in in the period' {
        (@(Get-LicenceWaste -Days 60).DisplayName -join ',') | Should -Be 'Unused,NeverUsed'
    }

    It 'ignores accounts without a licence' {
        (Get-LicenceWaste -Days 60).DisplayName | Should -Not -Contain 'NoLicence'
    }

    It 'counts and lists every licence on the account' {
        $unused = Get-LicenceWaste -Days 60 | Where-Object DisplayName -eq 'Unused'
        $unused.LicenceCount | Should -Be 2
        $unused.SkuIds | Should -Be 'sku-premium;sku-p2'
    }
}

Describe 'Get-GuestUsers' {
    BeforeAll {
        Mock Get-MgUser -ModuleName GovernanceReports {
            @(
                New-TestUser -Name 'Partner' -UserType 'Guest' -LastSignIn (Get-Date).AddDays(-10)
                New-TestUser -Name 'Pending' -UserType 'Guest' -LastSignIn $null
            )
        }
    }

    It 'asks Graph for guests only' {
        Get-GuestUsers | Out-Null
        Should -Invoke Get-MgUser -ModuleName GovernanceReports -ParameterFilter { $Filter -eq "userType eq 'Guest'" }
    }

    It 'returns every guest with a last sign-in value' {
        $result = @(Get-GuestUsers)
        $result.Count | Should -Be 2
        ($result | Where-Object DisplayName -eq 'Pending').LastSignIn | Should -Be 'Never'
    }
}
