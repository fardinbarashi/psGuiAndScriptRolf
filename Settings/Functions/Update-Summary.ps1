function Update-Summary {
    $shown    = $Script:Profiles.Count
    $total    = $Script:AllProfiles.Count
    $inactive = @($Script:AllProfiles | Where-Object Inactive).Count
    $loaded   = @($Script:AllProfiles | Where-Object Loaded).Count
    $prot     = @($Script:AllProfiles | Where-Object Protected).Count
    $sel      = @($Script:Profiles    | Where-Object IsSelected).Count
    $bytes    = 0.0
    foreach ($p in $Script:Profiles) { if ($p.IsSelected) { $bytes += $p.SizeBytes } }

    $ResultCount.Text   = "$shown profile(s)"
    $StatComputer.Text  = $Script:Computer
    $StatTotal.Text     = "$total"
    $StatInactive.Text  = "$inactive"
    $StatLoaded.Text    = "$loaded"
    $StatProtected.Text = "$prot"
    $StatSelected.Text  = "$sel"
    $StatSize.Text      = if ($bytes -gt 0) { ConvertTo-Size $bytes } else { '-' }
}
