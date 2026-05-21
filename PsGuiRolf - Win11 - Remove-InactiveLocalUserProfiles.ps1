<#
.SYNOPSIS
    PsGuiRolf - Win11 - Modern WPF GUI for inventorying and removing local/remote Windows user profiles.

.DESCRIPTION
    A self-contained PowerShell WPF (XAML) application to scan a local or remote computer for
    user profiles and safely remove inactive ones..

    Key features
      * CIM-based (Get-CimInstance / Remove-CimInstance) with automatic WSMan -> DCOM fallback,
      * Dry-run (WhatIf) mode: simulate deletions and log them without touching anything.
      * Safety guards: never deletes Special, currently-loaded, or well-known system profiles.
      * Action logging to CSV + full PowerShell transcript.
      * Export the current list to CSV, calculate profile sizes, open \\host\C$\Users,
        ping, reboot, and force-logoff-all-users tools.

.NOTES
    Original author : Fardin Barashi 
    Requires        : Windows PowerShell 5.1 or PowerShell 7+, run as Administrator.
                      Remote operations require WinRM (WSMan) or DCOM/WMI access and rights.

.WARNING
    Removing a user profile permanently deletes that user's local data (desktop, documents,
    AppData, registry hive entry). There is no undo.
#>


#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#----------------------------------------------------------------------------------------------
#  Assemblies
#----------------------------------------------------------------------------------------------
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms

#----------------------------------------------------------------------------------------------
#  Backing data type (INotifyPropertyChanged so the check boxes update live)
#----------------------------------------------------------------------------------------------
if (-not ('Rolf.ProfileItem' -as [type])) {
    Add-Type -ReferencedAssemblies WindowsBase -TypeDefinition @'
using System.ComponentModel;
namespace Rolf {
    public class ProfileItem : INotifyPropertyChanged {
        public event PropertyChangedEventHandler PropertyChanged;
        private bool _isSelected;
        public bool IsSelected {
            get { return _isSelected; }
            set { if (_isSelected != value) { _isSelected = value; OnChanged("IsSelected"); } }
        }
        public string UserName     { get; set; }
        public string Sid          { get; set; }
        public string LocalPath    { get; set; }
        public string LastUseTime  { get; set; }
        public int    InactiveDays { get; set; }
        public bool   Loaded       { get; set; }
        public bool   Special      { get; set; }
        public bool   Protected    { get; set; }
        public bool   Inactive     { get; set; }
        public string SizeText     { get; set; }
        public double SizeBytes    { get; set; }
        private void OnChanged(string p) {
            var h = PropertyChanged;
            if (h != null) { h(this, new PropertyChangedEventArgs(p)); }
        }
    }
}
'@
}

#----------------------------------------------------------------------------------------------
#  Settings & logging
#----------------------------------------------------------------------------------------------
$Script:AppName     = 'Rolf'
$Script:Root        = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$Script:LogDir      = Join-Path $Script:Root 'Logs'
if (-not (Test-Path $Script:LogDir)) { New-Item -ItemType Directory -Path $Script:LogDir -Force | Out-Null }
$Script:Stamp       = Get-Date -Format 'yyyyMMdd-HHmmss'
$Script:Transcript  = Join-Path $Script:LogDir "Rolf-$Script:Stamp.txt"
$Script:ActionLog   = Join-Path $Script:LogDir "Rolf-Actions-$Script:Stamp.csv"
$Script:Profiles    = New-Object 'System.Collections.ObjectModel.ObservableCollection[Rolf.ProfileItem]'
$Script:AllProfiles = New-Object 'System.Collections.Generic.List[Rolf.ProfileItem]'
$Script:Computer    = $env:COMPUTERNAME

try { Start-Transcript -Path $Script:Transcript -Force | Out-Null } catch { }

$Script:ProtectedNames = @('Default','Default User','Public','All Users','Administrator',
                           'systemprofile','LocalService','NetworkService','defaultuser0')

function Write-ActionLog {
    param([string]$Action,[string]$Target,[string]$Sid,[string]$Path,[string]$Result)
    [pscustomobject]@{
        Time     = (Get-Date -Format 's')
        Action   = $Action
        Computer = $Target
        Sid      = $Sid
        Path     = $Path
        Result   = $Result
        DryRun   = [bool]$WhatIf.IsChecked
        RunAs    = $env:USERNAME
    } | Export-Csv -Path $Script:ActionLog -Append -NoTypeInformation -Encoding UTF8
}

