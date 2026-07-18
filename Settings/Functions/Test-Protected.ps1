function Test-Protected {
    param([string]$Path,[bool]$Special,[bool]$Loaded)
    if ($Special -or $Loaded) { return $true }
    if ([string]::IsNullOrWhiteSpace($Path)) { return $true }
    $leaf = Split-Path $Path -Leaf
    foreach ($n in $Script:ProtectedNames) { if ($leaf -ieq $n) { return $true } }
    if ($Path -match '\\Windows\\') { return $true }
    return $false
}
