function Export-List {
    if ($Script:Profiles.Count -eq 0) { Set-Status "Nothing to export."; return }
    $dlg = New-Object System.Windows.Forms.SaveFileDialog
    $dlg.Filter = 'JSON (*.json)|*.json|CSV (*.csv)|*.csv'
    $dlg.FileName = "Profiles-$($Script:Computer)-$Script:Stamp"
    if ($dlg.ShowDialog() -ne 'OK') { return }
    $data = $Script:Profiles | Select-Object UserName,Sid,LocalPath,LastUseTime,InactiveDays,Loaded,Special,Protected,SizeText,SizeBytes
    try {
        if ($dlg.FileName -match '\.json$') {
            $data | ConvertTo-Json -Depth 4 | Set-Content -Path $dlg.FileName -Encoding UTF8
        } else {
            $data | Export-Csv -Path $dlg.FileName -NoTypeInformation -Encoding UTF8
        }
        Set-Status "Exported to $($dlg.FileName)"
    } catch { Set-Status "Export failed: $($_.Exception.Message)" }
}