#----------------------------------------------------------------------------------------------
#  XAML  (light Fluent theme, sidebar layout)
#----------------------------------------------------------------------------------------------
$XamlText = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Rolf" Height="900" Width="1600" MinHeight="560" MinWidth="1080"
        WindowStartupLocation="CenterScreen" Background="#FFF4F5F7"
        FontFamily="Segoe UI" FontSize="13" TextOptions.TextFormattingMode="Display">

  <Window.Resources>
    <!-- Palette (light) -->
    <SolidColorBrush x:Key="Bg"          Color="#FFF4F5F7"/>
    <SolidColorBrush x:Key="Card"        Color="#FFFFFFFF"/>
    <SolidColorBrush x:Key="CardAlt"     Color="#FFF8F9FB"/>
    <SolidColorBrush x:Key="Border"      Color="#FFE2E5EA"/>
    <SolidColorBrush x:Key="BorderStrong" Color="#FFD0D5DD"/>
    <SolidColorBrush x:Key="Text"        Color="#FF1F2329"/>
    <SolidColorBrush x:Key="Muted"       Color="#FF6B7280"/>
    <SolidColorBrush x:Key="Accent"      Color="#FF2563EB"/>
    <SolidColorBrush x:Key="AccentHover" Color="#FF1D4ED8"/>
    <SolidColorBrush x:Key="Danger"      Color="#FFDC2626"/>
    <SolidColorBrush x:Key="DangerHover" Color="#FFB91C1C"/>
    <SolidColorBrush x:Key="Warn"        Color="#FFB45309"/>
    <SolidColorBrush x:Key="GoodChip"    Color="#FFEFF4FF"/>

    <!-- Section header -->
    <Style x:Key="Section" TargetType="TextBlock">
      <Setter Property="Foreground" Value="{StaticResource Muted}"/>
      <Setter Property="FontSize" Value="11"/>
      <Setter Property="FontWeight" Value="Bold"/>
      <Setter Property="Margin" Value="0,14,0,6"/>
    </Style>

    <!-- Primary / accent button -->
    <Style x:Key="BtnPrimary" TargetType="Button">
      <Setter Property="Background" Value="{StaticResource Accent}"/>
      <Setter Property="Foreground" Value="White"/>
      <Setter Property="Padding" Value="12,8"/>
      <Setter Property="Margin" Value="0,0,0,0"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="HorizontalContentAlignment" Value="Center"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="b" Background="{TemplateBinding Background}" CornerRadius="6"
                    Padding="{TemplateBinding Padding}" SnapsToDevicePixels="True">
              <Border.Effect>
                <DropShadowEffect Color="#FF2563EB" BlurRadius="8" ShadowDepth="1" Opacity="0.28"/>
              </Border.Effect>
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="b" Property="Background" Value="{StaticResource AccentHover}"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="b" Property="RenderTransform">
                  <Setter.Value><TranslateTransform Y="1"/></Setter.Value>
                </Setter>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="b" Property="Opacity" Value="0.5"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- Secondary button: white fill, clear border + soft shadow (reads as a real button) -->
    <Style x:Key="BtnGhost" TargetType="Button">
      <Setter Property="Background" Value="{StaticResource Card}"/>
      <Setter Property="Foreground" Value="{StaticResource Text}"/>
      <Setter Property="Padding" Value="12,8"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="HorizontalContentAlignment" Value="Center"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="b" Background="{TemplateBinding Background}" CornerRadius="6"
                    BorderBrush="{StaticResource BorderStrong}" BorderThickness="1"
                    Padding="{TemplateBinding Padding}" SnapsToDevicePixels="True">
              <Border.Effect>
                <DropShadowEffect Color="#FF000000" BlurRadius="5" ShadowDepth="1" Opacity="0.12"/>
              </Border.Effect>
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="b" Property="Background" Value="#FFEEF2F8"/>
                <Setter TargetName="b" Property="BorderBrush" Value="{StaticResource Accent}"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="b" Property="Background" Value="#FFE3E9F2"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="b" Property="Opacity" Value="0.5"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- Danger button -->
    <Style x:Key="BtnDanger" TargetType="Button" BasedOn="{StaticResource BtnPrimary}">
      <Setter Property="Background" Value="{StaticResource Danger}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="b" Background="{TemplateBinding Background}" CornerRadius="6"
                    Padding="{TemplateBinding Padding}" SnapsToDevicePixels="True">
              <Border.Effect>
                <DropShadowEffect Color="#FFDC2626" BlurRadius="8" ShadowDepth="1" Opacity="0.30"/>
              </Border.Effect>
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="b" Property="Background" Value="{StaticResource DangerHover}"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="b" Property="Opacity" Value="0.5"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- TextBox -->
    <Style TargetType="TextBox">
      <Setter Property="Background" Value="{StaticResource Card}"/>
      <Setter Property="Foreground" Value="{StaticResource Text}"/>
      <Setter Property="CaretBrush" Value="{StaticResource Text}"/>
      <Setter Property="BorderBrush" Value="{StaticResource BorderStrong}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="8,7"/>
      <Setter Property="VerticalContentAlignment" Value="Center"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="TextBox">
            <Border x:Name="bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}"
                    BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="6">
              <ScrollViewer x:Name="PART_ContentHost" Margin="{TemplateBinding Padding}"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsKeyboardFocused" Value="True">
                <Setter TargetName="bd" Property="BorderBrush" Value="{StaticResource Accent}"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style TargetType="Label">
      <Setter Property="Foreground" Value="{StaticResource Muted}"/>
      <Setter Property="Padding" Value="0,0,0,3"/>
    </Style>
    <Style TargetType="TextBlock"><Setter Property="Foreground" Value="{StaticResource Text}"/></Style>
    <Style TargetType="CheckBox">
      <Setter Property="Foreground" Value="{StaticResource Text}"/>
      <Setter Property="VerticalContentAlignment" Value="Center"/>
    </Style>

    <!-- DataGrid (light) -->
    <Style TargetType="DataGrid">
      <Setter Property="Background" Value="{StaticResource Card}"/>
      <Setter Property="Foreground" Value="{StaticResource Text}"/>
      <Setter Property="BorderBrush" Value="{StaticResource Border}"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="RowBackground" Value="{StaticResource Card}"/>
      <Setter Property="AlternatingRowBackground" Value="#FFFAFBFC"/>
      <Setter Property="GridLinesVisibility" Value="Horizontal"/>
      <Setter Property="HorizontalGridLinesBrush" Value="#FFEDEFF2"/>
      <Setter Property="HeadersVisibility" Value="Column"/>
      <Setter Property="RowHeaderWidth" Value="0"/>
      <Setter Property="AutoGenerateColumns" Value="False"/>
      <Setter Property="CanUserAddRows" Value="False"/>
      <Setter Property="CanUserDeleteRows" Value="False"/>
      <Setter Property="SelectionMode" Value="Extended"/>
      <Setter Property="SelectionUnit" Value="FullRow"/>
      <Setter Property="RowHeight" Value="30"/>
    </Style>
    <Style TargetType="DataGridColumnHeader">
      <Setter Property="Background" Value="{StaticResource CardAlt}"/>
      <Setter Property="Foreground" Value="{StaticResource Muted}"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Padding" Value="10,9"/>
      <Setter Property="BorderBrush" Value="{StaticResource Border}"/>
      <Setter Property="BorderThickness" Value="0,0,0,1"/>
      <Setter Property="HorizontalContentAlignment" Value="Left"/>
    </Style>
    <Style TargetType="DataGridCell">
      <Setter Property="Foreground" Value="{StaticResource Text}"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Padding" Value="10,0"/>
      <Style.Triggers>
        <Trigger Property="IsSelected" Value="True">
          <Setter Property="Background" Value="#FFDCE8FF"/>
          <Setter Property="Foreground" Value="{StaticResource Text}"/>
        </Trigger>
      </Style.Triggers>
    </Style>
    <Style TargetType="DataGridRow">
      <Setter Property="Background" Value="Transparent"/>
      <Style.Triggers>
        <DataTrigger Binding="{Binding Protected}" Value="True">
          <Setter Property="Foreground" Value="{StaticResource Muted}"/>
        </DataTrigger>
        <DataTrigger Binding="{Binding Loaded}" Value="True">
          <Setter Property="Foreground" Value="{StaticResource Warn}"/>
        </DataTrigger>
      </Style.Triggers>
    </Style>
  </Window.Resources>

  <Grid>
    <Grid.RowDefinitions>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <Grid.ColumnDefinitions>
      <ColumnDefinition Width="320"/>
      <ColumnDefinition Width="*"/>
      <ColumnDefinition Width="280"/>
    </Grid.ColumnDefinitions>

    <!-- ============================ SIDEBAR ============================ -->
    <Border Grid.Row="0" Grid.Column="0" Background="{StaticResource Card}"
            BorderBrush="{StaticResource Border}" BorderThickness="0,0,1,0">
      <DockPanel Margin="18,18,18,18">

        <!-- Title -->
        <StackPanel DockPanel.Dock="Top">
          <TextBlock Text="Rolf" FontSize="24" FontWeight="Bold"/>
          <TextBlock Text="Profile cleanup tool" Foreground="{StaticResource Muted}" Margin="0,1,0,0"/>
          <TextBlock x:Name="AdminBadge" Text="" Foreground="{StaticResource Warn}" FontSize="11"
                     Margin="0,6,0,0" TextWrapping="Wrap"/>
        </StackPanel>

        <!-- Statistics pinned to bottom -->
        <Border DockPanel.Dock="Bottom" Background="{StaticResource CardAlt}" CornerRadius="8"
                BorderBrush="{StaticResource Border}" BorderThickness="1" Padding="14" Margin="0,14,0,0">
          <StackPanel>
            <TextBlock Text="Statistics" FontWeight="Bold" Margin="0,0,0,8"/>
            <Grid>
              <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
              <Grid.RowDefinitions>
                <RowDefinition/><RowDefinition/><RowDefinition/><RowDefinition/>
                <RowDefinition/><RowDefinition/><RowDefinition/>
              </Grid.RowDefinitions>
              <TextBlock Grid.Row="0" Grid.Column="0" Text="Computer"      Foreground="{StaticResource Muted}"/>
              <TextBlock Grid.Row="0" Grid.Column="1" x:Name="StatComputer" Text="-" FontWeight="SemiBold"/>
              <TextBlock Grid.Row="1" Grid.Column="0" Text="Profiles found" Foreground="{StaticResource Muted}"/>
              <TextBlock Grid.Row="1" Grid.Column="1" x:Name="StatTotal"    Text="0" FontWeight="SemiBold"/>
              <TextBlock Grid.Row="2" Grid.Column="0" Text="Inactive"       Foreground="{StaticResource Muted}"/>
              <TextBlock Grid.Row="2" Grid.Column="1" x:Name="StatInactive" Text="0" FontWeight="SemiBold"/>
              <TextBlock Grid.Row="3" Grid.Column="0" Text="In use"         Foreground="{StaticResource Muted}"/>
              <TextBlock Grid.Row="3" Grid.Column="1" x:Name="StatLoaded"   Text="0" FontWeight="SemiBold"/>
              <TextBlock Grid.Row="4" Grid.Column="0" Text="Protected"      Foreground="{StaticResource Muted}"/>
              <TextBlock Grid.Row="4" Grid.Column="1" x:Name="StatProtected" Text="0" FontWeight="SemiBold"/>
              <TextBlock Grid.Row="5" Grid.Column="0" Text="Selected"       Foreground="{StaticResource Muted}"/>
              <TextBlock Grid.Row="5" Grid.Column="1" x:Name="StatSelected" Text="0" FontWeight="SemiBold"/>
              <TextBlock Grid.Row="6" Grid.Column="0" Text="Selected size"  Foreground="{StaticResource Muted}"/>
              <TextBlock Grid.Row="6" Grid.Column="1" x:Name="StatSize"     Text="-" FontWeight="SemiBold"/>
            </Grid>
            <Separator Margin="0,8" Background="{StaticResource Border}"/>
            <TextBlock x:Name="StatElapsed" Text="Elapsed: -" Foreground="{StaticResource Muted}" FontSize="11"/>
            <TextBlock x:Name="StatLog" Text="" Foreground="{StaticResource Muted}" FontSize="11"
                       TextTrimming="CharacterEllipsis" Margin="0,2,0,0"/>
          </StackPanel>
        </Border>

        <!-- Scrollable controls -->
        <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
          <StackPanel Margin="0,4,4,0">

            <TextBlock Text="TARGET" Style="{StaticResource Section}"/>
            <Label Content="Computer"/>
            <TextBox x:Name="TxtComputer"/>
            <Grid Margin="0,8,0,0">
              <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="8"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
              <Button Grid.Column="0" x:Name="BtnLocal"   Content="Use local"     Style="{StaticResource BtnGhost}"/>
              <Button Grid.Column="2" x:Name="BtnConnect" Content="Scan profiles" Style="{StaticResource BtnPrimary}"/>
            </Grid>

            <TextBlock Text="FILTER" Style="{StaticResource Section}"/>
            <Label Content="Inactive more than (days)"/>
            <TextBox x:Name="TxtDays" Text="180" MaxLength="6"/>
            <Label Content="Search filter (user / path / SID)" Margin="0,8,0,0"/>
            <TextBox x:Name="TxtFilter" ToolTip="Type to filter the list by user name, profile path or SID"/>
            <CheckBox x:Name="ChkOnlyInactive" Content="Show only inactive profiles" Margin="0,10,0,0"/>

            <TextBlock Text="SELECT" Style="{StaticResource Section}"/>
            <Grid>
              <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="8"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
              <Button Grid.Column="0" x:Name="BtnSelectInactive" Content="Inactive" Style="{StaticResource BtnGhost}"/>
              <Button Grid.Column="2" x:Name="BtnSelectAll"      Content="All"      Style="{StaticResource BtnGhost}"/>
            </Grid>
            <Button x:Name="BtnClear" Content="Clear list" Style="{StaticResource BtnGhost}" Margin="0,8,0,0"/>
          </StackPanel>
        </ScrollViewer>
      </DockPanel>
    </Border>

    <!-- ============================ RESULTS ============================ -->
    <Grid Grid.Row="0" Grid.Column="1" Margin="18">
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
      </Grid.RowDefinitions>

      <DockPanel Grid.Row="0" Margin="0,0,0,12">
        <TextBlock Text="Profiles" FontSize="20" FontWeight="Bold" DockPanel.Dock="Left"/>
        <TextBlock x:Name="ResultCount" Text="0 profile(s)" Foreground="{StaticResource Muted}"
                   HorizontalAlignment="Right" VerticalAlignment="Bottom"/>
      </DockPanel>

      <Border Grid.Row="1" Background="{StaticResource Card}" CornerRadius="10"
              BorderBrush="{StaticResource Border}" BorderThickness="1" ClipToBounds="True">
        <DataGrid x:Name="Grid">
          <DataGrid.Columns>
            <DataGridCheckBoxColumn Header="" Width="40"
                Binding="{Binding IsSelected, Mode=TwoWay, UpdateSourceTrigger=PropertyChanged}"/>
            <DataGridTextColumn Header="User"      Width="*"   Binding="{Binding UserName}"   IsReadOnly="True"/>
            <DataGridTextColumn Header="Path"      Width="2*"  Binding="{Binding LocalPath}"  IsReadOnly="True"/>
            <DataGridTextColumn Header="Last use"  Width="110" Binding="{Binding LastUseTime}" IsReadOnly="True"/>
            <DataGridTextColumn Header="Days idle" Width="85"  Binding="{Binding InactiveDays}" IsReadOnly="True"/>
            <DataGridCheckBoxColumn Header="In use" Width="60" Binding="{Binding Loaded}"     IsReadOnly="True"/>
            <DataGridTextColumn Header="Size"      Width="90"  Binding="{Binding SizeText}"   IsReadOnly="True"/>
            <DataGridTextColumn Header="SID"       Width="2*"  Binding="{Binding Sid}"        IsReadOnly="True"/>
          </DataGrid.Columns>
        </DataGrid>
      </Border>
    </Grid>

    <!-- ============================ ACTIONS (right container) ============================ -->
    <Border Grid.Row="0" Grid.Column="2" Background="{StaticResource Card}"
            BorderBrush="{StaticResource Border}" BorderThickness="1,0,0,0">
      <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
        <StackPanel Margin="18,18,18,18">
          <TextBlock Text="Actions" FontSize="18" FontWeight="Bold"/>

          <TextBlock Text="DATA" Style="{StaticResource Section}"/>
          <Grid>
            <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="8"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
            <Button Grid.Column="0" x:Name="BtnSizes"  Content="Calc sizes" Style="{StaticResource BtnGhost}"/>
            <Button Grid.Column="2" x:Name="BtnExport" Content="Export..."  Style="{StaticResource BtnGhost}"/>
          </Grid>
          <Button x:Name="BtnOpen" Content="Open Users folder" Style="{StaticResource BtnGhost}" Margin="0,8,0,0"/>

          <TextBlock Text="MACHINE TOOLS" Style="{StaticResource Section}"/>
          <Button x:Name="BtnPing"   Content="Ping"             Style="{StaticResource BtnGhost}"/>
          <Button x:Name="BtnLogoff" Content="Log off all users" Style="{StaticResource BtnGhost}" Margin="0,8,0,0"/>
          <Button x:Name="BtnReboot" Content="Reboot machine"    Style="{StaticResource BtnGhost}" Margin="0,8,0,0"/>

          <TextBlock Text="DELETE" Style="{StaticResource Section}"/>
          <CheckBox x:Name="WhatIf" Content="What-if (simulate, no deletion)" IsChecked="True" Margin="0,0,0,8"/>
          <Button x:Name="BtnDelete" Content="Delete selected profiles" Style="{StaticResource BtnDanger}"/>
        </StackPanel>
      </ScrollViewer>
    </Border>

    <!-- ============================ STATUS BAR ============================ -->
    <Border Grid.Row="1" Grid.Column="0" Grid.ColumnSpan="3" Background="{StaticResource Card}"
            BorderBrush="{StaticResource Border}" BorderThickness="0,1,0,0" Padding="16,8">
      <DockPanel>
        <TextBlock x:Name="HostHint" Text="" Foreground="{StaticResource Muted}" DockPanel.Dock="Right"
                   VerticalAlignment="Center" Margin="12,0,0,0"/>
        <ProgressBar x:Name="Progress" Width="180" Height="6" Minimum="0" Maximum="100" Value="0"
                     DockPanel.Dock="Right" VerticalAlignment="Center"
                     Background="#FFE9ECF1" Foreground="{StaticResource Accent}" BorderThickness="0"/>
        <TextBlock x:Name="Status" Text="Ready" VerticalAlignment="Center"/>
      </DockPanel>
    </Border>
  </Grid>
