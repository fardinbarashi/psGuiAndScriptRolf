function Update-Grid {
    $filter = $TxtFilter.Text.Trim()
    $onlyInactive = [bool]$ChkOnlyInactive.IsChecked
    $Script:Profiles.Clear()
    foreach ($p in $Script:AllProfiles) {
        if ($onlyInactive -and -not $p.Inactive) { continue }
        if ($filter -and ($p.UserName -notmatch [regex]::Escape($filter)) `
                     -and ($p.LocalPath -notmatch [regex]::Escape($filter)) `
                     -and ($p.Sid -notmatch [regex]::Escape($filter))) { continue }
        $Script:Profiles.Add($p)
    }
    Update-Summary
}
