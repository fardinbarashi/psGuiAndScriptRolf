function Invoke-Reboot {
    $c = Get-TargetComputer
    if ([System.Windows.MessageBox]::Show("Reboot $c now?", $Script:AppName, 'YesNo','Warning') -ne 'Yes') { return }
    try {
        if (Test-Local $c) { Restart-Computer -Force } else { Restart-Computer -ComputerName $c -Force }
        Write-ActionLog -Action 'Reboot' -Target $c -Sid '' -Path '' -Result 'Sent'
        Set-Status "Reboot command sent to $c."
    } catch { Set-Status "Reboot failed: $($_.Exception.Message)" }
}