</Window>
'@

#----------------------------------------------------------------------------------------------
#  Load XAML and wire up named controls
#----------------------------------------------------------------------------------------------
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
#  Helpers
#----------------------------------------------------------------------------------------------
function Set-Status   { param([string]$Text) $Status.Text = $Text; $Window.Dispatcher.Invoke([action]{}, 'Render') }
function Set-Progress { param([int]$Value) $Progress.Value = [math]::Min(100,[math]::Max(0,$Value)); $Window.Dispatcher.Invoke([action]{}, 'Render') }

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal $id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-TargetComputer {
    $c = $TxtComputer.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($c)) { $c = $env:COMPUTERNAME }
    $c
}

function Test-Local { param($Computer) $Computer -in @($env:COMPUTERNAME, 'localhost', '.', '127.0.0.1', '') }

function New-ProfileSession { param([string]$Computer)
    if (Test-Local $Computer) { return $null }
    try {
        New-CimSession -ComputerName $Computer -ErrorAction Stop
    } catch {
        $opt = New-CimSessionOption -Protocol Dcom
        New-CimSession -ComputerName $Computer -SessionOption $opt -ErrorAction Stop
    }
}

function ConvertTo-Size { param([double]$Bytes)
    if ($Bytes -le 0) { return '' }
    $u = 'B','KB','MB','GB','TB'; $i = 0; $v = $Bytes
    while ($v -ge 1024 -and $i -lt $u.Count-1) { $v /= 1024; $i++ }
    '{0:N1} {1}' -f $v, $u[$i]
}

