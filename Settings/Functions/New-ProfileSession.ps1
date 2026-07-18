function New-ProfileSession {
    param([string]$Computer)
    if (Test-Local $Computer) { return $null }
    try {
        New-CimSession -ComputerName $Computer -ErrorAction Stop
    } catch {
        # WSMan failed - fall back to DCOM
        $opt = New-CimSessionOption -Protocol Dcom
        New-CimSession -ComputerName $Computer -SessionOption $opt -ErrorAction Stop
    }
}
