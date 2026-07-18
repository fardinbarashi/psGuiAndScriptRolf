function Write-ActionLog {
    param([string]$Action,[string]$Target,[string]$Sid,[string]$Path,[string]$Result)
    [pscustomobject]@{
        Time     = (Get-Date -Format 's')
        Action   = $Action
        Computer = $Target
        Sid      = $Sid
        Path     = $Path
        Result   = $Result
        DryRun   = [bool]$WhatIf.IsChecked
        RunAs    = $env:USERNAME
    } | Export-Csv -Path $Script:ActionLog -Append -NoTypeInformation -Encoding UTF8
}
