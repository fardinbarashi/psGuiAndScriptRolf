# Rolf : Windows Profile Cleanup Tools

![](githubRepoContentDeleteIfYouWant/img/logo.png)

## Overview
This repository contains four PowerShell-based tools for managing and removing inactive local Windows user profiles.
These tools are designed for IT administrators who manage shared workstations, lab environments, terminal servers, or enterprise devices where inactive profiles consume unnecessary disk space.

## ⚠️ Warning
Deleting a profile permanently removes:
* User files
* AppData
* Desktop/Documents
* Registry profile entries

## News :
### 1.1
```
Better code in the main script
```

## System requirements :
### Runtime
```
PowerShell 5
Permissions : Administrator
Remote operations require WinRM (WSMan) or DCOM/WMI access and rights.
```
---


The scripts are divided into:
```
- GUI versions (PsGuiRolf) for interactive administration.
  XAML GUI for local and remote profile cleanup
  Windows PowerShell : 7
  Permissions : Administrator 
  Runs on win 11, Remove related registry entries under: HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList 
  CLI Parameter - Option change
  $DaysFilterAccounts = (Get-Date).AddDays(-180)

- CLI versions (PsRolf) for automated or scheduled execution : 
  Modern CIM-based inactive profile cleanup ( CIM-based profile management )
  Windows PowerShell : 7
  Permissions : Administrator 
  Runs on win 11, Remove related registry entries under: HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList
  - Default exclusions:
   - Administrator
   - Default
   - Default User
   - Public
   - WDAGUtilityAccount
```

# 🖥️ PsGuiRolf - Win11
```
`PsGuiRolf - Win11` is the next-generation GUI where we go from WPF to XAML GUI application for managing local and remote Windows user profiles.
- XAML interface
- CIM operations
- WSMan → DCOM fallback
- Improved safety controls
- Better logging and exporting
It is designed for enterprise administration and modern Windows environments.
```
![](githubRepoContentDeleteIfYouWant/img/7.jpg)






