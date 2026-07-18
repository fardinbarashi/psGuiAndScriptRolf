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
