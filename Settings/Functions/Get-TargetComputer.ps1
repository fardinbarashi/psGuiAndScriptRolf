function Get-TargetComputer {
    $c = $TxtComputer.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($c)) { $c = $env:COMPUTERNAME }
    $c
}
