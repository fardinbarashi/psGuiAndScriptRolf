function Set-Status {
    param([string]$Text)
    $Status.Text = $Text
    $Window.Dispatcher.Invoke([action]{}, 'Render')
}
