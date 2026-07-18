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