function Test-Protected { param([string]$Path,[bool]$Special,[bool]$Loaded)
    if ($Special -or $Loaded) { return $true }
    if ([string]::IsNullOrWhiteSpace($Path)) { return $true }
    $leaf = Split-Path $Path -Leaf
    foreach ($n in $Script:ProtectedNames) { if ($leaf -ieq $n) { return $true } }
    if ($Path -match '\\Windows\\') { return $true }
    return $false
}

#----------------------------------------------------------------------------------------------
#  Scan
#----------------------------------------------------------------------------------------------
function Invoke-Scan {
    $computer = Get-TargetComputer
    $Script:Computer = $computer
    $days = 0; [void][int]::TryParse($TxtDays.Text, [ref]$days); if ($days -lt 0) { $days = 0 }
    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    Set-Status "Pinging $computer ..."; Set-Progress 10
    if (-not (Test-Local $computer)) {
        if (-not (Test-Connection -ComputerName $computer -Count 1 -Quiet -ErrorAction SilentlyContinue)) {
            Set-Progress 0; Set-Status "Offline: $computer is not reachable."; return
        }
    }

    Set-Status "Connecting to $computer ..."; Set-Progress 30
    $session = $null
    try { $session = New-ProfileSession $computer }
    catch { Set-Progress 0; Set-Status "Connect failed: $($_.Exception.Message)"; return }

    try {
        Set-Status "Querying user profiles ..."; Set-Progress 55
        $cimArgs = @{ ClassName = 'Win32_UserProfile'; ErrorAction = 'Stop' }
        if ($session) { $cimArgs.CimSession = $session }
        $raw = Get-CimInstance @cimArgs

        $Script:AllProfiles.Clear()
        $now = Get-Date
        foreach ($p in $raw) {
            $last = $null
            try { if ($p.LastUseTime) { $last = [datetime]$p.LastUseTime } } catch { }
            $idle = if ($last) { [int]($now - $last).TotalDays } else { 99999 }
            $path = [string]$p.LocalPath
            $prot = Test-Protected -Path $path -Special ([bool]$p.Special) -Loaded ([bool]$p.Loaded)
            $item = New-Object Rolf.ProfileItem
            $item.UserName     = if ($path) { Split-Path $path -Leaf } else { '<unknown>' }
            $item.Sid          = [string]$p.SID
            $item.LocalPath    = $path
            $item.LastUseTime  = if ($last) { $last.ToString('yyyy-MM-dd') } else { 'never' }
            $item.InactiveDays = $idle
            $item.Loaded       = [bool]$p.Loaded
            $item.Special      = [bool]$p.Special
            $item.Protected    = $prot
            $item.Inactive     = ($days -gt 0 -and $idle -ge $days)
            $item.SizeText     = ''
            $item.SizeBytes    = 0
            $Script:AllProfiles.Add($item)
        }
        Set-Progress 90
        Update-Grid
        $sw.Stop()
        $StatElapsed.Text = "Elapsed: {0:N2} s" -f $sw.Elapsed.TotalSeconds
        $StatLog.Text     = "Log: $(Split-Path $Script:ActionLog -Leaf)"
        Set-Progress 0
        Set-Status "Found $($Script:AllProfiles.Count) profiles on $computer."
    }
    catch { Set-Progress 0; Set-Status "Scan error: $($_.Exception.Message)" }
    finally { if ($session) { Remove-CimSession $session -ErrorAction SilentlyContinue } }
}

