<#
    Windows Time Synchronization Tool (PowerShell edition)
    Queries a list of NTP servers and sets the local system clock.
    No Python required - uses .NET sockets and the built-in Set-Date cmdlet.
#>

# ---- Self-elevate if not already running as Administrator ----
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal(
    [Security.Principal.WindowsIdentity]::GetCurrent()
)
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Requesting administrator privileges..."
    Start-Process powershell.exe -ArgumentList @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$PSCommandPath`""
    ) -Verb RunAs
    exit
}

function Get-NtpTime {
    param([string]$Server)

    $ntpData = New-Object byte[] 48
    $ntpData[0] = 0x1B   # LI = 0, VN = 3, Mode = 3 (client)

    $socket = $null
    try {
        $ipAddresses = [System.Net.Dns]::GetHostAddresses($Server)
        $endpoint = New-Object System.Net.IPEndPoint($ipAddresses[0], 123)

        $socket = New-Object System.Net.Sockets.Socket(
            [System.Net.Sockets.AddressFamily]::InterNetwork,
            [System.Net.Sockets.SocketType]::Dgram,
            [System.Net.Sockets.ProtocolType]::Udp
        )
        $socket.ReceiveTimeout = 5000
        $socket.SendTimeout = 5000
        $socket.Connect($endpoint)

        $socket.Send($ntpData) | Out-Null
        $socket.Receive($ntpData) | Out-Null

        # Transmit timestamp lives at bytes 40-47 (big-endian: 32-bit seconds + 32-bit fraction)
        $seconds = ([uint32]$ntpData[40] -shl 24) -bor ([uint32]$ntpData[41] -shl 16) `
                 -bor ([uint32]$ntpData[42] -shl 8)  -bor ([uint32]$ntpData[43])
        $fraction = ([uint32]$ntpData[44] -shl 24) -bor ([uint32]$ntpData[45] -shl 16) `
                  -bor ([uint32]$ntpData[46] -shl 8)  -bor ([uint32]$ntpData[47])

        $millis = [math]::Round(($fraction / [math]::Pow(2, 32)) * 1000)

        # NTP epoch starts 1900-01-01 (UTC); .NET DateTime handles the leap years for us
        $ntpEpoch = Get-Date -Date "1900-01-01T00:00:00Z"
        return $ntpEpoch.AddSeconds($seconds).AddMilliseconds($millis)
    }
    catch {
        Write-Host "Error connecting to $Server`: $($_.Exception.Message)"
        return $null
    }
    finally {
        if ($socket) { $socket.Close() }
    }
}

Write-Host "Windows Time Synchronization Tool"
Write-Host "================================="

$servers = @("time.google.com", "time.windows.com", "time.nist.gov")
$ntpUtc = $null
$successfulServer = $null

foreach ($server in $servers) {
    Write-Host "Connecting to $server..."
    $ntpUtc = Get-NtpTime -Server $server
    if ($ntpUtc) {
        $successfulServer = $server
        Write-Host "Successfully connected to $server"
        break
    }
    Write-Host "Failed to connect to $server, trying next server...`n"
}

if (-not $ntpUtc) {
    Write-Host "Failed to connect to any NTP server. Please check your internet connection and try again later."
    exit 1
}

$currentTime = Get-Date
$newTimeLocal = $ntpUtc.ToLocalTime()
$diffSeconds = [math]::Abs(($newTimeLocal - $currentTime).TotalSeconds)

Write-Host ""
Write-Host "Current system time: $currentTime"
Write-Host "NTP server time:     $newTimeLocal (from $successfulServer)"
Write-Host "Time difference:     $diffSeconds seconds"

Write-Host ""
Write-Host "Updating system time..."

try {
    Set-Date -Date $newTimeLocal | Out-Null
    Write-Host "Time synchronization completed successfully."
}
catch {
    Write-Host "Time synchronization failed: $($_.Exception.Message)"
}

Write-Host ""
Read-Host "Press Enter to exit"
