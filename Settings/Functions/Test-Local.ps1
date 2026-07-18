function Test-Local {
    param($Computer)
    $Computer -in @($env:COMPUTERNAME, 'localhost', '.', '127.0.0.1', '')
}