function Update-Grid {
    $filter = $TxtFilter.Text.Trim()
    $onlyInactive = [bool]$ChkOnlyInactive.IsChecked
    $Script:Profiles.Clear()
    foreach ($p in $Script:AllProfiles) {
        if ($onlyInactive -and -not $p.Inactive) { continue }
        if ($filter -and ($p.UserName -notmatch [regex]::Escape($filter)) `
                     -and ($p.LocalPath -notmatch [regex]::Escape($filter)) `
                     -and ($p.Sid -notmatch [regex]::Escape($filter))) { continue }
        $Script:Profiles.Add($p)
    }
    Update-Summary
}

function Update-Summary {
    $shown    = $Script:Profiles.Count
    $total    = $Script:AllProfiles.Count
    $inactive = @($Script:AllProfiles | Where-Object Inactive).Count
    $loaded   = @($Script:AllProfiles | Where-Object Loaded).Count
    $prot     = @($Script:AllProfiles | Where-Object Protected).Count
    $sel      = @($Script:Profiles    | Where-Object IsSelected).Count
    $bytes    = 0.0
    foreach ($p in $Script:Profiles) { if ($p.IsSelected) { $bytes += $p.SizeBytes } }

    $ResultCount.Text   = "$shown profile(s)"
    $StatComputer.Text  = $Script:Computer
    $StatTotal.Text     = "$total"
    $StatInactive.Text  = "$inactive"
    $StatLoaded.Text    = "$loaded"
    $StatProtected.Text = "$prot"
    $StatSelected.Text  = "$sel"
    $StatSize.Text      = if ($bytes -gt 0) { ConvertTo-Size $bytes } else { '-' }
}

