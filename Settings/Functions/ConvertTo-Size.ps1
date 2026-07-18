function ConvertTo-Size {
    param([double]$Bytes)
    if ($Bytes -le 0) { return '' }
    $u = 'B','KB','MB','GB','TB'; $i = 0; $v = $Bytes
    while ($v -ge 1024 -and $i -lt $u.Count-1) { $v /= 1024; $i++ }
    '{0:N1} {1}' -f $v, $u[$i]
}
