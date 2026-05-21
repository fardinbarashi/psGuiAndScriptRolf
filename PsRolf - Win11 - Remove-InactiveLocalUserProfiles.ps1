#requires -Version 7.0
#requires -RunAsAdministrator

<#
.SYNOPSIS
Removes inactive local Windows user profiles.

.DESCRIPTION
This script removes local Windows user profiles that have not been used for a specified number of days.

By default, the script checks for profiles that have not been used for 180 days.
Only profiles that are not special and not currently loaded will be removed.

When a profile is removed using Win32_UserProfile, Windows removes the local profile folder
and the related registry entry under:
HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList

.REQUIREMENTS
- Windows 11
- PowerShell 7.0 or later
- Must be run as Administrator
- Local administrator permissions
- CIM access to Win32_UserProfile
- Target user profiles must not be loaded
- Test with -WhatIf before deleting profiles

.NOTES
Author: Fardin.Barashi@gmail.com
Created: 2026-05-21
Version: 2.0
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "High")]
param(
    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 3650)]
    [int]$InactiveDays = 180,

    [Parameter(Mandatory = $false)]
    [string[]]$ExcludedProfileNames = @(
        "Administrator",
        "Default",
        "Default User",
        "Public",
        "WDAGUtilityAccount"
    )
)

#----------------------------------- Settings ------------------------------------------

$ErrorActionPreference = "Stop"

$CutoffDate = (Get-Date).AddDays(-$InactiveDays)

#----------------------------------- Start Script ------------------------------------------

try {
    Write-Host "Checking inactive local user profiles..." -ForegroundColor Cyan
    Write-Host "Inactive days: $InactiveDays" -ForegroundColor Cyan
    Write-Host "Cutoff date: $CutoffDate" -ForegroundColor Cyan
    Write-Host ""

    $Profiles = Get-CimInstance -ClassName Win32_UserProfile |
        Where-Object {
            $_.Special -eq $false -and
            $_.Loaded -eq $false -and
            $_.LastUseTime -ne $null -and
            $_.LastUseTime -le $CutoffDate
        } |
        Select-Object `
            SID,
            LocalPath,
            Loaded,
            Special,
            LastUseTime,
            @{Name = "ProfileName"; Expression = { Split-Path -Path $_.LocalPath -Leaf } }

    $ProfilesToRemove = $Profiles |
        Where-Object {
            $_.ProfileName -notin $ExcludedProfileNames
        }

    if (-not $ProfilesToRemove) {
        Write-Host "No inactive profiles found." -ForegroundColor Green
        return
    }

    Write-Host "Inactive profiles found: $($ProfilesToRemove.Count)" -ForegroundColor Yellow
    Write-Host ""

    foreach ($Profile in $ProfilesToRemove) {
        Write-Host "Profile:" -ForegroundColor Yellow
        Write-Host "  Name:        $($Profile.ProfileName)"
        Write-Host "  SID:         $($Profile.SID)"
        Write-Host "  LocalPath:   $($Profile.LocalPath)"
        Write-Host "  LastUseTime: $($Profile.LastUseTime)"
        Write-Host ""

        if ($PSCmdlet.ShouldProcess($Profile.LocalPath, "Remove inactive local user profile")) {
            $ProfileToDelete = Get-CimInstance -ClassName Win32_UserProfile |
                Where-Object {
                    $_.SID -eq $Profile.SID
                }

            if ($ProfileToDelete) {
                Remove-CimInstance -InputObject $ProfileToDelete
                Write-Host "Removed profile: $($Profile.LocalPath)" -ForegroundColor Green
            }
        }
    }

    Write-Host ""
    Write-Host "Script completed." -ForegroundColor Green
}
catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}