#----------------------------------------------------------------------------------------------
#  Sizes
#----------------------------------------------------------------------------------------------
function Get-Sizes {
    if ($Script:Profiles.Count -eq 0) { return }
    $local = Test-Local $Script:Computer
    $i = 0; $total = $Script:Profiles.Count
    foreach ($p in $Script:Profiles) {
        $i++; Set-Progress ([int](100*$i/$total)); Set-Status "Sizing $($p.UserName) ..."
        $path = if ($local) { $p.LocalPath } else { '\\{0}\{1}' -f $Script:Computer, ($p.LocalPath -replace '^([A-Za-z]):','$1$') }
        try {
            $measure = Get-ChildItem -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue |
                       Measure-Object Length -Sum
            $sum = 0
            if ($measure -and $measure.Sum) { $sum = $measure.Sum }
            $p.SizeBytes = [double]$sum
            $p.SizeText  = ConvertTo-Size $p.SizeBytes
        } catch { $p.SizeText = 'n/a' }
    }
    $Grid.Items.Refresh()
    Update-Summary
    Set-Progress 0; Set-Status "Sizes calculated."
}

#----------------------------------------------------------------------------------------------
#  Delete
#----------------------------------------------------------------------------------------------
function Remove-Selected {
    $targets = @($Script:Profiles | Where-Object { $_.IsSelected })
    if ($targets.Count -eq 0) { Set-Status "Nothing selected."; return }

    $blocked   = @($targets | Where-Object Protected)
    $deletable = @($targets | Where-Object { -not $_.Protected })

    if ($deletable.Count -eq 0) {
        [System.Windows.MessageBox]::Show(
            "All selected profiles are protected (system, in-use or well-known) and will not be removed.",
            $Script:AppName, 'OK', 'Warning') | Out-Null
        return
    }

    $dry  = [bool]$WhatIf.IsChecked
    $verb = if ($dry) { 'simulate removal of' } else { 'PERMANENTLY DELETE' }
    $msg  = "About to $verb $($deletable.Count) profile(s) on $($Script:Computer)."
    if ($blocked.Count) { $msg += "`n$($blocked.Count) protected profile(s) will be skipped." }
    $msg += "`n`nContinue?"
    $answer = [System.Windows.MessageBox]::Show($msg, $Script:AppName, 'YesNo',
                ($(if ($dry) { 'Question' } else { 'Warning' })))
    if ($answer -ne 'Yes') { Set-Status "Cancelled."; return }

    $session = $null
    try { $session = New-ProfileSession $Script:Computer }
    catch { Set-Status "Connect failed: $($_.Exception.Message)"; return }

    $i = 0; $ok = 0
    try {
        foreach ($p in $deletable) {
            $i++; Set-Progress ([int](100*$i/$deletable.Count)); Set-Status "Removing $($p.UserName) ..."
            try {
                if (-not $dry) {
                    $q = @{ ClassName = 'Win32_UserProfile'; Filter = "SID='$($p.Sid)'"; ErrorAction = 'Stop' }
                    if ($session) { $q.CimSession = $session }
                    Get-CimInstance @q | Remove-CimInstance -ErrorAction Stop
                }
                Write-ActionLog -Action 'RemoveProfile' -Target $Script:Computer -Sid $p.Sid -Path $p.LocalPath -Result $(if ($dry) {'DryRun-OK'} else {'Deleted'})
                $ok++
            } catch {
                Write-ActionLog -Action 'RemoveProfile' -Target $Script:Computer -Sid $p.Sid -Path $p.LocalPath -Result "ERROR: $($_.Exception.Message)"
            }
        }
    } finally { if ($session) { Remove-CimSession $session -ErrorAction SilentlyContinue } }

    Set-Progress 0
    $word = if ($dry) { 'simulated' } else { 'removed' }
    Set-Status "$ok of $($deletable.Count) profile(s) $word.  Log: $(Split-Path $Script:ActionLog -Leaf)"
    if (-not $dry) { Invoke-Scan } else { Update-Summary }
}

