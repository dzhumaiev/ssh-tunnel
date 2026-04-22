Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# --- Persistence Logic ---
$SettingsPath = Join-Path $PSScriptRoot "tunnel_settings.json"

function Save-Settings {
    $Settings = @{
        Key   = $txtKey.Text
        Jump  = $txtJump.Text
        Ports = $txtPorts.Text
    }
    $Settings | ConvertTo-Json | Out-File $SettingsPath
    $lblStatus.Text = "Status: Settings Saved!"
    $lblStatus.ForeColor = "Blue"
}

function Load-Settings {
    if (Test-Path $SettingsPath) {
        $Settings = Get-Content $SettingsPath | ConvertFrom-Json
        $txtKey.Text   = $Settings.Key
        $txtJump.Text  = $Settings.Jump
        $txtPorts.Text = $Settings.Ports
    }
}

function Start-TunnelProcess {
    $lblStatus.Text = "Status: Connecting..."
    $lblStatus.ForeColor = "Orange"
    Get-Job -Name "SSHTunnel" -ErrorAction SilentlyContinue | Remove-Job -Force
    
    $parts = $txtJump.Text -split '@'
    if ($parts.Count -ne 2) { [System.Windows.Forms.MessageBox]::Show("Invalid Jump Host format."); return }
    
    $user = $parts[0]
    $hostPart = $parts[1] -split ':'
    $ip = $hostPart[0]
    $port = if($hostPart[1]) { $hostPart[1] } else { "22" }

    $Config = @{
        Key   = $txtKey.Text
        User  = $user
        Host  = $ip
        Port  = $port
        Lines = $txtPorts.Text -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -match ":" }
    }

    Start-Job -Name "SSHTunnel" -ArgumentList $Config -ScriptBlock {
        param($Cfg)
        $ArgList = @("-N", "-o", "StrictHostKeyChecking=no", "-i", $Cfg.Key, "-p", $Cfg.Port)
        foreach ($line in $Cfg.Lines) { $ArgList += "-L"; $ArgList += $line }
        $ArgList += "$($Cfg.User)@$($Cfg.Host)"
        ssh @ArgList
    }

    Start-Sleep -Seconds 2
    if ((Get-Job -Name "SSHTunnel").State -eq "Running") {
        $lblStatus.ForeColor = "Green"
        $lblStatus.Text = "Status: Connected!"
    } else {
        $lblStatus.Text = "Status: Failed"
        $lblStatus.ForeColor = "Red"
    }
}

# --- UI Setup ---
$Form = New-Object System.Windows.Forms.Form
$Form.Text = "SSH Tunnel Manager"
$Form.Size = New-Object System.Drawing.Size(450, 660)
$Form.StartPosition = "CenterScreen"
$Form.FormBorderStyle = "FixedDialog"

# --- Add UI Components BEFORE showing the form ---
function Add-Label($Text, $Top) {
    $Label = New-Object System.Windows.Forms.Label
    $Label.Text = $Text; $Label.Left = 20; $Label.Top = $Top; $Label.Width = 400
    $Form.Controls.Add($Label)
}

Add-Label "Private Key Path:" 10
$txtKey = New-Object System.Windows.Forms.TextBox
$txtKey.Left = 20; $txtKey.Top = 30; $txtKey.Width = 390
$Form.Controls.Add($txtKey)

Add-Label "Jump Host (User@Host:Port):" 70
$txtJump = New-Object System.Windows.Forms.TextBox
$txtJump.Left = 20; $txtJump.Top = 90; $txtJump.Width = 390
$Form.Controls.Add($txtJump)

Add-Label "Multi-Port Mappings (LocalPort:TargetIP:RemotePort):" 130
$txtPorts = New-Object System.Windows.Forms.TextBox
$txtPorts.Multiline = $true; $txtPorts.Height = 150; $txtPorts.Left = 20; $txtPorts.Top = 150; $txtPorts.Width = 390; $txtPorts.ScrollBars = "Vertical"
$Form.Controls.Add($txtPorts)

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = "Status: Idle"; $lblStatus.Left = 20; $lblStatus.Top = 320; $lblStatus.Width = 400; $lblStatus.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$Form.Controls.Add($lblStatus)

$btnSave = New-Object System.Windows.Forms.Button
$btnSave.Text = "💾 Save Config"; $btnSave.Top = 360; $btnSave.Left = 20; $btnSave.Width = 390; $btnSave.Height = 40
$Form.Controls.Add($btnSave)

$btnStart = New-Object System.Windows.Forms.Button
$btnStart.Text = "▶ Start"; $btnStart.Top = 410; $btnStart.Left = 20; $btnStart.Width = 125; $btnStart.Height = 45; $btnStart.BackColor = "LightGreen"
$Form.Controls.Add($btnStart)

$btnReconnect = New-Object System.Windows.Forms.Button
$btnReconnect.Text = "🔄 Reconnect"; $btnReconnect.Top = 410; $btnReconnect.Left = 152; $btnReconnect.Width = 125; $btnReconnect.Height = 45; $btnReconnect.BackColor = "LightCyan"
$Form.Controls.Add($btnReconnect)

$btnStop = New-Object System.Windows.Forms.Button
$btnStop.Text = "🛑 Stop"; $btnStop.Top = 410; $btnStop.Left = 285; $btnStop.Width = 125; $btnStop.Height = 45
$Form.Controls.Add($btnStop)

# --- Tray Icon & Events ---
$TrayIcon = New-Object System.Windows.Forms.NotifyIcon
$TrayIcon.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon((Get-Process -Id $PID).Path)
$TrayIcon.Text = "SSH Tunnel Manager"
$TrayIcon.Visible = $true

$ContextMenu = New-Object System.Windows.Forms.ContextMenu
$MenuShow = New-Object System.Windows.Forms.MenuItem("Show Manager")
$MenuExit = New-Object System.Windows.Forms.MenuItem("Exit")
$ContextMenu.MenuItems.AddRange(@($MenuShow, $MenuExit))
$TrayIcon.ContextMenu = $ContextMenu

$ShowForm = { 
    $Form.Visible = $true
    $Form.WindowState = "Normal"
    $Form.Activate()
}

$TrayIcon.Add_Click($ShowForm)
$MenuShow.Add_Click($ShowForm)
$MenuExit.Add_Click({ 
    $TrayIcon.Visible = $false
    Get-Job -Name "SSHTunnel" | Remove-Job -Force
    $Form.Close()
    [System.Windows.Forms.Application]::Exit()
})

$Form.Add_Closing({
    if ($TrayIcon.Visible) {
        $_.Cancel = $true
        $Form.Visible = $false
    }
})

# --- Event Handlers ---
$btnSave.Add_Click({ Save-Settings })
$btnStart.Add_Click({ Start-TunnelProcess })
$btnReconnect.Add_Click({ Start-TunnelProcess })
$btnStop.Add_Click({ Get-Job -Name "SSHTunnel" | Remove-Job -Force; $lblStatus.Text = "Status: Stopped"; $lblStatus.ForeColor = "Black" })

# --- Initialization & Loop ---
$txtKey.Text = "C:\PathToKey\.ssh\id_rsa"
$txtJump.Text = "username@URL_or_IP:PORT"
$txtPorts.Text = "WAN_IP:jump_server_ip:LAN_IP"
Load-Settings

# This keeps the UI active and visible immediately
$Form.Show()
[System.Windows.Forms.Application]::Run($Form)
