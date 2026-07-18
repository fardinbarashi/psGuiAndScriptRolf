function Set-Progress {
    param([int]$Value)
    $Progress.Value = [math]::Min(100, [math]::Max(0, $Value))
    $Window.Dispatcher.Invoke([action]{}, 'Render')
}