#----------------------------------------------------------------------------------------------
#  Tools / export
#----------------------------------------------------------------------------------------------
function Invoke-Ping {
    $c = Get-TargetComputer; Set-Status "Pinging $c ..."; Set-Progress 50
    $up = Test-Connection -ComputerName $c -Count 1 -Quiet -ErrorAction SilentlyContinue
    Set-Progress 0; Set-Status $(if ($up) { "$c is online." } else { "$c did not respond." })
}

function Invoke-LogoffAll {
    $c = Get-TargetComputer
    if ([System.Windows.MessageBox]::Show("Force log off ALL users on $c?", $Script:AppName, 'YesNo','Warning') -ne 'Yes') { return }
    try {
        $session = New-ProfileSession $c
        $os = if ($session) { Get-CimInstance Win32_OperatingSystem -CimSession $session } else { Get-CimInstance Win32_OperatingSystem }
        $os | Invoke-CimMethod -MethodName Win32Shutdown -Arguments @{ Flags = [uint32]4 } | Out-Null
        if ($session) { Remove-CimSession $session -ErrorAction SilentlyContinue }
        Write-ActionLog -Action 'LogoffAll' -Target $c -Sid '' -Path '' -Result 'Sent'
        Set-Status "Forced logoff sent to $c."
    } catch { Set-Status "Logoff failed: $($_.Exception.Message)" }
}

