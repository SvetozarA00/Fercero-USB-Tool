<# ::
@echo off
set BAT_DIR=%~dp0
powershell.exe -NoProfile -ExecutionPolicy Bypass -sta -WindowStyle Hidden -Command "& ([ScriptBlock]::Create((Get-Content -Raw -LiteralPath '%~f0')))"
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo [ERROR] The application encountered a problem during startup (Exit Code: %ERRORLEVEL%).
    pause
)
exit /b
#>
#Requires -Version 5.1

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

try {

# ==============================================================================
# 1. ARCHITECTURE AND MULTITHREADED ENGINE (BACKGROUND RUNSPACE)
# ==============================================================================
$script:MsgQueue = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()
$script:IsBusy   = $false
$script:PSInst   = $null
$script:RS       = $null
$script:Handle   = $null

$BackgroundScript = @'
function Write-Log([string]$msg, [string]$type="I") { $Queue.Enqueue("$type|$msg") }
function Set-Progress([int]$val) { $Queue.Enqueue("%|" + [math]::Max(0, [math]::Min(100, $val))) }

function Test-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Encyclopedic Knowledge Base of Device Manager Codes (Codes 1 - 54)
$CodeManagerDict = @{
    1  = @{ Symbol="CM_PROB_NOT_CONFIGURED"; Description="Device is not configured or drivers are not installed."; Suggestion="Install official drivers from the manufacturer's website." }
    3  = @{ Symbol="CM_PROB_OUT_OF_MEMORY"; Description="Insufficient RAM memory for the driver or the driver is corrupted."; Suggestion="Free up RAM memory or restart the computer." }
    9  = @{ Symbol="CM_PROB_INVALID_DATA"; Description="Windows cannot identify the hardware."; Suggestion="Check BIOS/UEFI settings or update firmware." }
    10 = @{ Symbol="CM_PROB_FAILED_START"; Description="Device cannot start (Hardware Timeout)."; Suggestion="Update driver, reconnect device, or check the cable." }
    12 = @{ Symbol="CM_PROB_OUT_OF_EARLY_RES"; Description="No free system resources available (IRQ/IO)."; Suggestion="Disable unnecessary devices in BIOS." }
    14 = @{ Symbol="CM_PROB_NEED_RESTART"; Description="Requires a computer restart."; Suggestion="Restart your Windows computer." }
    16 = @{ Symbol="CM_PROB_PARTIAL_LOG_CONF"; Description="Device resources are not fully identified."; Suggestion="Assign resources manually or update driver." }
    18 = @{ Symbol="CM_PROB_REINSTALL"; Description="Driver reinstallation required."; Suggestion="Remove device from Device Manager and scan for hardware changes." }
    19 = @{ Symbol="CM_PROB_REGISTRY_UNKNOWN"; Description="Data in Windows Registry is corrupted."; Suggestion="Remove Upper/LowerFilters or run system repair." }
    21 = @{ Symbol="CM_PROB_WILL_BE_REMOVED"; Description="Device is being removed from system."; Suggestion="Wait or restart the computer." }
    22 = @{ Symbol="CM_PROB_DISABLED"; Description="Device is disabled in Windows."; Suggestion="Enable device in Device Manager (Right Click -> Enable)." }
    24 = @{ Symbol="CM_PROB_DEVLOADER_NOT_READY"; Description="Incomplete driver installation or loose connection."; Suggestion="Check connection and reinstall driver." }
    28 = @{ Symbol="CM_PROB_FAILED_INSTALL"; Description="Driver not installed (Unknown device)."; Suggestion="Download driver via Windows Update or manufacturer website." }
    29 = @{ Symbol="CM_PROB_HARDWARE_DISABLED"; Description="Device is disabled in BIOS/UEFI."; Suggestion="Enable device in motherboard BIOS settings." }
    31 = @{ Symbol="CM_PROB_FAILED_ADD"; Description="Windows cannot load drivers for this hardware."; Suggestion="Update driver or remove incompatible software." }
    32 = @{ Symbol="CM_PROB_DISABLED_SERVICE"; Description="Driver service disabled in Registry."; Suggestion="Enable service in Windows Services or reinstall driver." }
    33 = @{ Symbol="CM_PROB_TRANSLATION_FAILED"; Description="Resource translation error by system."; Suggestion="Update motherboard BIOS/UEFI." }
    34 = @{ Symbol="CM_PROB_NO_SOFTCONFIG"; Description="Missing configured values for device."; Suggestion="Configure device manually per manufacturer instructions." }
    35 = @{ Symbol="CM_PROB_BIOS_TABLE"; Description="System BIOS does not contain device information."; Suggestion="Flash latest version of BIOS/UEFI firmware." }
    36 = @{ Symbol="CM_PROB_IRQ_TRANSLATION_FAILED"; Description="Interrupt (IRQ) translation failed."; Suggestion="Change PCI slot of device or refresh BIOS." }
    37 = @{ Symbol="CM_PROB_FAILED_DRIVER_ENTRY"; Description="Driver cannot initialize."; Suggestion="Reinstall official driver." }
    38 = @{ Symbol="CM_PROB_DRIVER_FAILED_PRIOR"; Description="Previous instance of driver remains in RAM."; Suggestion="Restart computer to clear memory." }
    39 = @{ Symbol="CM_PROB_DRIVER_FAILED_LOAD"; Description="Driver missing or corrupted on disk."; Suggestion="Reinstall driver in Device Manager." }
    40 = @{ Symbol="CM_PROB_DRIVER_SERVICE_KEY_INVALID"; Description="Invalid service key in Registry."; Suggestion="Update device driver." }
    41 = @{ Symbol="CM_PROB_LEGACY_SERVICE_ERROR"; Description="Driver loaded but device not found."; Suggestion="Check if device is physically connected." }
    42 = @{ Symbol="CM_PROB_DUPLICATE_DEVICE"; Description="Duplicate device operation detected in memory."; Suggestion="Restart computer or remove duplicate in Device Manager." }
    43 = @{ Symbol="CM_PROB_FAILED_POST_START"; Description="Windows stopped device (GPU crash, voltage drop, or USB crash)."; Suggestion="Clean drivers with DDU tool (for GPU), reinstall driver, and check power supply." }
    44 = @{ Symbol="CM_PROB_HALTED"; Description="Application or service stopped hardware operation."; Suggestion="Restart application or computer." }
    45 = @{ Symbol="CM_PROB_NOT_PRESENT"; Description="Device not physically connected to computer."; Suggestion="Check USB/SATA cable and reconnect device." }
    46 = @{ Symbol="CM_PROB_MOVED"; Description="Access denied due to shutdown preparation."; Suggestion="Wait for system reboot." }
    47 = @{ Symbol="CM_PROB_TOO_EARLY"; Description="Device prepared for 'Safe Removal'."; Suggestion="Unplug and re-plug USB device." }
    48 = @{ Symbol="CM_PROB_NO_VALID_LOG_CONF"; Description="Software blocked due to Windows incompatibility."; Suggestion="Download latest driver for your version of Windows." }
    49 = @{ Symbol="CM_PROB_INVALID_MAIN_INT"; Description="Windows Registry hive is too large."; Suggestion="Clean Registry or run system repair." }
    50 = @{ Symbol="CM_PROB_FIXED_RES_CONFLICT"; Description="Fixed device settings conflict."; Suggestion="Change settings or reinstall device." }
    51 = @{ Symbol="CM_PROB_SYSTEM_SHUTDOWN"; Description="Device pending reboot."; Suggestion="Restart computer." }
    52 = @{ Symbol="CM_PROB_UNSIGNED_DRIVER"; Description="Driver digital signature is invalid."; Suggestion="Install signed driver or disable Driver Signature Enforcement." }
    53 = @{ Symbol="CM_PROB_VETOED"; Description="Antivirus or security filter blocked driver."; Suggestion="Check antivirus settings or update driver." }
    54 = @{ Symbol="CM_PROB_RESET_FAILED"; Description="Device reset failed."; Suggestion="Restart computer or check physical connection." }
}

# Encyclopedic Knowledge Base of System Logs
$EventKB = @{
    "WHEA-Logger" = @{ Description="CPU/RAM/PCIe hardware error."; Why="Voltage drop, overheating, or clock instability."; Solution="Disable overclocking/XMP, update BIOS, and check cooling." }
    "Kernel-Power" = @{ Description="Sudden power loss (Event ID 41)."; Why="Power outage, overheating, or PSU failure."; Solution="Check power supply, extension cord, and CPU cooler." }
    "Hyper-V-Hypervisor" = @{ Description="Virtualization not started (ID 42)."; Why="SVM Mode or VT-x disabled in BIOS."; Solution="Enter BIOS and enable 'SVM Mode' or 'VT-x'." }
    "Kernel-Boot" = @{ Description="VBS security check (ID 124)."; Why="Requires active virtualization in BIOS."; Solution="Enable CPU Virtualization in BIOS settings." }
    "EventLog" = @{ Description="Unexpected shutdown log (ID 6008)."; Why="Sudden power interruption in previous session."; Solution="Check power stability and cooling." }
    "DistributedCOM" = @{ Description="DCOM service timeout (ID 10010/10016)."; Why="Brief timeout in background app response."; Solution="Message is 95% harmless and does not affect stability." }
    "BugCheck" = @{ Description="Blue Screen of Death (BSOD ID 1001)."; Why="Fatal driver error or RAM failure."; Solution="Check C:\Windows\Minidump and run a RAM test." }
    "Disk" = @{ Description="Disk I/O error (ID 7/11/15/51)."; Why="Bad sectors, cable issue, or NVMe/SATA controller fault."; Solution="Immediately back up data, run 'chkdsk C: /f /r', and check drive health." }
    "Ntfs" = @{ Description="File system structure corruption (ID 55/137)."; Why="Sudden power loss during disk write."; Solution="Run 'chkdsk C: /f' to repair partition." }
    "Display" = @{ Description="GPU driver crash and recovery (ID 4101)."; Why="Graphics overheating, unstable clock, or bad driver."; Solution="Clean drivers with DDU tool and install fresh driver." }
    "nvlddmkm" = @{ Description="NVIDIA GeForce driver crash."; Why="Loss of GPU response due to overheating or voltage."; Solution="Reinstall NVIDIA drivers (Clean Install)." }
    "amdkmdag" = @{ Description="AMD Radeon driver crash."; Why="Radeon GPU driver failure."; Solution="Reset Radeon Adrenalin settings and update driver." }
    "igfx" = @{ Description="Intel integrated graphics crash."; Why="Loss of integrated GPU response in CPU."; Solution="Update Intel HD/Iris driver." }
    "Service Control Manager" = @{ Description="Windows service crash (ID 7000/7001)."; Why="Issue with system service dependencies."; Solution="Run Option 5 (System Repair DISM/SFC)." }
    "Volmgr" = @{ Description="Failed to write crash dump (ID 161)."; Why="SSD power loss during system crash."; Solution="Check SSD connection and free space on drive C:." }
    "Kernel-General" = @{ Description="Registry write error (ID 5/6)."; Why="Interrupted write to System Hive during shutdown."; Solution="Run SFC /scannow repair." }
    "Kernel-PNP" = @{ Description="PnP device driver not loaded (ID 219)."; Why="Missing driver for attached hardware."; Solution="Install official driver in Device Manager." }
    "BitLocker-Driver" = @{ Description="BitLocker encryption issue."; Why="Changes in TPM chip or access disabled."; Solution="Save your BitLocker recovery key." }
    "WindowsUpdateClient" = @{ Description="Update error (ID 20/31)."; Why="Corrupted Windows Update cache."; Solution="Run Option 6 (Windows Update Repair)." }
    "SideBySide" = @{ Description="C++ library error (ID 33/35/59)."; Why="Missing Microsoft Visual C++ Redistributable."; Solution="Install Visual C++ All-in-One package." }
    "Application Error" = @{ Description="Critical program crash (.exe ID 1000)."; Why="Invalid memory address access."; Solution="Reinstall the specified program." }
    "Application Hang" = @{ Description="Application freezing (ID 1002)."; Why="Infinite loop or interrupted I/O response."; Solution="Check CPU load and disk health." }
    "Schannel" = @{ Description="TLS/SSL protocol error."; Why="Invalid network certificate or incorrect system time."; Solution="Set correct system time and date." }
    "Winlogon" = @{ Description="User logon error."; Why="Issue in user session."; Solution="Restart computer and run SFC repair." }
}

try {
    switch ($TaskName) {
        "HardverScan" {
            Set-Progress 5
            Write-Log "=== COMPREHENSIVE HARDWARE AND SYSTEM SCAN ===" "H"

            Set-Progress 20
            Write-Log "Reading OS, processor, and memory info..." "I"
            try {
                $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
                $cpu = Get-CimInstance Win32_Processor -ErrorAction Stop
                $regVer = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue
                $displayVer = if ($regVer.DisplayVersion) { $regVer.DisplayVersion } else { $regVer.ReleaseId }
                $buildNum   = $regVer.CurrentBuild
                $ubrNum     = $regVer.UBR
                
                $fullOSInfo = "$($os.Caption) ($($os.OSArchitecture)) | Version: $displayVer (Build $buildNum.$ubrNum)"
                $lastUpdate = Get-HotFix -ErrorAction SilentlyContinue | Sort-Object InstalledOn -Descending | Select-Object -First 1
                $updateStr  = if ($lastUpdate) { "$($lastUpdate.HotFixID) ($($lastUpdate.InstalledOn))" } else { "Not detected" }

                Write-Log "[OS] $fullOSInfo" "P"
                Write-Log "[LAST UPDATE] $updateStr" "P"
                Write-Log "[CPU] $($cpu.Name) | Cores: $($cpu.NumberOfCores) | Threads: $($cpu.NumberOfLogicalProcessors)" "P"
                Write-Log "[RAM] Total: $([math]::Round($os.TotalVisibleMemorySize/1MB,2)) GB | Free: $([math]::Round($os.FreePhysicalMemory/1MB,2)) GB" "P"
            } catch { Write-Log "[ERROR] Error reading OS data." "F" }

            Set-Progress 40
            Write-Log "Reading GPU and RAM slot details..." "I"
            try {
                Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | ForEach-Object {
                    $vramStr = if ($_.AdapterRAM -and $_.AdapterRAM -gt 0 -and $_.AdapterRAM -lt 4294967295) {
                        "$([math]::Round($_.AdapterRAM/1GB,2)) GB"
                    } elseif ($_.AdapterRAM -ge 4294967295) {
                        ">= 4 GB (VRAM)"
                    } else {
                        "Shared / Integrated (RAM)"
                    }
                    Write-Log "[GPU] Model: $($_.Name) | VRAM: $vramStr | Driver: $($_.DriverVersion)" "P"
                }
                Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue | ForEach-Object {
                    $capGB = if ($_.Capacity) { [math]::Round($_.Capacity/1GB, 2) } else { 0 }
                    Write-Log "[RAM SLOT] Slot: $($_.DeviceLocator) | Capacity: ${capGB} GB | Speed: $($_.Speed) MHz" "P"
                }
            } catch {}

            Set-Progress 60
            Write-Log "Checking S.M.A.R.T. disk health..." "I"
            try {
                $disks = Get-PhysicalDisk -ErrorAction SilentlyContinue
                if ($disks) {
                    foreach ($d in $disks) {
                        $type = if ($d.MediaType -and $d.MediaType -ne 'Unspecified') { $d.MediaType } else { "NVMe/SSD" }
                        if ($d.HealthStatus -eq 'Healthy') {
                            Write-Log "[DISK OK] $($d.FriendlyName) ($type) | Status: HEALTHY" "P"
                        } else {
                            Write-Log "[DISK CRITICAL] $($d.FriendlyName) ($type) | Status: $($d.HealthStatus)!" "F"
                            Write-Log "   -> URGENT SUGGESTION: Back up your data immediately and replace the disk." "D"
                        }
                    }
                } else {
                    Get-CimInstance Win32_DiskDrive -ErrorAction SilentlyContinue | ForEach-Object {
                        Write-Log "[DISK] Model: $($_.Model) | Status: $($_.Status)" "P"
                    }
                }
            } catch {}

            Set-Progress 80
            Write-Log "Analyzing Windows PnP devices and error codes..." "I"
            try {
                $pnpErrors = Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue | Where-Object { 
                    $_.ConfigManagerErrorCode -ne 0 -and $_.ConfigManagerErrorCode -ne $null -and $_.ConfigManagerErrorCode -ne 22
                }
                if ($pnpErrors) {
                    foreach ($re in $pnpErrors) {
                        $devName = if ($re.Name) { $re.Name } else { $re.DeviceId }
                        $errCode = $re.ConfigManagerErrorCode
                        Write-Log "[DEVICE FAULT] $devName (Windows Code $errCode)" "F"
                        if ($CodeManagerDict.ContainsKey($errCode)) {
                            $info = $CodeManagerDict[$errCode]
                            Write-Log "   -> DESCRIPTION: $($info.Description)" "D"
                            Write-Log "   -> SOLUTION: $($info.Suggestion)" "P"
                        } else {
                            Write-Log "   -> SOLUTION: Reinstall driver or check connection in Device Manager." "P"
                        }
                    }
                } else { Write-Log "[OK] All active hardware devices are functioning properly." "P" }
            } catch {}

            Set-Progress 95
            Write-Log "`n=== SYSTEM LOG ANALYSIS (PAST 7 DAYS) ===" "H"
            try {
                $events = Get-WinEvent -FilterHashtable @{LogName='System'; Level=1,2; StartTime=(Get-Date).AddDays(-7)} -MaxEvents 100 -ErrorAction SilentlyContinue | Select-Object -First 10
                if ($events) {
                    foreach ($e in $events) {
                        $evtTime = $e.TimeCreated.ToString('dd.MM.yyyy. HH:mm:ss')
                        $src     = $e.ProviderName
                        Write-Log "[INCIDENT] Time: $evtTime | Source: $src | Event ID: $($e.Id)" "E"
                        
                        $matched = $false
                        foreach ($kbKey in $EventKB.Keys) {
                            if ($src -match $kbKey) {
                                $matched = $true
                                $kb = $EventKB[$kbKey]
                                Write-Log "   -> PROBLEM: $($kb.Description)" "F"
                                Write-Log "   -> WHY: $($kb.Why)" "D"
                                Write-Log "   -> SOLUTION: $($kb.Solution)" "P"
                                break
                            }
                        }
                        if (-not $matched) {
                            $msgStr = try { $e.Message } catch { $null }
                            if (-not $msgStr) { $msgStr = "System event recorded by provider '$src'." }
                            $msgStr = ($msgStr -replace "[\r\n]+", " ").Trim()
                            if ($msgStr.Length -gt 110) { $msgStr = $msgStr.Substring(0, 110) + "..." }
                            Write-Log "   -> DESCRIPTION: $msgStr" "I"
                            Write-Log "   -> SOLUTION: Run Option 5 (System Repair) and update drivers." "D"
                        }
                    }
                } else { Write-Log "[OK] No critical crashes recorded in system log." "P" }
            } catch { Write-Log "[OK] No critical crashes detected in the observed period." "P" }

            Set-Progress 100
            Write-Log "=== HARDWARE SCAN AND ANALYSIS COMPLETED ===" "H"
        }

        "MreznaDijagnostika" {
            Set-Progress 10
            Write-Log "=== NETWORK DIAGNOSTICS AND PING TEST ===" "H"
            Set-Progress 30
            Write-Log "Scanning active network adapters and IP addresses..." "I"
            try {
                Get-CimInstance Win32_NetworkAdapterConfiguration -ErrorAction SilentlyContinue | Where-Object { $_.IPEnabled -eq $true } | ForEach-Object {
                    Write-Log "[ADAPTER] $($_.Description)" "P"
                    Write-Log "   -> IPv4 Address: $($_.IPAddress -join ', ')" "I"
                    Write-Log "   -> Subnet Mask: $($_.IPSubnet -join ', ')" "I"
                    Write-Log "   -> Gateway: $($_.DefaultIPGateway -join ', ')" "I"
                    Write-Log "   -> DNS Servers: $($_.DNSServerSearchOrder -join ', ')" "I"
                    Write-Log "   -> MAC Address: $($_.MACAddress)" "I"
                }
            } catch {}

            Set-Progress 60
            Write-Log "`nRunning Ping test to key servers..." "H"
            $pingTargets = @(
                @{ Name="Google Public DNS"; IP="8.8.8.8" },
                @{ Name="Cloudflare DNS"; IP="1.1.1.1" }
            )
            $pinger = New-Object System.Net.NetworkInformation.Ping
            foreach ($pt in $pingTargets) {
                try {
                    $res = $pinger.Send($pt.IP, 2000)
                    if ($res.Status -eq 'Success') {
                        Write-Log "[PING OK] $($pt.Name) ($($pt.IP)) | Response time: $($res.RoundtripTime) ms" "P"
                    } else {
                        Write-Log "[PING FAIL] $($pt.Name) ($($pt.IP)) | Status: $($res.Status)" "F"
                    }
                } catch { Write-Log "[PING ERROR] $($pt.Name) : $($_.Exception.Message)" "F" }
            }
            Set-Progress 100
            Write-Log "=== NETWORK DIAGNOSTICS COMPLETED ===" "H"
        }

        "BatteryReport" {
            Set-Progress 10
            Write-Log "=== LAPTOP BATTERY AND HEALTH TEST ===" "H"
            Set-Progress 30
            $batt = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue
            if (-not $batt) {
                Write-Log "[INFO] Computer is a Desktop PC (no built-in battery)." "I"
                Write-Log "[OK] Battery test skipped (Not applicable to Desktop)." "P"
            } else {
                Set-Progress 50
                foreach ($b in $batt) {
                    Write-Log "[BATTERY] Model: $($b.Name) | Charge: $($b.EstimatedChargeRemaining)%" "P"
                }
                try {
                    $fullCap = (Get-CimInstance -Namespace root\wmi -ClassName MSBatteryFullCapacity -ErrorAction SilentlyContinue | Select-Object -First 1).FullChargedCapacity
                    $designCap = (Get-CimInstance -Namespace root\wmi -ClassName MSBatteryStaticData -ErrorAction SilentlyContinue | Select-Object -First 1).DesignedCapacity
                    if ($designCap -and $designCap -gt 0) {
                        $health = [math]::Min(100, [math]::Round(($fullCap / $designCap) * 100, 1))
                        $wear   = [math]::Max(0, [math]::Round(100 - $health, 1))
                        Write-Log "[CAPACITY] Factory: ${designCap} mWh | Current Max: ${fullCap} mWh" "D"
                        if ($health -ge 80) {
                            Write-Log "[STATUS] Battery Health: ${health}% (Degradation: ${wear}%) - Good condition." "P"
                        } else {
                            Write-Log "[WARNING] Battery Health: ${health}% (Degradation: ${wear}%) - Battery is worn out." "F"
                        }
                    }
                } catch {}

                Set-Progress 75
                $desktopPath = [Environment]::GetFolderPath('Desktop')
                $battReportPath = Join-Path $desktopPath "battery-report.html"
                if (Test-Admin) {
                    $null = Start-Process "powercfg.exe" -ArgumentList "/batteryreport /output `"$battReportPath`"" -Wait -NoNewWindow
                    if (Test-Path $battReportPath) {
                        Write-Log "[OK] HTML report saved to Desktop: 'battery-report.html'." "P"
                    }
                } else { Write-Log "[NOTE] Generating HTML report requires Administrator privileges." "D" }
            }
            Set-Progress 100
            Write-Log "=== BATTERY TEST COMPLETED ===" "H"
        }

        "CiscenjeTemp" {
            Set-Progress 10
            Write-Log "=== TEMPORARY FILES CLEANUP (TEMP) ===" "H"
            $tempFolders = @("$env:TEMP", "C:\Windows\Temp")
            $cnt = 0; $bytes = 0
            foreach ($folder in $tempFolders) {
                if (Test-Path $folder) {
                    Get-ChildItem -Path $folder -File -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
                        try {
                            $fLen = $_.Length
                            Remove-Item -Path $_.FullName -Force -ErrorAction Stop
                            $bytes += $fLen
                            $cnt++
                        } catch {}
                    }
                }
            }
            Set-Progress 90
            $sizeMB = [math]::Round($bytes / 1MB, 2)
            Write-Log "[RESULT] Successfully cleaned $cnt files (${sizeMB} MB freed)." "P"
            Write-Log "[NOTE] Locked files of active applications were safely skipped." "D"
            Set-Progress 100
            Write-Log "=== TEMP FILES CLEANUP COMPLETED ===" "H"
        }

        "SistemskaPopravka" {
            if (-not (Test-Admin)) { Write-Log "[ERROR] Run Fercero USB Tool as Administrator!" "F"; return }
            Set-Progress 10
            Write-Log "1/4: Running DISM /CheckHealth..." "H"
            $null = Start-Process "DISM.exe" -ArgumentList "/Online /Cleanup-Image /CheckHealth" -Wait -NoNewWindow
            
            Set-Progress 35
            Write-Log "2/4: Running DISM /ScanHealth (May take 2-3 minutes)..." "H"
            $null = Start-Process "DISM.exe" -ArgumentList "/Online /Cleanup-Image /ScanHealth" -Wait -NoNewWindow
            
            Set-Progress 60
            Write-Log "3/4: Running DISM /RestoreHealth (Restoring system files)..." "H"
            $dism = Start-Process "DISM.exe" -ArgumentList "/Online /Cleanup-Image /RestoreHealth" -Wait -NoNewWindow -PassThru
            if ($dism.ExitCode -eq 0) { Write-Log "[OK] DISM restoration successful." "P" } else { Write-Log "[WARNING] DISM exit code: $($dism.ExitCode)" "E" }
            
            Set-Progress 85
            Write-Log "4/4: Running SFC /scannow (Scanning core system files)..." "H"
            $sfc = Start-Process "sfc.exe" -ArgumentList "/scannow" -Wait -NoNewWindow -PassThru
            if ($sfc.ExitCode -eq 0) { Write-Log "[OK] SFC scan completed with no errors found." "P" } else { Write-Log "[WARNING] SFC found and repaired corrupted files." "F" }
            
            $desktopPath = [Environment]::GetFolderPath('Desktop')
            $reportFile = Join-Path $desktopPath "sfcdetails.txt"
            $cbsLog = "$env:windir\Logs\CBS\CBS.log"
            if (Test-Path $cbsLog) {
                Select-String -Path $cbsLog -Pattern "\[SR\]" -ErrorAction SilentlyContinue | ForEach-Object { $_.Line } | Out-File $reportFile -Encoding utf8 -ErrorAction SilentlyContinue
                Write-Log "[OK] Detailed SFC report saved to Desktop: 'sfcdetails.txt'." "P"
            }
            Set-Progress 100
            Write-Log "=== SYSTEM REPAIR COMPLETED ===" "H"
        }

        "UpdatePopravka" {
            if (-not (Test-Admin)) { Write-Log "[ERROR] Run Fercero USB Tool as Administrator!" "F"; return }
            Set-Progress 15
            Write-Log "Activating TrustedInstaller service..." "H"
            Start-Service -Name "trustedinstaller" -ErrorAction SilentlyContinue

            Set-Progress 35
            Write-Log "Stopping Windows Update services..." "I"
            "bits","wuauserv","msiserver","cryptsvc","appidsvc" | ForEach-Object {
                Stop-Service -Name $_ -Force -ErrorAction SilentlyContinue
            }

            Set-Progress 60
            Write-Log "Renaming cache folders..." "I"
            $dateStr = Get-Date -Format 'yyyyMMdd_HHmmss'
            if (Test-Path "$env:SystemRoot\SoftwareDistribution") { Rename-Item "$env:SystemRoot\SoftwareDistribution" "SoftwareDistribution.$dateStr.bak" -ErrorAction SilentlyContinue }
            if (Test-Path "$env:SystemRoot\System32\catroot2") { Rename-Item "$env:SystemRoot\System32\catroot2" "catroot2.$dateStr.bak" -ErrorAction SilentlyContinue }

            Set-Progress 80
            Write-Log "Cleaning components and restarting services..." "I"
            Start-Process "DISM.exe" -ArgumentList "/Online /Cleanup-image /StartComponentCleanup" -Wait -NoNewWindow
            "bits","wuauserv","msiserver","cryptsvc","appidsvc" | ForEach-Object {
                Start-Service -Name $_ -ErrorAction SilentlyContinue
            }

            Set-Progress 100
            Write-Log "[OK] Windows Update system successfully reset." "P"
        }

        "MrezniReset" {
            if (-not (Test-Admin)) { Write-Log "[ERROR] Run Fercero USB Tool as Administrator!" "F"; return }
            Set-Progress 30
            Write-Log "Flushing DNS cache..." "H"
            Start-Process "ipconfig.exe" -ArgumentList "/flushdns" -Wait -NoNewWindow
            Set-Progress 60
            Write-Log "Resetting Winsock and TCP/IP protocols..." "H"
            Start-Process "netsh.exe" -ArgumentList "winsock reset" -Wait -NoNewWindow
            Start-Process "netsh.exe" -ArgumentList "int ip reset" -Wait -NoNewWindow
            Set-Progress 100
            Write-Log "[OK] Network protocols (TCP/IP and Winsock) successfully reset." "P"
        }

        "RestartBios" {
            if (-not (Test-Admin)) { Write-Log "[ERROR] Entering Advanced Startup requires Administrator privileges!" "F"; return }

            Write-Log "=== RESTART TO ADVANCED STARTUP MENU ===" "H"
            Write-Log "Sending system command to restart into Advanced Startup Options..." "I"
            Write-Log "   -> In the menu that opens, you can select: BIOS/UEFI Settings, Safe Mode, or Startup Repair." "P"
            
            $proc = Start-Process "shutdown.exe" -ArgumentList "/r /o /t 2" -Wait -NoNewWindow -PassThru
            if ($proc.ExitCode -ne 0) {
                Write-Log "[ERROR] Error sending restart command (Exit Code: $($proc.ExitCode))." "F"
            } else {
                Write-Log "[OK] Computer will restart into Advanced Startup menu in 2 seconds..." "P"
            }
            Set-Progress 100
        }
    }
} catch { Write-Log "[CRITICAL ERROR] Exception: $($_.Exception.Message)" "F" }
finally { Set-Progress 100 }
'@

# ==============================================================================
# 2. XAML (DARK MODE)
# ==============================================================================
$xamlString = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Fercero USB Tool v8.7 Final Edition" Height="820" Width="1220"
        WindowStartupLocation="CenterScreen" Background="#0B0E14" Foreground="#F1F5F9">
    <Window.Resources>
        <!-- Modern Slim ScrollBar -->
        <Style TargetType="ScrollBar">
            <Setter Property="Width" Value="3"/>
            <Setter Property="MinWidth" Value="3"/>
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ScrollBar">
                        <Grid Background="Transparent">
                            <Track x:Name="PART_Track" IsDirectionReversed="true">
                                <Track.Thumb>
                                    <Thumb>
                                        <Thumb.Template>
                                            <ControlTemplate TargetType="Thumb">
                                                <Border x:Name="b" Background="#334155" CornerRadius="3"/>
                                                <ControlTemplate.Triggers>
                                                    <Trigger Property="IsMouseOver" Value="True">
                                                        <Setter TargetName="b" Property="Background" Value="#38BDF8"/>
                                                    </Trigger>
                                                </ControlTemplate.Triggers>
                                            </ControlTemplate>
                                        </Thumb.Template>
                                    </Thumb>
                                </Track.Thumb>
                            </Track>
                        </Grid>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style TargetType="Button" x:Key="NavBtn">
            <Setter Property="Background" Value="#171C28"/>
            <Setter Property="Foreground" Value="#CBD5E1"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Margin" Value="0,0,0,8"/>
            <Setter Property="Height" Value="40"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="b" Background="{TemplateBinding Background}" CornerRadius="8" BorderThickness="1" BorderBrush="#232B3E">
                            <ContentPresenter HorizontalAlignment="Left" VerticalAlignment="Center" Margin="14,0,0,0"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="b" Property="Background" Value="#2563EB"/>
                                <Setter TargetName="b" Property="BorderBrush" Value="#3B82F6"/>
                                <Setter Property="Foreground" Value="#FFFFFF"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="b" Property="Background" Value="#10141D"/>
                                <Setter TargetName="b" Property="BorderBrush" Value="#171C28"/>
                                <Setter Property="Foreground" Value="#475569"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style TargetType="Button" x:Key="ToolBtn" BasedOn="{StaticResource NavBtn}">
            <Setter Property="Background" Value="#1E293B"/>
            <Setter Property="Foreground" Value="#38BDF8"/>
        </Style>
    </Window.Resources>
    
    <Grid Margin="16">
        <Grid.ColumnDefinitions>
            <ColumnDefinition Width="320"/>
            <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>
        <Grid.RowDefinitions>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <!-- Sidebar Panel -->
        <Border Grid.Column="0" Grid.Row="0" Background="#121622" CornerRadius="12" Padding="14" Margin="0,0,14,14" BorderBrush="#1E2536" BorderThickness="1">
            <DockPanel>
                <StackPanel DockPanel.Dock="Top" Margin="2,2,2,10">
                    <TextBlock Text="⚡ FERCERO USB TOOL" FontSize="18" FontWeight="Bold" Foreground="#38BDF8"/>
                    <TextBlock Text="USB Diagnostics v8.7" FontSize="11" Foreground="#64748B" Margin="0,2,0,0"/>
                </StackPanel>
                <ScrollViewer VerticalScrollBarVisibility="Auto">
                    <StackPanel x:Name="BtnStack"/>
                </ScrollViewer>
            </DockPanel>
        </Border>

        <!-- Console Log Panel -->
        <Border Grid.Column="1" Grid.Row="0" Background="#080A0F" CornerRadius="12" Padding="16" Margin="0,0,0,14" BorderBrush="#1E2536" BorderThickness="1">
            <Grid>
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                </Grid.RowDefinitions>
                <DockPanel Grid.Row="0" Margin="0,0,0,12">
                    <TextBlock Text="DIAGNOSTIC CONSOLE AND REPORT" FontSize="12" FontWeight="Bold" Foreground="#94A3B8" VerticalAlignment="Center"/>
                </DockPanel>
                <RichTextBox x:Name="LogBox" Grid.Row="1" Background="Transparent" Foreground="#F8FAFC" FontFamily="Consolas" FontSize="12.5" BorderThickness="0" IsReadOnly="True" VerticalScrollBarVisibility="Auto">
                    <FlowDocument PagePadding="0"/>
                </RichTextBox>
            </Grid>
        </Border>

        <!-- Bottom Status Bar -->
        <Border Grid.Column="0" Grid.ColumnSpan="2" Grid.Row="1" Background="#121622" CornerRadius="10" Padding="14,10" BorderBrush="#1E2536" BorderThickness="1">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="260"/>
                    <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>
                <TextBlock x:Name="StatusLbl" Text="Status: Ready." FontWeight="SemiBold" Foreground="#38BDF8" VerticalAlignment="Center"/>
                <ProgressBar x:Name="PBar" Grid.Column="1" Height="8" Background="#1A202C" Foreground="#38BDF8" BorderThickness="0" Minimum="0" Maximum="100" Value="0">
                    <ProgressBar.Template>
                        <ControlTemplate TargetType="ProgressBar">
                            <Grid x:Name="TemplateRoot">
                                <Border Background="{TemplateBinding Background}" CornerRadius="4"/>
                                <Track x:Name="PART_Track">
                                    <Track.DecreaseRepeatButton>
                                        <RepeatButton Command="{x:Static Slider.DecreaseLarge}">
                                            <RepeatButton.Template>
                                                <ControlTemplate>
                                                    <Border Background="{TemplateBinding Foreground}" CornerRadius="4"/>
                                                </ControlTemplate>
                                            </RepeatButton.Template>
                                        </RepeatButton>
                                    </Track.DecreaseRepeatButton>
                                </Track>
                            </Grid>
                        </ControlTemplate>
                    </ProgressBar.Template>
                </ProgressBar>
            </Grid>
        </Border>
    </Grid>
</Window>
"@

# ==============================================================================
# 3. CONTROLLER AND EVENT HANDLERS
# ==============================================================================
$reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xamlString))
$Window = [System.Windows.Markup.XamlReader]::Load($reader)

if ($env:BAT_DIR) {
    $iconPath = Join-Path $env:BAT_DIR "fercero.ico"
    if (Test-Path $iconPath) {
        try { $Window.Icon = [System.Windows.Media.Imaging.BitmapFrame]::Create([uri]$iconPath) } catch {}
    }
}

$LogBox    = $Window.FindName("LogBox")
$StatusLbl = $Window.FindName("StatusLbl")
$PBar      = $Window.FindName("PBar")
$BtnStack  = $Window.FindName("BtnStack")
$navStyle  = $Window.FindResource("NavBtn")
$toolStyle = $Window.FindResource("ToolBtn")

# BASIC DIAGNOSTIC FUNCTIONS
$btnDefs = @(
    @{ L="1. Hardware Scan & Logs"; K="HardverScan" },
    @{ L="2. Network Diagnostics & Ping"; K="MreznaDijagnostika" },
    @{ L="3. Battery Test (Laptop)"; K="BatteryReport" },
    @{ L="4. Junk Cleanup (Temp)"; K="CiscenjeTemp" },
    @{ L="5. System Repair (DISM/SFC)"; K="SistemskaPopravka" },
    @{ L="6. Windows Update Repair"; K="UpdatePopravka" },
    @{ L="7. Reset Network & DNS"; K="MrezniReset" },
    @{ L="8. Save Report (.html)"; K="SacuvajIzvestaj" },
    @{ L="9. Restart to Advanced Startup / BIOS"; K="RestartBios" }
)

foreach ($def in $btnDefs) {
    $b = [System.Windows.Controls.Button]::new()
    $b.Content = $def.L
    $b.Style = $navStyle
    $b.Tag = $def.K
    $b.Add_Click({ param($s,$e); Start-Task $s.Tag })
    $BtnStack.Children.Add($b) | Out-Null
}

# DYNAMIC SCANNING OF PORTABLE TOOLS FROM USB (\Tools\)
$usbToolsPath = if ($env:BAT_DIR) { Join-Path $env:BAT_DIR "Tools" } else { "Tools" }
$detectedExeFiles = @()

if (Test-Path $usbToolsPath) {
    $detectedExeFiles = Get-ChildItem -Path $usbToolsPath -Filter "*.exe" -Recurse -ErrorAction SilentlyContinue
}

# SECTION IN MENU FOR PORTABLE TOOLS
$headerTxt = [System.Windows.Controls.TextBlock]::new()
$headerTxt.Text = "🧰 PORTABLE TOOLS (USB)"
$headerTxt.FontSize = 11
$headerTxt.FontWeight = [System.Windows.FontWeights]::Bold
$headerTxt.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#94A3B8")
$headerTxt.Margin = [System.Windows.Thickness]::new(4, 12, 0, 8)
$BtnStack.Children.Add($headerTxt) | Out-Null

if ($detectedExeFiles.Count -gt 0) {
    foreach ($exe in $detectedExeFiles) {
        $btn = [System.Windows.Controls.Button]::new()
        $cleanName = $exe.BaseName -replace "Portable|x64|x86|_", " "
        $btn.Content = "▶ " + $cleanName.Trim()
        $btn.Style = $toolStyle
        $btn.Tag = $exe.FullName
        $btn.Add_Click({
            param($s, $e)
            $exePath = $s.Tag
            try {
                Append-Log "`n[LAUNCH] Launching portable tool: $($s.Content)..." "#38BDF8"
                Start-Process -FilePath $exePath -Verb RunAs -ErrorAction Stop
                Append-Log "[OK] Tool successfully launched from: $exePath" "#4ADE80"
            } catch {
                Append-Log "[ERROR] Failed to launch tool: $($_.Exception.Message)" "#F87171"
            }
        })
        $BtnStack.Children.Add($btn) | Out-Null
    }
} else {
    $noToolsTxt = [System.Windows.Controls.TextBlock]::new()
    $noToolsTxt.Text = "No .exe files found in \Tools\ folder."
    $noToolsTxt.FontSize = 11
    $noToolsTxt.FontStyle = [System.Windows.FontStyles]::Italic
    $noToolsTxt.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#475569")
    $noToolsTxt.Margin = [System.Windows.Thickness]::new(4, 0, 0, 8)
    $BtnStack.Children.Add($noToolsTxt) | Out-Null
}

function Append-Log([string]$text, [string]$colorHex="#F8FAFC") {
    $p = [System.Windows.Documents.Paragraph]::new()
    $p.Margin = [System.Windows.Thickness]::new(0, 0, 0, 3)
    $run = [System.Windows.Documents.Run]::new($text)
    $run.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($colorHex)
    $p.Inlines.Add($run) | Out-Null
    $LogBox.Document.Blocks.Add($p) | Out-Null
    $LogBox.ScrollToEnd()
}

function Start-Task([string]$TaskName) {
    if ($script:IsBusy) { return }

    if ($TaskName -eq "SacuvajIzvestaj") {
        $desktopPath = [Environment]::GetFolderPath('Desktop')
        $ts = Get-Date -Format 'yyyyMMdd_HHmmss'
        $dateFormatted = Get-Date -Format 'dd.MM.yyyy. HH:mm:ss'
        $fileName = "FerceroUSB_Report_$ts.html"
        $filePathDesktop = Join-Path $desktopPath $fileName

        try {
            $range = [System.Windows.Documents.TextRange]::new($LogBox.Document.ContentStart, $LogBox.Document.ContentEnd)
            $rawText = $range.Text
            
            $lines = $rawText -split "[\r\n]+"
            $htmlLines = @()
            foreach ($line in $lines) {
                if ([string]::IsNullOrWhiteSpace($line)) { continue }
                $escapedLine = $line.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;')
                
                $color = "#E2E8F0"
                if ($line -match "^===") { $color = "#38BDF8"; $escapedLine = "<strong>$escapedLine</strong>" }
                elseif ($line -match "\[OK\]|\[DISK OK\]|\[PING OK\]|\[STATUS\]") { $color = "#4ADE80" }
                elseif ($line -match "\[ERROR\]|\[CRITICAL\]|\[INCIDENT\]|\[PING FAIL\]|\[DEVICE FAULT\]") { $color = "#F87171" }
                elseif ($line -match "\[WARNING\]|\[NOTE\]|\[CAPACITY\]") { $color = "#FACC15" }
                elseif ($line -match "\[OS\]|\[LAST UPDATE\]|\[CPU\]|\[RAM\]|\[GPU\]|\[DISK\]|\[BATTERY\]|\[ADAPTER\]") { $color = "#38BDF8" }

                $htmlLines += "<div class='log-line' style='color: $color;'>$escapedLine</div>"
            }
            $htmlBody = $htmlLines -join "`n"

            $htmlContent = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>Fercero USB Tool — Diagnostic Report</title>
    <style>
        body { background-color: #0B0E14; color: #F1F5F9; font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 0; padding: 24px; }
        .container { max-width: 1000px; margin: 0 auto; background-color: #121622; border: 1px solid #1E2536; border-radius: 12px; padding: 24px; box-shadow: 0 10px 25px rgba(0,0,0,0.5); }
        .header { border-bottom: 1px solid #1E2536; padding-bottom: 16px; margin-bottom: 20px; }
        .title { font-size: 22px; font-weight: bold; color: #38BDF8; }
        .meta { font-size: 13px; color: #94A3B8; line-height: 1.6; margin-bottom: 20px; background: #080A0F; padding: 12px 16px; border-radius: 8px; border: 1px solid #1E2536; }
        .console { background-color: #080A0F; border: 1px solid #1E2536; border-radius: 8px; padding: 16px; font-family: 'Consolas', 'Courier New', monospace; font-size: 13px; line-height: 1.5; overflow-x: auto; }
        .log-line { margin-bottom: 4px; white-space: pre-wrap; }
        .footer { margin-top: 24px; text-align: right; font-size: 12px; color: #64748B; border-top: 1px solid #1E2536; padding-top: 12px; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <div class="title">⚡ FERCERO USB TOOL — DIAGNOSTIC REPORT</div>
        </div>
        <div class="meta">
            <strong>Scan Date and Time:</strong> $dateFormatted<br>
            <strong>Computer:</strong> $env:COMPUTERNAME &nbsp;|&nbsp; <strong>Active User:</strong> $env:USERNAME<br>
            <strong>Platform:</strong> Fercero USB Tool v8.7 Final Edition
        </div>
        <div class="console">
            $htmlBody
        </div>
    </div>
</body>
</html>
"@
            $htmlContent | Out-File -FilePath $filePathDesktop -Encoding utf8 -ErrorAction Stop
            Append-Log "`n[OK] HTML REPORT SAVED TO DESKTOP: $filePathDesktop" "#4ADE80"
            
            if ($env:BAT_DIR -and (Test-Path $env:BAT_DIR)) {
                $usbFolder = Join-Path $env:BAT_DIR "Reports"
                if (-not (Test-Path $usbFolder)) { New-Item -ItemType Directory -Path $usbFolder -ErrorAction SilentlyContinue | Out-Null }
                $filePathUSB = Join-Path $usbFolder $fileName
                $htmlContent | Out-File -FilePath $filePathUSB -Encoding utf8 -ErrorAction SilentlyContinue
                Append-Log "[OK] HTML REPORT SAVED TO USB DRIVE: $filePathUSB" "#4ADE80"
            }

            [System.Windows.MessageBox]::Show("Complete HTML report saved to Desktop!`n`nPath: $filePathDesktop", "Report Saved", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
        } catch {
            [System.Windows.MessageBox]::Show("Error saving report: $($_.Exception.Message)", "Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
        }
        return
    }

    if ($TaskName -eq "RestartBios") {
        $confirm = [System.Windows.MessageBox]::Show("Are you sure you want to restart the computer into Advanced Startup (Advanced Startup Options)?", "Restart Confirmation", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning)
        if ($confirm -ne [System.Windows.MessageBoxResult]::Yes) { return }
    }

    $script:IsBusy = $true
    $PBar.Value = 0
    $LogBox.Document.Blocks.Clear()
    foreach ($child in $BtnStack.Children) { if ($child -is [System.Windows.Controls.Button]) { $child.IsEnabled = $false } }
    $StatusLbl.Text = "Status: Executing [$TaskName]..."

    $script:RS = [runspacefactory]::CreateRunspace()
    $script:RS.ApartmentState = "STA"
    $script:RS.ThreadOptions = "ReuseThread"
    $script:RS.Open()
    $script:RS.SessionStateProxy.SetVariable("Queue", $script:MsgQueue)
    $script:RS.SessionStateProxy.SetVariable("TaskName", $TaskName)

    $script:PSInst = [PowerShell]::Create()
    $script:PSInst.Runspace = $script:RS
    [void]$script:PSInst.AddScript($BackgroundScript)
    $script:Handle = $script:PSInst.BeginInvoke()
}

# TIMER FOR ACCURATE AND SAFE INTERFACE REFRESHING
$timer = [System.Windows.Threading.DispatcherTimer]::new()
$timer.Interval = [TimeSpan]::FromMilliseconds(60)
$timer.Add_Tick({
    $msg = ""
    while ($script:MsgQueue.TryDequeue([ref]$msg)) {
        if ($msg.StartsWith("%|")) {
            $rawVal = [int]$msg.Substring(2)
            $PBar.Value = [math]::Max(0, [math]::Min(100, $rawVal))
        } else {
            $parts = $msg.Split('|', 2)
            $hex = switch ($parts[0]) {
                'H' { "#38BDF8" } # Cyan
                'P' { "#4ADE80" } # Green
                'F' { "#F87171" } # Red
                'E' { "#F87171" } # Red
                'D' { "#FACC15" } # Gold
                default { "#E2E8F0" } # Slate
            }
            Append-Log $parts[1] $hex
        }
    }

    if ($script:IsBusy -and $null -ne $script:Handle -and $script:Handle.IsCompleted) {
        try { $script:PSInst.EndInvoke($script:Handle) } catch {}
        $script:PSInst.Dispose()
        $script:RS.Close()
        $script:IsBusy = $false
        $StatusLbl.Text = "Status: Ready."
        $PBar.Value = 100
        foreach ($child in $BtnStack.Children) { if ($child -is [System.Windows.Controls.Button]) { $child.IsEnabled = $true } }
    }
})
$timer.Start()

$Window.Add_Closing({
    $timer.Stop()
    if ($script:IsBusy -and $null -ne $script:PSInst) {
        try { $script:PSInst.Stop() } catch {}
        try { $script:RS.Close() } catch {}
    }
})

Append-Log "Welcome to Fercero USB Tool v8.7 (Final Edition)" "#38BDF8"
if ($detectedExeFiles.Count -gt 0) {
    Append-Log "[INFO] Detected $($detectedExeFiles.Count) portable tool(s) in '\Tools\' folder." "#4ADE80"
} else {
    Append-Log "[INFO] Place portable tools (.exe) into the '\Tools\' folder on the USB drive for automatic integration." "#FACC15"
}
Append-Log "--------------------------------------------------------------------------------------------------" "#334155"

[void]$Window.ShowDialog()

} catch {
    [System.Windows.Forms.MessageBox]::Show(
        "Critical error starting application:`n`n$($_.Exception.Message)`n`nLocation:`n$($_.ScriptStackTrace)",
        "Fercero USB Tool - Diagnostic Error",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    )
}
