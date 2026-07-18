<#
.SYNOPSIS
    Rolf - Win11 - Modern WPF GUI for inventorying and removing local/remote Windows user profiles.

.DESCRIPTION
    A PowerShell WPF (XAML) application to scan a local or remote computer for user
    profiles and safely remove inactive ones.

    Structure:
      Rolf.ps1                          This file. Loads type, UI, functions, wires events.
      Settings\UI\MainWindow.xaml       The whole window as XAML.
      Settings\Types\ProfileItem.cs     The INotifyPropertyChanged backing class.
      Settings\Functions\*.ps1          One function per file, dot-sourced below.

    Load order matters. The functions reach WPF controls like $Progress and $Grid
    by script-scope variable, so they are dot-sourced AFTER the controls exist -
    not at the top. Dot-sourcing only defines them; they are not called until a
    button is clicked, by which point every control exists.

.NOTES
    Original author : Fardin Barashi
    Requires        : Windows PowerShell 5.1 or PowerShell 7+, run as Administrator.
                      Remote operations require WinRM (WSMan) or DCOM/WMI access and rights.

.WARNING
    Removing a user profile permanently deletes that user's local data (desktop,
    documents, AppData, registry hive entry). There is no undo.
#>

$ErrorActionPreference = 'Stop'

#----------------------------------------------------------------------------------------------
#  Assemblies
#----------------------------------------------------------------------------------------------
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms

#----------------------------------------------------------------------------------------------
#  Paths
#----------------------------------------------------------------------------------------------
$Script:AppName     = 'Rolf'
$Script:Root        = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$Script:LogDir      = Join-Path $Script:Root 'Settings\Logs'
$Script:XamlPath    = Join-Path $Script:Root 'Settings\UI\MainWindow.xaml'
$Script:TypePath    = Join-Path $Script:Root 'Settings\Types\ProfileItem.cs'
$Script:FuncDir     = Join-Path $Script:Root 'Settings\Functions'

if (-not (Test-Path $Script:LogDir)) { New-Item -ItemType Directory -Path $Script:LogDir -Force | Out-Null }

#----------------------------------------------------------------------------------------------
#  Backing data type (INotifyPropertyChanged so the check boxes update live)
#----------------------------------------------------------------------------------------------
if (-not ('Rolf.ProfileItem' -as [type])) {
    if (-not (Test-Path $Script:TypePath)) { throw "Cannot find the type file: $Script:TypePath" }
    $cs = Get-Content -Raw -Encoding UTF8 $Script:TypePath

    if ($PSVersionTable.PSEdition -eq 'Core') {
        # PowerShell 7: reference the assemblies by name from the shared framework
        Add-Type -TypeDefinition $cs -ReferencedAssemblies @(
            'System.ObjectModel',
            'System.ComponentModel',
            'System.ComponentModel.Primitives',
            'WindowsBase'
        )
    }
    else {
        # Windows PowerShell 5.1: WindowsBase pulls in what INotifyPropertyChanged needs
        Add-Type -TypeDefinition $cs -ReferencedAssemblies WindowsBase
    }
}

#----------------------------------------------------------------------------------------------
#  Settings & logging
#----------------------------------------------------------------------------------------------
$Script:Stamp       = Get-Date -Format 'yyyyMMdd-HHmmss'
$Script:Transcript  = Join-Path $Script:LogDir "Rolf-$Script:Stamp.txt"
$Script:ActionLog   = Join-Path $Script:LogDir "Rolf-Actions-$Script:Stamp.csv"
$Script:Profiles    = New-Object 'System.Collections.ObjectModel.ObservableCollection[Rolf.ProfileItem]'
$Script:AllProfiles = New-Object 'System.Collections.Generic.List[Rolf.ProfileItem]'
$Script:Computer    = $env:COMPUTERNAME

try { Start-Transcript -Path $Script:Transcript -Force | Out-Null } catch { }

$Script:ProtectedNames = @('Default','Default User','Public','All Users','Administrator',
                           'systemprofile','LocalService','NetworkService','defaultuser0')

