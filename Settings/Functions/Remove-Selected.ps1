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
