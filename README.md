# M365 Governance Automation

> **Status: in progress.** This README is filled in as the project is built.

![Tests](https://github.com/Brightkakatech/m365-governance-automation/actions/workflows/test.yml/badge.svg)

## Summary

BrightKaka Tech is a fictional company used for my labs. This project automates five governance checks on its Microsoft 365 tenant. A scheduled Azure Automation runbook signs in with a **managed identity** (no stored password), reads the tenant through Microsoft Graph and saves each report as a CSV file in Azure Storage.

| Report | Question it answers |
|---|---|
| Inactive users | Which enabled accounts haven't signed in for 90 days? |
| MFA gaps | Who has no multifactor authentication method registered? (admins first) |
| Ownerless Teams | Which teams have nobody responsible for them? |
| Licence waste | Which licensed accounts haven't been used for 60 days? |
| Guest users | Which outside guests exist, and did they ever accept or sign in? |

Every report is **read-only**: the runbook's identity has read permissions only, so it cannot change anything in the tenant.

The tenant is the one built in my [Zero Trust identity lab](https://github.com/Brightkakatech/zero-trust-identity-lab).

## Architecture

![Architecture diagram](docs/diagrams/architecture.png)

A weekly schedule starts the runbook. It signs in with its managed identity, calls Microsoft Graph, and uploads the CSV reports to a storage container. GitHub Actions checks code style and runs the unit tests on every change.

## What you need

| Item | Detail |
|---|---|
| Licences | Microsoft Entra ID P1 (needed to read sign-in activity), through the Microsoft 365 Business Premium trial |
| Azure | Azure for Students subscription: Automation account, storage account |
| Graph permissions | User.Read.All, AuditLog.Read.All, Reports.Read.All, Group.Read.All (application, read only) |
| Tools | PowerShell 7, Microsoft Graph PowerShell SDK, Pester 5, PSScriptAnalyzer |
| Cost | Free or near free: Azure Automation includes free monthly job minutes |

## Testing

The report logic is tested without a tenant. Each Microsoft Graph command is replaced by a **mock** that returns sample data, so the tests check exactly what each report includes and excludes.

```powershell
Install-Module Pester -MinimumVersion 5.5.0 -MaximumVersion 5.99.99 -Scope CurrentUser -Force -SkipPublisherCheck
Install-Module PSScriptAnalyzer -Scope CurrentUser
Import-Module Pester -MinimumVersion 5.5.0 -MaximumVersion 5.99.99
Invoke-ScriptAnalyzer -Path ./src -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
Invoke-Pester -Path ./tests -Output Detailed
```

The tests are written for **Pester 5**, so the version is pinned below 6. On Windows, `-SkipPublisherCheck` is needed because Windows ships an old Pester 3.4.0 signed by Microsoft, while newer versions are signed by the Pester team.

## How it was built

_Step-by-step setup, written as each stage is completed._

## Results

_Screenshots and sample (anonymised) report output, added during the trial._

## What broke and what I learned

_Added during the build._

## Teardown

_Added at the end._

## Repository layout

```
README.md
PSScriptAnalyzerSettings.psd1   code style rules (one documented exception)
src/
  GovernanceReports.psm1        the five report functions
tests/
  GovernanceReports.Tests.ps1   Pester unit tests with mocked Graph data
.github/workflows/
  test.yml                      style check and tests on every push and pull request
docs/
  diagrams/                     architecture diagram
  screenshots/                  evidence for each stage
```

## Author

Bright Amalahu, Systems Administrator
[LinkedIn](https://www.linkedin.com/in/bright-amalahu/) · [Medium](https://medium.com/@brightkakatech) · [GitHub](https://github.com/Brightkakatech)