#----------------------------------------------------------------------------------------------
#  Load XAML from file and wire up named controls
#----------------------------------------------------------------------------------------------
if (-not (Test-Path $Script:XamlPath)) { throw "Cannot find the UI file: $Script:XamlPath" }

$XamlText = Get-Content -Raw -Encoding UTF8 $Script:XamlPath
[xml]$Xaml = $XamlText
$reader = New-Object System.Xml.XmlNodeReader $Xaml
$Window = [Windows.Markup.XamlReader]::Load($reader)

$Sync = @{}
foreach ($m in [regex]::Matches($XamlText, 'x:Name="([^"]+)"')) {
    $name = $m.Groups[1].Value
    $ctrl = $Window.FindName($name)
    $Sync[$name] = $ctrl
    Set-Variable -Name $name -Value $ctrl -Scope Script
}

$Grid.ItemsSource = $Script:Profiles

#----------------------------------------------------------------------------------------------
#  Load functions - after the controls exist, so they can reach them by name
#----------------------------------------------------------------------------------------------
if (-not (Test-Path $Script:FuncDir)) { throw "Function folder not found: $Script:FuncDir" }

$functionFiles = Get-ChildItem -Path $Script:FuncDir -Filter '*.ps1' -File
if (-not $functionFiles) { throw "No .ps1 files found in $Script:FuncDir" }

foreach ($file in $functionFiles) {
    try   { . $file.FullName }
    catch { throw "Failed to load function file '$($file.Name)': $($_.Exception.Message)" }
}

#----------------------------------------------------------------------------------------------
#  Event wiring
#----------------------------------------------------------------------------------------------
$BtnConnect.Add_Click({ Invoke-Scan })
$TxtComputer.Add_KeyDown({ if ($_.Key -eq 'Return') { Invoke-Scan } })
$BtnLocal.Add_Click({ $TxtComputer.Text = $env:COMPUTERNAME; Invoke-Scan })
$BtnDelete.Add_Click({ Remove-Selected })
$BtnSizes.Add_Click({ Get-Sizes })
$BtnExport.Add_Click({ Export-List })
$BtnOpen.Add_Click({ Open-UsersFolder })
$BtnClear.Add_Click({ $Script:AllProfiles.Clear(); $Script:Profiles.Clear(); Update-Summary; Set-Status 'Cleared.' })
$BtnSelectAll.Add_Click({ foreach ($p in $Script:Profiles) { $p.IsSelected = -not $p.Protected }; Update-Summary })
$BtnSelectInactive.Add_Click({ foreach ($p in $Script:Profiles) { $p.IsSelected = ($p.Inactive -and -not $p.Protected) }; Update-Summary })
$TxtFilter.Add_TextChanged({ Update-Grid })
$ChkOnlyInactive.Add_Click({ Update-Grid })

# Allow digits only in the days box, but any number of them
$TxtDays.Add_PreviewTextInput({ if ($args[1].Text -notmatch '^[0-9]+$') { $args[1].Handled = $true } })
$TxtDays.Add_TextChanged({
    $d = 0; [void][int]::TryParse($TxtDays.Text, [ref]$d)
    foreach ($p in $Script:AllProfiles) { $p.Inactive = ($d -gt 0 -and $p.InactiveDays -ge $d) }
    Update-Grid
})
$Grid.Add_CurrentCellChanged({ Update-Summary })
$BtnPing.Add_Click({ Invoke-Ping })
$BtnLogoff.Add_Click({ Invoke-LogoffAll })
$BtnReboot.Add_Click({ Invoke-Reboot })

#----------------------------------------------------------------------------------------------
#  Init
#----------------------------------------------------------------------------------------------
$TxtComputer.Text = $env:COMPUTERNAME
$HostHint.Text    = "Running on $env:COMPUTERNAME as $env:USERNAME"
if (-not (Test-IsAdmin)) { $AdminBadge.Text = 'Not running as administrator - deletions may fail.' }
Update-Summary

$Window.Add_Closed({ try { Stop-Transcript | Out-Null } catch { } })
$Window.ShowDialog() | Out-Null
