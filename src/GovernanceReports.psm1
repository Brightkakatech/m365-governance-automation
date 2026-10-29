<#
.SYNOPSIS
    Read-only governance reports for a Microsoft 365 tenant.

.DESCRIPTION
    Each function answers one governance question using Microsoft Graph.
    The functions only READ data. They never change users, groups or licences.

    Sign in before calling them:
      On a PC:              Connect-MgGraph -Scopes 'User.Read.All','AuditLog.Read.All','Reports.Read.All','Group.Read.All'
      In Azure Automation:  Connect-MgGraph -Identity   (managed identity, no password)

    Required Microsoft Graph permissions (application permissions for the runbook):
      User.Read.All, AuditLog.Read.All, Reports.Read.All, Group.Read.All

    Reading sign-in activity (signInActivity) requires Microsoft Entra ID P1.
#>

function Get-InactiveUsers {
    <#
    .SYNOPSIS
        Enabled accounts that have not signed in for a given number of days.
    .DESCRIPTION
        Accounts that are enabled but unused are a security risk: nobody notices
        if an attacker starts using them. Accounts that have never signed in
        are included and marked 'Never'.
    .PARAMETER Days
        How many days without a sign-in counts as inactive. Default 90.
    #>
    [CmdletBinding()]
    param(
        [ValidateRange(1, 3650)]
        [int]$Days = 90
    )

    $cutoff = (Get-Date).AddDays(-$Days)

    Get-MgUser -All -Property 'DisplayName', 'UserPrincipalName', 'AccountEnabled', 'SignInActivity', 'UserType' |
        Where-Object { $_.AccountEnabled -and $_.UserType -ne 'Guest' } |
        ForEach-Object {
            $lastSignIn = $_.SignInActivity.LastSignInDateTime
            if (-not $lastSignIn -or $lastSignIn -lt $cutoff) {
                [pscustomobject]@{
                    DisplayName       = $_.DisplayName
                    UserPrincipalName = $_.UserPrincipalName
                    LastSignIn        = if ($lastSignIn) { $lastSignIn } else { 'Never' }
                }
            }
        }
}

function Get-MfaGaps {
    <#
    .SYNOPSIS
        Users who have not registered any multifactor authentication method.
    .DESCRIPTION
        A user with no MFA method cannot complete an MFA prompt. When a
        Conditional Access policy starts requiring MFA, these users are either
        locked out or forced to register on the spot. Admins without MFA are
        the highest risk, so they are listed first.
    #>
    [CmdletBinding()]
    param()

    Get-MgReportAuthenticationMethodUserRegistrationDetail -All |
        Where-Object { -not $_.IsMfaRegistered } |
        Sort-Object -Property @{ Expression = 'IsAdmin'; Descending = $true }, 'UserPrincipalName' |
        Select-Object -Property 'UserPrincipalName', 'IsAdmin', 'IsMfaRegistered'
}

function Get-OwnerlessTeams {
    <#
    .SYNOPSIS
        Microsoft Teams that have no owner.
    .DESCRIPTION
        A team without an owner has nobody responsible for its members,
        guests or content, and nobody to approve access requests.
    #>
    [CmdletBinding()]
    param()

    $groups = Get-MgGroup -All -Filter "groupTypes/any(c:c eq 'Unified')" -Property 'Id', 'DisplayName', 'ResourceProvisioningOptions'

    foreach ($group in $groups | Where-Object { $_.ResourceProvisioningOptions -contains 'Team' }) {
        $owners = @(Get-MgGroupOwner -GroupId $group.Id -All)
        if ($owners.Count -eq 0) {
            [pscustomobject]@{
                Team    = $group.DisplayName
                GroupId = $group.Id
            }
        }
    }
}

function Get-LicenceWaste {
    <#
    .SYNOPSIS
        Licensed accounts that have not signed in for a given number of days.
    .DESCRIPTION
        A licence assigned to an account nobody uses is money spent for nothing.
        Accounts that have never signed in are included and marked 'Never'.
    .PARAMETER Days
        How many days without a sign-in counts as unused. Default 60.
    #>
    [CmdletBinding()]
    param(
        [ValidateRange(1, 3650)]
        [int]$Days = 60
    )

    $cutoff = (Get-Date).AddDays(-$Days)

    Get-MgUser -All -Property 'DisplayName', 'UserPrincipalName', 'AssignedLicenses', 'SignInActivity' |
        Where-Object { @($_.AssignedLicenses).Count -gt 0 } |
        ForEach-Object {
            $lastSignIn = $_.SignInActivity.LastSignInDateTime
            if (-not $lastSignIn -or $lastSignIn -lt $cutoff) {
                [pscustomobject]@{
                    DisplayName       = $_.DisplayName
                    UserPrincipalName = $_.UserPrincipalName
                    LicenceCount      = @($_.AssignedLicenses).Count
                    SkuIds            = (@($_.AssignedLicenses) | ForEach-Object { $_.SkuId }) -join ';'
                    LastSignIn        = if ($lastSignIn) { $lastSignIn } else { 'Never' }
                }
            }
        }
}

function Get-GuestUsers {
    <#
    .SYNOPSIS
        All guest accounts, with their invitation state and last sign-in.
    .DESCRIPTION
        Guests are people from outside the organisation. Guests who never
        accepted their invitation, or who stopped signing in, should be
        reviewed and usually removed.
    #>
    [CmdletBinding()]
    param()

    Get-MgUser -All -Filter "userType eq 'Guest'" -Property 'DisplayName', 'Mail', 'UserPrincipalName', 'CreatedDateTime', 'ExternalUserState', 'SignInActivity' |
        ForEach-Object {
            $lastSignIn = $_.SignInActivity.LastSignInDateTime
            [pscustomobject]@{
                DisplayName       = $_.DisplayName
                Mail              = $_.Mail
                InvitationState   = $_.ExternalUserState
                Created           = $_.CreatedDateTime
                LastSignIn        = if ($lastSignIn) { $lastSignIn } else { 'Never' }
            }
        }
}

Export-ModuleMember -Function 'Get-InactiveUsers', 'Get-MfaGaps', 'Get-OwnerlessTeams', 'Get-LicenceWaste', 'Get-GuestUsers'
