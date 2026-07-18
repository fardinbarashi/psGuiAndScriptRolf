function Open-UsersFolder {
    $c = Get-TargetComputer
    $path = if (Test-Local $c) { "$env:SystemDrive\Users" } else { "\\$c\C$\Users" }
    try { Start-Process explorer.exe $path } catch { Set-Status "Could not open $path" }
}