function Invoke-Reboot {
    $c = Get-TargetComputer
    if ([System.Windows.MessageBox]::Show("Reboot $c now?", $Script:AppName, 'YesNo','Warning') -ne 'Yes') { return }
    try {
        if (Test-Local $c) { Restart-Computer -Force } else { Restart-Computer -ComputerName $c -Force }
        Write-ActionLog -Action 'Reboot' -Target $c -Sid '' -Path '' -Result 'Sent'
        Set-Status "Reboot command sent to $c."
    } catch { Set-Status "Reboot failed: $($_.Exception.Message)" }
}

function Open-UsersFolder {
    $c = Get-TargetComputer
    $path = if (Test-Local $c) { "$env:SystemDrive\Users" } else { "\\$c\C$\Users" }
    try { Start-Process explorer.exe $path } catch { Set-Status "Could not open $path" }
}

function Export-List {
    if ($Script:Profiles.Count -eq 0) { Set-Status "Nothing to export."; return }
    $dlg = New-Object System.Windows.Forms.SaveFileDialog
    $dlg.Filter = 'JSON (*.json)|*.json|CSV (*.csv)|*.csv'
    $dlg.FileName = "Profiles-$($Script:Computer)-$Script:Stamp"
    if ($dlg.ShowDialog() -ne 'OK') { return }
    $data = $Script:Profiles | Select-Object UserName,Sid,LocalPath,LastUseTime,InactiveDays,Loaded,Special,Protected,SizeText,SizeBytes
    try {
        if ($dlg.FileName -match '\.json$') {
            $data | ConvertTo-Json -Depth 4 | Set-Content -Path $dlg.FileName -Encoding UTF8
        } else {
            $data | Export-Csv -Path $dlg.FileName -NoTypeInformation -Encoding UTF8
        }
        Set-Status "Exported to $($dlg.FileName)"
    } catch { Set-Status "Export failed: $($_.Exception.Message)" }
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
