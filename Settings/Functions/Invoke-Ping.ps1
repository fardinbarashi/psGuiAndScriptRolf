function Invoke-Ping {
    $c = Get-TargetComputer; Set-Status "Pinging $c ..."; Set-Progress 50
    $up = Test-Connection -ComputerName $c -Count 1 -Quiet -ErrorAction SilentlyContinue
    Set-Progress 0; Set-Status $(if ($up) { "$c is online." } else { "$c did not respond." })
}
