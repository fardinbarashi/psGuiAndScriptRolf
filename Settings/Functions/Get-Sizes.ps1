function Get-Sizes {
    if ($Script:Profiles.Count -eq 0) { return }
    $local = Test-Local $Script:Computer
    $i = 0; $total = $Script:Profiles.Count
    foreach ($p in $Script:Profiles) {
        $i++; Set-Progress ([int](100*$i/$total)); Set-Status "Sizing $($p.UserName) ..."
        $path = if ($local) { $p.LocalPath } else { '\\{0}\{1}' -f $Script:Computer, ($p.LocalPath -replace '^([A-Za-z]):','$1$') }
        try {
            $measure = Get-ChildItem -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue |
                       Measure-Object Length -Sum
            $sum = 0
            if ($measure -and $measure.Sum) { $sum = $measure.Sum }
            $p.SizeBytes = [double]$sum
            $p.SizeText  = ConvertTo-Size $p.SizeBytes
        } catch { $p.SizeText = 'n/a' }
    }
    $Grid.Items.Refresh()
    Update-Summary
    Set-Progress 0; Set-Status "Sizes calculated."
}
