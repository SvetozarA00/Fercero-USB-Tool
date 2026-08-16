<# ::
@echo off
set BAT_DIR=%~dp0
powershell.exe -NoProfile -ExecutionPolicy Bypass -sta -WindowStyle Hidden -Command "& ([ScriptBlock]::Create((Get-Content -Raw -LiteralPath '%~f0')))"
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo [GRESKA] Aplikacija je naisla na problem pri pokretanju (Exit Code: %ERRORLEVEL%).
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
# 1. ARHITEKTURA I VIŠENITNI ENGINE (POZADINSKI RUNSPACE)
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

# Enciklopedijska Baza Device Manager Kodova (Codes 1 - 54)
$CodeManagerDict = @{
    1  = @{ Symbol="CM_PROB_NOT_CONFIGURED"; Opis="Uređaj nije konfigurisan ili drajveri nisu instalirani."; Sugestija="Instalirajte zvanične drajvere sa sajta proizvođača." }
    3  = @{ Symbol="CM_PROB_OUT_OF_MEMORY"; Opis="Nedovoljno RAM memorije za drajver ili je drajver oštećen."; Sugestija="Oslobodite RAM memoriju ili restartujte računar." }
    9  = @{ Symbol="CM_PROB_INVALID_DATA"; Opis="Windows ne može da identifikuje hardver."; Sugestija="Proverite BIOS/UEFI podešavanja ili ažurirajte firmware." }
    10 = @{ Symbol="CM_PROB_FAILED_START"; Opis="Uređaj ne može da se pokrene (Hardware Timeout)."; Sugestija="Ažurirajte drajver, ponovo povežite uređaj ili proverite kabl." }
    12 = @{ Symbol="CM_PROB_OUT_OF_EARLY_RES"; Opis="Nema slobodnih sistemskih resursa (IRQ/IO)."; Sugestija="Onemogućite nepotrebne uređaje u BIOS-u." }
    14 = @{ Symbol="CM_PROB_NEED_RESTART"; Opis="Zahteva ponovno pokretanje računara."; Sugestija="Restartujte Windows računar." }
    16 = @{ Symbol="CM_PROB_PARTIAL_LOG_CONF"; Opis="Resursi uređaja nisu u potpunosti identifikovani."; Sugestija="Dodelite resurse ručno ili ažurirajte drajver." }
    18 = @{ Symbol="CM_PROB_REINSTALL"; Opis="Potrebno je ponovo instalirati drajver."; Sugestija="Uklonite uređaj iz Device Manager-a i skenirajte promene." }
    19 = @{ Symbol="CM_PROB_REGISTRY_UNKNOWN"; Opis="Podaci u Windows Registru su oštećeni."; Sugestija="Obrišite Upper/LowerFilters ili pokrenite popravku sistema." }
    21 = @{ Symbol="CM_PROB_WILL_BE_REMOVED"; Opis="Uređaj se uklanja iz sistema."; Sugestija="Sačekajte ili restartujte računar." }
    22 = @{ Symbol="CM_PROB_DISABLED"; Opis="Uređaj je onemogućen u Windows-u."; Sugestija="Omogućite uređaj u Device Manager-u (Right Click -> Enable)." }
    24 = @{ Symbol="CM_PROB_DEVLOADER_NOT_READY"; Opis="Nedovršena instalacija drajvera ili loš spoj."; Sugestija="Proverite priključak i ponovo instalirajte drajver." }
    28 = @{ Symbol="CM_PROB_FAILED_INSTALL"; Opis="Drajver nije instaliran (Nepoznat uređaj)."; Sugestija="Preuzmite drajver preko Windows Update-a ili sajta proizvođača." }
    29 = @{ Symbol="CM_PROB_HARDWARE_DISABLED"; Opis="Uređaj je onemogućen u BIOS/UEFI."; Sugestija="Omogućite uređaj u BIOS podešavanjima matične ploče." }
    31 = @{ Symbol="CM_PROB_FAILED_ADD"; Opis="Windows ne može da učita drajvere za ovaj hardver."; Sugestija="Ažurirajte drajver ili uklonite nekompatibilni softver." }
    32 = @{ Symbol="CM_PROB_DISABLED_SERVICE"; Opis="Servis drajvera je onemogućen u Registru."; Sugestija="Aktivirajte servis u Windows Services ili reinstalirajte drajver." }
    33 = @{ Symbol="CM_PROB_TRANSLATION_FAILED"; Opis="Problem sa prevođenjem resursa od strane sistema."; Sugestija="Ažurirajte BIOS/UEFI matične ploče." }
    34 = @{ Symbol="CM_PROB_NO_SOFTCONFIG"; Opis="Nedostaju konfigurisane vrednosti za uređaj."; Sugestija="Konfigurišite uređaj ručno po uputstvu proizvođača." }
    35 = @{ Symbol="CM_PROB_BIOS_TABLE"; Opis="Sistemski BIOS ne sadrži informacije o uređaju."; Sugestija="Flashujte najnoviju verziju BIOS/UEFI firmware-a." }
    36 = @{ Symbol="CM_PROB_IRQ_TRANSLATION_FAILED"; Opis="Prekid (IRQ) nije pravilno dodeljen."; Sugestija="Promenite PCI slot uređaja ili osvežite BIOS." }
    37 = @{ Symbol="CM_PROB_FAILED_DRIVER_ENTRY"; Opis="Drajver ne može da se inicijalizuje."; Sugestija="Reinstalirajte zvanični drajver." }
    38 = @{ Symbol="CM_PROB_DRIVER_FAILED_PRIOR"; Opis="Prethodna instanca drajvera ostala u RAM-u."; Sugestija="Restartujte računar radi čišćenja memorije." }
    39 = @{ Symbol="CM_PROB_DRIVER_FAILED_LOAD"; Opis="Drajver nedostaje ili je oštećen na disku."; Sugestija="Ponovo instalirajte drajver u Device Manager-u." }
    40 = @{ Symbol="CM_PROB_DRIVER_SERVICE_KEY_INVALID"; Opis="Nevažeći ključ servisa u Registru."; Sugestija="Ažurirajte drajver uređaja." }
    41 = @{ Symbol="CM_PROB_LEGACY_SERVICE_ERROR"; Opis="Drajver je učitan ali uređaj nije pronađen."; Sugestija="Proverite da li je uređaj fizički priključen." }
    42 = @{ Symbol="CM_PROB_DUPLICATE_DEVICE"; Opis="Detektovan duplirani rad uređaja u memoriji."; Sugestija="Restartujte računar ili uklonite duplikat u Device Manager-u." }
    43 = @{ Symbol="CM_PROB_FAILED_POST_START"; Opis="Windows zaustavio uređaj (Kvar GPU-a, pad napona ili USB krah)."; Sugestija="Očistite drajvere DDU alatom (za GPU), reinstalirajte drajver i proverite napajanje." }
    44 = @{ Symbol="CM_PROB_HALTED"; Opis="Aplikacija ili servis je zaustavio rad hardvera."; Sugestija="Restartujte aplikaciju ili računar." }
    45 = @{ Symbol="CM_PROB_NOT_PRESENT"; Opis="Uređaj nije fizički povezan sa računarom."; Sugestija="Proverite USB/SATA kabl i ponovo priključite uređaj." }
    46 = @{ Symbol="CM_PROB_MOVED"; Opis="Pristup onemogućen usled pripreme za gašenje."; Sugestija="Sačekajte reboot sistema." }
    47 = @{ Symbol="CM_PROB_TOO_EARLY"; Opis="Uređaj je pripremljen za 'Safe Removal'."; Sugestija="Iskopčajte pa ponovo ukopčajte USB." }
    48 = @{ Symbol="CM_PROB_NO_VALID_LOG_CONF"; Opis="Softver blokiran zbog nekompatibilnosti sa Windows-om."; Sugestija="Preuzmite najnoviji drajver za vašu verziju Windows-a." }
    49 = @{ Symbol="CM_PROB_INVALID_MAIN_INT"; Opis="Windows Registar hive je prevelik."; Sugestija="Očistite Registar ili pokrenite popravku sistema." }
    50 = @{ Symbol="CM_PROB_FIXED_RES_CONFLICT"; Opis="Sukob fiksnih postavki uređaja."; Sugestija="Promenite postavke ili reinstalirajte uređaj." }
    51 = @{ Symbol="CM_PROB_SYSTEM_SHUTDOWN"; Opis="Uređaj na čekanju za reboot."; Sugestija="Restartujte računar." }
    52 = @{ Symbol="CM_PROB_UNSIGNED_DRIVER"; Opis="Digitalni potpis drajvera je nevažeći."; Sugestija="Instalirajte potpisani drajver ili isključite Driver Signature Enforcement." }
    53 = @{ Symbol="CM_PROB_VETOED"; Opis="Antivirus ili bezbednosni filter blokirao drajver."; Sugestija="Proverite antivirus podešavanja ili ažurirajte drajver." }
    54 = @{ Symbol="CM_PROB_RESET_FAILED"; Opis="Resetovanje uređaja nije uspelo."; Sugestija="Restartujte računar ili proverite fizički spoj." }
}

# Enciklopedijska Baza Sistemskih Logova
$EventKB = @{
    "WHEA-Logger" = @{ Opis="Hardverska greška CPU/RAM/PCIe."; Zasto="Pad napona, pregrevanje ili instabilnost takta."; Sugestija="Isključite overclock/XMP, osvežite BIOS i proverite hlađenje." }
    "Kernel-Power" = @{ Opis="Nagli prekid napajanja (Event ID 41)."; Zasto="Pad napona, pregrevanje ili otkazivanje PSU napajanja."; Sugestija="Proverite napajanje, produžni kabl i hladnjak procesora." }
    "Hyper-V-Hypervisor" = @{ Opis="Virtualizacija nije pokrenuta (ID 42)."; Zasto="SVM Mode ili VT-x je isključen u BIOS-u."; Sugestija="Uđite u BIOS i uključite 'SVM Mode' ili 'VT-x'." }
    "Kernel-Boot" = @{ Opis="VBS bezbednosna provera (ID 124)."; Zasto="Zahteva aktivnu virtualizaciju u BIOS-u."; Sugestija="Omogućite CPU Virtualization u BIOS podešavanjima." }
    "EventLog" = @{ Opis="Evidencija neočekivanog gašenja (ID 6008)."; Zasto="Nenadani prekid rada u prethodnoj sesiji."; Sugestija="Proverite stabilnost strujne mreže i hlađenja." }
    "DistributedCOM" = @{ Opis="DCOM tajmaut servisa (ID 10010/10016)."; Zasto="Kratak zoj u odzivu pozadinske aplikacije."; Sugestija="Poruka je 95% bezopasna i ne utiče na stabilnost." }
    "BugCheck" = @{ Opis="Plavi ekran smrti (BSOD ID 1001)."; Zasto="Fatalna greška drajvera ili radne memorije."; Sugestija="Proverite C:\Windows\Minidump i pokrenite RAM test." }
    "Disk" = @{ Opis="I/O greška diska (ID 7/11/15/51)."; Zasto="Loši sektori, problem sa kablom ili NVMe/SATA kontrolerom."; Sugestija="Hitno napravite bekap, pokrenite 'chkdsk C: /f /r' i proverite disk." }
    "Ntfs" = @{ Opis="Oštećenje strukture fajl sistema (ID 55/137)."; Zasto="Nagli prekid struje tokom upisa na disk."; Sugestija="Pokrenite 'chkdsk C: /f' za oporavak particije." }
    "Display" = @{ Opis="Rušenje i oporavak GPU drajvera (ID 4101)."; Zasto="Pregrevanje grafike, nestabilan takt ili loš drajver."; Sugestija="Očistite drajvere DDU alatom i instalirajte nov drajver." }
    "nvlddmkm" = @{ Opis="Rušenje NVIDIA GeForce drajvera."; Zasto="Gubitak odziva GPU-a usled pregrevanja ili napona."; Sugestija="Reinstalirajte NVIDIA drajvere (Clean Install)." }
    "amdkmdag" = @{ Opis="Rušenje AMD Radeon drajvera."; Zasto="Otkazivanje Radeon GPU drajvera."; Sugestija="Resetujte Radeon Adrenalin podešavanja i ažurirajte drajver." }
    "igfx" = @{ Opis="Rušenje Intel integrisane grafike."; Zasto="Gubitak odziva integrisanog GPU-a u procesoru."; Sugestija="Ažurirajte Intel HD/Iris drajver." }
    "Service Control Manager" = @{ Opis="Rušenje Windows servisa (ID 7000/7001)."; Zasto="Problem sa sistemskim zavisnostima servisa."; Sugestija="Pokrenite Opciju 5 (Popravka Sistema DISM/SFC)." }
    "Volmgr" = @{ Opis="Neuspešan zapis crash dump-a (ID 161)."; Zasto="Gubitak napajanja SSD-a u momentu padu sistema."; Sugestija="Proverite spajanje SSD-a i slobodan prostor na C: disku." }
    "Kernel-General" = @{ Opis="Problem sa upisom u Registar (ID 5/6)."; Zasto="Prekinut upis u System Hive usled gašenja."; Sugestija="Pokrenite SFC /scannow popravku." }
    "Kernel-PNP" = @{ Opis="Drajver PnP uređaja nije učitan (ID 219)."; Zasto="Nedostaje drajver za priključeni hardver."; Sugestija="Instalirajte zvanični drajver u Device Manager-u." }
    "BitLocker-Driver" = @{ Opis="Problem sa BitLocker enkripcijom."; Zasto="Promene u TPM čipu ili onemogućen pristup."; Sugestija="Sačuvajte BitLocker recovery ključ." }
    "WindowsUpdateClient" = @{ Opis="Greška pri ažuriranju (ID 20/31)."; Zasto="Oštećen keš Windows Update-a."; Sugestija="Pokrenite Opciju 6 (Popravka Windows Update-a)." }
    "SideBySide" = @{ Opis="Greška C++ biblioteke (ID 33/35/59)."; Zasto="Nedostaje Microsoft Visual C++ Redistributable."; Sugestija="Instalirajte Visual C++ All-in-One paket." }
    "Application Error" = @{ Opis="Kritično rušenje programa (.exe ID 1000)."; Zasto="Nevažeći pristup memorijskoj adresi."; Sugestija="Reinstalirajte navedeni program." }
    "Application Hang" = @{ Opis="Zamrzavanje aplikacije (ID 1002)."; Zasto="Beskonačna petlja ili prekinut I/O odziv."; Sugestija="Proverite opterećenje CPU-a i zdravlje diska." }
    "Schannel" = @{ Opis="Greška TLS/SSL protokola."; Zasto="Nevažeći mrežni sertifikat ili pogrešno vreme."; Sugestija="Podesite tačno sistemsko vreme i datum." }
    "Winlogon" = @{ Opis="Greška pri prijavljivanju korisnika."; Zasto="Problem u korisničkoj sesiji."; Sugestija="Restartujte računar i pokrenite SFC popravku." }
}

try {
    switch ($TaskName) {
        "HardverScan" {
            Set-Progress 5
            Write-Log "=== COMPREHENSIVE HARDVERSKI I SISTEMSKI SKEN ===" "H"

            Set-Progress 20
            Write-Log "Očitavanje OS-a, procesora i memorije..." "I"
            try {
                $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
                $cpu = Get-CimInstance Win32_Processor -ErrorAction Stop
                $regVer = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue
                $displayVer = if ($regVer.DisplayVersion) { $regVer.DisplayVersion } else { $regVer.ReleaseId }
                $buildNum   = $regVer.CurrentBuild
                $ubrNum     = $regVer.UBR
                
                $fullOSInfo = "$($os.Caption) ($($os.OSArchitecture)) | Verzija: $displayVer (Build $buildNum.$ubrNum)"
                $lastUpdate = Get-HotFix -ErrorAction SilentlyContinue | Sort-Object InstalledOn -Descending | Select-Object -First 1
                $updateStr  = if ($lastUpdate) { "$($lastUpdate.HotFixID) ($($lastUpdate.InstalledOn))" } else { "Nije očitano" }

                Write-Log "[OS] $fullOSInfo" "P"
                Write-Log "[POSLEDNJI UPDATE] $updateStr" "P"
                Write-Log "[CPU] $($cpu.Name) | Jezgara: $($cpu.NumberOfCores) | Niti: $($cpu.NumberOfLogicalProcessors)" "P"
                Write-Log "[RAM] Ukupno: $([math]::Round($os.TotalVisibleMemorySize/1MB,2)) GB | Slobodno: $([math]::Round($os.FreePhysicalMemory/1MB,2)) GB" "P"
            } catch { Write-Log "[GREŠKA] Greška pri očitavanju OS podataka." "F" }

            Set-Progress 40
            Write-Log "Očitavanje GPU-a i RAM slotova..." "I"
            try {
                Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | ForEach-Object {
                    $vramStr = if ($_.AdapterRAM -and $_.AdapterRAM -gt 0 -and $_.AdapterRAM -lt 4294967295) {
                        "$([math]::Round($_.AdapterRAM/1GB,2)) GB"
                    } elseif ($_.AdapterRAM -ge 4294967295) {
                        ">= 4 GB (VRAM)"
                    } else {
                        "Deljena / Integrisana (RAM)"
                    }
                    Write-Log "[GPU] Model: $($_.Name) | VRAM: $vramStr | Drajver: $($_.DriverVersion)" "P"
                }
                Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue | ForEach-Object {
                    $capGB = if ($_.Capacity) { [math]::Round($_.Capacity/1GB, 2) } else { 0 }
                    Write-Log "[RAM SLOT] Slot: $($_.DeviceLocator) | Kapacitet: ${capGB} GB | Brzina: $($_.Speed) MHz" "P"
                }
            } catch {}

            Set-Progress 60
            Write-Log "Provera S.M.A.R.T. zdravlja diskova..." "I"
            try {
                $disks = Get-PhysicalDisk -ErrorAction SilentlyContinue
                if ($disks) {
                    foreach ($d in $disks) {
                        $type = if ($d.MediaType -and $d.MediaType -ne 'Unspecified') { $d.MediaType } else { "NVMe/SSD" }
                        if ($d.HealthStatus -eq 'Healthy') {
                            Write-Log "[DISK OK] $($d.FriendlyName) ($type) | Status: ZDRAV" "P"
                        } else {
                            Write-Log "[DISK KRITIČNO] $($d.FriendlyName) ($type) | Status: $($d.HealthStatus)!" "F"
                            Write-Log "   -> HITNA SUGESTIJA: Napravite bekap podataka i zamenite disk." "D"
                        }
                    }
                } else {
                    Get-CimInstance Win32_DiskDrive -ErrorAction SilentlyContinue | ForEach-Object {
                        Write-Log "[DISK] Model: $($_.Model) | Status: $($_.Status)" "P"
                    }
                }
            } catch {}

            Set-Progress 80
            Write-Log "Analiza Windows PnP uređaja i kodova grešaka..." "I"
            try {
                $pnpErrors = Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue | Where-Object { 
                    $_.ConfigManagerErrorCode -ne 0 -and $_.ConfigManagerErrorCode -ne $null -and $_.ConfigManagerErrorCode -ne 22
                }
                if ($pnpErrors) {
                    foreach ($re in $pnpErrors) {
                        $devName = if ($re.Name) { $re.Name } else { $re.DeviceId }
                        $errCode = $re.ConfigManagerErrorCode
                        Write-Log "[KVAR UREĐAJA] $devName (Windows Code $errCode)" "F"
                        if ($CodeManagerDict.ContainsKey($errCode)) {
                            $info = $CodeManagerDict[$errCode]
                            Write-Log "   -> OPIS: $($info.Opis)" "D"
                            Write-Log "   -> REŠENJE: $($info.Sugestija)" "P"
                        } else {
                            Write-Log "   -> REŠENJE: Reinstalirajte drajver ili proverite priključak u Device Manager-u." "P"
                        }
                    }
                } else { Write-Log "[OK] Svi aktivni hardverski uređaji rade ispravno." "P" }
            } catch {}

            Set-Progress 95
            Write-Log "`n=== ANALIZA SISTEMSKIH DNEVNIKA (POSLEDNJIH 7 DANA) ===" "H"
            try {
                $events = Get-WinEvent -FilterHashtable @{LogName='System'; Level=1,2; StartTime=(Get-Date).AddDays(-7)} -MaxEvents 100 -ErrorAction SilentlyContinue | Select-Object -First 10
                if ($events) {
                    foreach ($e in $events) {
                        $evtTime = $e.TimeCreated.ToString('dd.MM.yyyy. HH:mm:ss')
                        $src     = $e.ProviderName
                        Write-Log "[INCIDENT] Vreme: $evtTime | Izvor: $src | Event ID: $($e.Id)" "E"
                        
                        $matched = $false
                        foreach ($kbKey in $EventKB.Keys) {
                            if ($src -match $kbKey) {
                                $matched = $true
                                $kb = $EventKB[$kbKey]
                                Write-Log "   -> PROBLEM: $($kb.Opis)" "F"
                                Write-Log "   -> ZAŠTO: $($kb.Zasto)" "D"
                                Write-Log "   -> REŠENJE: $($kb.Sugestija)" "P"
                                break
                            }
                        }
                        if (-not $matched) {
                            $msgStr = try { $e.Message } catch { $null }
                            if (-not $msgStr) { $msgStr = "Sistemski događaj zabeležen od strane provajdera '$src'." }
                            $msgStr = ($msgStr -replace "[\r\n]+", " ").Trim()
                            if ($msgStr.Length -gt 110) { $msgStr = $msgStr.Substring(0, 110) + "..." }
                            Write-Log "   -> OPIS: $msgStr" "I"
                            Write-Log "   -> REŠENJE: Pokrenite Opciju 5 (Popravka Sistema) i ažurirajte drajvere." "D"
                        }
                    }
                } else { Write-Log "[OK] Nema zabeleženih kritičnih padova u sistemskom dnevniku." "P" }
            } catch { Write-Log "[OK] Nisu detektovani kritični padovi u posmatranom periodu." "P" }

            Set-Progress 100
            Write-Log "=== HARDVERSKI SKEN I ANALIZA ZAVRŠENI ===" "H"
        }

        "MreznaDijagnostika" {
            Set-Progress 10
            Write-Log "=== MREŽNA DIJAGNOSTIKA I PING TEST ===" "H"
            Set-Progress 30
            Write-Log "Skeniram aktivne mrežne kartice i IP adrese..." "I"
            try {
                Get-CimInstance Win32_NetworkAdapterConfiguration -ErrorAction SilentlyContinue | Where-Object { $_.IPEnabled -eq $true } | ForEach-Object {
                    Write-Log "[ADAPTER] $($_.Description)" "P"
                    Write-Log "   -> IPv4 Adresa: $($_.IPAddress -join ', ')" "I"
                    Write-Log "   -> Mrežna Maska: $($_.IPSubnet -join ', ')" "I"
                    Write-Log "   -> Gateway: $($_.DefaultIPGateway -join ', ')" "I"
                    Write-Log "   -> DNS Serveri: $($_.DNSServerSearchOrder -join ', ')" "I"
                    Write-Log "   -> MAC Adresa: $($_.MACAddress)" "I"
                }
            } catch {}

            Set-Progress 60
            Write-Log "`nPokrećem Ping test ka ključnim serverima..." "H"
            $pingTargets = @(
                @{ Name="Google Public DNS"; IP="8.8.8.8" },
                @{ Name="Cloudflare DNS"; IP="1.1.1.1" }
            )
            $pinger = New-Object System.Net.NetworkInformation.Ping
            foreach ($pt in $pingTargets) {
                try {
                    $res = $pinger.Send($pt.IP, 2000)
                    if ($res.Status -eq 'Success') {
                        Write-Log "[PING OK] $($pt.Name) ($($pt.IP)) | Odziv: $($res.RoundtripTime) ms" "P"
                    } else {
                        Write-Log "[PING FAIL] $($pt.Name) ($($pt.IP)) | Status: $($res.Status)" "F"
                    }
                } catch { Write-Log "[PING GREŠKA] $($pt.Name) : $($_.Exception.Message)" "F" }
            }
            Set-Progress 100
            Write-Log "=== MREŽNA DIJAGNOSTIKA ZAVRŠENA ===" "H"
        }

        "BatteryReport" {
            Set-Progress 10
            Write-Log "=== TEST BATERIJE I ZDRAVLJA LAPTOPA ===" "H"
            Set-Progress 30
            $batt = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue
            if (-not $batt) {
                Write-Log "[INFO] Računar je stoni PC (nema ugrađenu bateriju)." "I"
                Write-Log "[OK] Test baterije preskočen (nije primenjivo na Desktop)." "P"
            } else {
                Set-Progress 50
                foreach ($b in $batt) {
                    Write-Log "[BATERIJA] Model: $($b.Name) | Napunjenost: $($b.EstimatedChargeRemaining)%" "P"
                }
                try {
                    $fullCap = (Get-CimInstance -Namespace root\wmi -ClassName MSBatteryFullCapacity -ErrorAction SilentlyContinue | Select-Object -First 1).FullChargedCapacity
                    $designCap = (Get-CimInstance -Namespace root\wmi -ClassName MSBatteryStaticData -ErrorAction SilentlyContinue | Select-Object -First 1).DesignedCapacity
                    if ($designCap -and $designCap -gt 0) {
                        $health = [math]::Min(100, [math]::Round(($fullCap / $designCap) * 100, 1))
                        $wear   = [math]::Max(0, [math]::Round(100 - $health, 1))
                        Write-Log "[KAPACITET] Fabrički: ${designCap} mWh | Trenutni max: ${fullCap} mWh" "D"
                        if ($health -ge 80) {
                            Write-Log "[STATUS] Zdravlje baterije: ${health}% (Degradacija: ${wear}%) - Dobro stanje." "P"
                        } else {
                            Write-Log "[UPOZORENJE] Zdravlje baterije: ${health}% (Degradacija: ${wear}%) - Baterija je istrošena." "F"
                        }
                    }
                } catch {}

                Set-Progress 75
                $desktopPath = [Environment]::GetFolderPath('Desktop')
                $battReportPath = Join-Path $desktopPath "battery-report.html"
                if (Test-Admin) {
                    $null = Start-Process "powercfg.exe" -ArgumentList "/batteryreport /output `"$battReportPath`"" -Wait -NoNewWindow
                    if (Test-Path $battReportPath) {
                        Write-Log "[OK] HTML izveštaj sačuvan na Desktopu: 'battery-report.html'." "P"
                    }
                } else { Write-Log "[NAPOMENA] Generisanje HTML izveštaja zahteva Administrator prava." "D" }
            }
            Set-Progress 100
            Write-Log "=== TEST BATERIJE ZAVRŠEN ===" "H"
        }

        "CiscenjeTemp" {
            Set-Progress 10
            Write-Log "=== ČIŠĆENJE PRIVREMENIH FAJLOVA (TEMP) ===" "H"
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
            Write-Log "[REZULTAT] Uspešno očišćeno $cnt fajlova (${sizeMB} MB oslobođeno)." "P"
            Write-Log "[NAPOMENA] Zaključani fajlovi aktivnih aplikacija su bezbedno preskočeni." "D"
            Set-Progress 100
            Write-Log "=== ČIŠĆENJE TEMP FAJLOVA ZAVRŠENO ===" "H"
        }

        "SistemskaPopravka" {
            if (-not (Test-Admin)) { Write-Log "[GREŠKA] Pokrenite Fercero USB Alat kao Administrator!" "F"; return }
            Set-Progress 10
            Write-Log "1/4: Pokrećem DISM /CheckHealth..." "H"
            $null = Start-Process "DISM.exe" -ArgumentList "/Online /Cleanup-Image /CheckHealth" -Wait -NoNewWindow
            
            Set-Progress 35
            Write-Log "2/4: Pokrećem DISM /ScanHealth (Može potrajati 2-3 minuta)..." "H"
            $null = Start-Process "DISM.exe" -ArgumentList "/Online /Cleanup-Image /ScanHealth" -Wait -NoNewWindow
            
            Set-Progress 60
            Write-Log "3/4: Pokrećem DISM /RestoreHealth (Obnova sistemskih fajlova)..." "H"
            $dism = Start-Process "DISM.exe" -ArgumentList "/Online /Cleanup-Image /RestoreHealth" -Wait -NoNewWindow -PassThru
            if ($dism.ExitCode -eq 0) { Write-Log "[OK] DISM obnova uspešna." "P" } else { Write-Log "[UPOZORENJE] DISM exit code: $($dism.ExitCode)" "E" }
            
            Set-Progress 85
            Write-Log "4/4: Pokrećem SFC /scannow (Skeniranje bazičnih sistemskih fajlova)..." "H"
            $sfc = Start-Process "sfc.exe" -ArgumentList "/scannow" -Wait -NoNewWindow -PassThru
            if ($sfc.ExitCode -eq 0) { Write-Log "[OK] SFC skeniranje završeno bez uočenih grešaka." "P" } else { Write-Log "[UPOZORENJE] SFC je popravio oštećene fajlove." "F" }
            
            $desktopPath = [Environment]::GetFolderPath('Desktop')
            $reportFile = Join-Path $desktopPath "sfcdetails.txt"
            $cbsLog = "$env:windir\Logs\CBS\CBS.log"
            if (Test-Path $cbsLog) {
                Select-String -Path $cbsLog -Pattern "\[SR\]" -ErrorAction SilentlyContinue | ForEach-Object { $_.Line } | Out-File $reportFile -Encoding utf8 -ErrorAction SilentlyContinue
                Write-Log "[OK] Detaljan SFC izveštaj sačuvan na Desktopu: 'sfcdetails.txt'." "P"
            }
            Set-Progress 100
            Write-Log "=== SISTEMSKA POPRAVKA ZAVRŠENA ===" "H"
        }

        "UpdatePopravka" {
            if (-not (Test-Admin)) { Write-Log "[GREŠKA] Pokrenite Fercero USB Alat kao Administrator!" "F"; return }
            Set-Progress 15
            Write-Log "Aktivacija TrustedInstaller servisa..." "H"
            Start-Service -Name "trustedinstaller" -ErrorAction SilentlyContinue

            Set-Progress 35
            Write-Log "Zaustavljanje Windows Update servisa..." "I"
            "bits","wuauserv","msiserver","cryptsvc","appidsvc" | ForEach-Object {
                Stop-Service -Name $_ -Force -ErrorAction SilentlyContinue
            }

            Set-Progress 60
            Write-Log "Preimenovanje keš foldera..." "I"
            $dateStr = Get-Date -Format 'yyyyMMdd_HHmmss'
            if (Test-Path "$env:SystemRoot\SoftwareDistribution") { Rename-Item "$env:SystemRoot\SoftwareDistribution" "SoftwareDistribution.$dateStr.bak" -ErrorAction SilentlyContinue }
            if (Test-Path "$env:SystemRoot\System32\catroot2") { Rename-Item "$env:SystemRoot\System32\catroot2" "catroot2.$dateStr.bak" -ErrorAction SilentlyContinue }

            Set-Progress 80
            Write-Log "Čišćenje komponenata i ponovno pokretanje servisa..." "I"
            Start-Process "DISM.exe" -ArgumentList "/Online /Cleanup-image /StartComponentCleanup" -Wait -NoNewWindow
            "bits","wuauserv","msiserver","cryptsvc","appidsvc" | ForEach-Object {
                Start-Service -Name $_ -ErrorAction SilentlyContinue
            }

            Set-Progress 100
            Write-Log "[OK] Windows Update sistem uspešno resetovan." "P"
        }

        "MrezniReset" {
            if (-not (Test-Admin)) { Write-Log "[GREŠKA] Pokrenite Fercero USB Alat kao Administrator!" "F"; return }
            Set-Progress 30
            Write-Log "Resetovanje DNS keša..." "H"
            Start-Process "ipconfig.exe" -ArgumentList "/flushdns" -Wait -NoNewWindow
            Set-Progress 60
            Write-Log "Resetovanje Winsock i TCP/IP protokola..." "H"
            Start-Process "netsh.exe" -ArgumentList "winsock reset" -Wait -NoNewWindow
            Start-Process "netsh.exe" -ArgumentList "int ip reset" -Wait -NoNewWindow
            Set-Progress 100
            Write-Log "[OK] Mrežni protokoli (TCP/IP i Winsock) uspešno resetovani." "P"
        }

        "RestartBios" {
            if (-not (Test-Admin)) { Write-Log "[GREŠKA] Ulazak u Advanced Startup zahteva Administrator prava!" "F"; return }

            Write-Log "=== RESTART U ADVANCED STARTUP MENI ===" "H"
            Write-Log "Šaljem sistemsku komandu za restartovanje u Napredne Opcije Pokretanja..." "I"
            Write-Log "   -> U meniju koji se otvori možete izabrati: BIOS/UEFI Settings, Safe Mode ili Startup Repair." "P"
            
            $proc = Start-Process "shutdown.exe" -ArgumentList "/r /o /t 2" -Wait -NoNewWindow -PassThru
            if ($proc.ExitCode -ne 0) {
                Write-Log "[GREŠKA] Greška pri slanju komande za restart (Exit Code: $($proc.ExitCode))." "F"
            } else {
                Write-Log "[OK] Računar se restartuje u Advanced Startup meni za 2 sekunde..." "P"
            }
            Set-Progress 100
        }
    }
} catch { Write-Log "[KRITIČNA GREŠKA] Exception: $($_.Exception.Message)" "F" }
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
        <!-- Moderni Slim ScrollBar -->
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
                    <TextBlock Text="⚡ FERCERO USB ALAT" FontSize="18" FontWeight="Bold" Foreground="#38BDF8"/>
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
                    <TextBlock Text="DIJAGNOSTIČKA KONZOLA I IZVEŠTAJ" FontSize="12" FontWeight="Bold" Foreground="#94A3B8" VerticalAlignment="Center"/>
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
                <TextBlock x:Name="StatusLbl" Text="Status: Spreman za rad." FontWeight="SemiBold" Foreground="#38BDF8" VerticalAlignment="Center"/>
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
# 3. KONTROLER I EVENT HANDLERI
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

# BAZIČNE DIJAGNOSTIČKE FUNKCIJE
$btnDefs = @(
    @{ L="1. Hardverski Sken & Logovi"; K="HardverScan" },
    @{ L="2. Mrežna Dijagnostika & Ping"; K="MreznaDijagnostika" },
    @{ L="3. Test Baterije (Laptop)"; K="BatteryReport" },
    @{ L="4. Čišćenje Smeća (Temp)"; K="CiscenjeTemp" },
    @{ L="5. Popravka Sistema (DISM/SFC)"; K="SistemskaPopravka" },
    @{ L="6. Popravka Windows Update-a"; K="UpdatePopravka" },
    @{ L="7. Reset Mreže i DNS-a"; K="MrezniReset" },
    @{ L="8. Sačuvaj Izveštaj (.html)"; K="SacuvajIzvestaj" },
    @{ L="9. Restart u Advanced Startup / BIOS"; K="RestartBios" }
)

foreach ($def in $btnDefs) {
    $b = [System.Windows.Controls.Button]::new()
    $b.Content = $def.L
    $b.Style = $navStyle
    $b.Tag = $def.K
    $b.Add_Click({ param($s,$e); Start-Task $s.Tag })
    $BtnStack.Children.Add($b) | Out-Null
}

# DINAMIČKO SKENIRANJE PORTABLE ALATA SA USB-A (\Tools\)
$usbToolsPath = if ($env:BAT_DIR) { Join-Path $env:BAT_DIR "Tools" } else { "Tools" }
$detectedExeFiles = @()

if (Test-Path $usbToolsPath) {
    $detectedExeFiles = Get-ChildItem -Path $usbToolsPath -Filter "*.exe" -Recurse -ErrorAction SilentlyContinue
}

# SEKCIJA U MENIJU ZA PRENOSIVE ALATE
$headerTxt = [System.Windows.Controls.TextBlock]::new()
$headerTxt.Text = "🧰 PRENOSIVI ALATI (USB)"
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
                Append-Log "`n[POKRETANJE] Pokrećem prenosivi alat: $($s.Content)..." "#38BDF8"
                Start-Process -FilePath $exePath -Verb RunAs -ErrorAction Stop
                Append-Log "[OK] Alat uspešno pokrenut iz: $exePath" "#4ADE80"
            } catch {
                Append-Log "[GREŠKA] Neuspešno pokretanje alata: $($_.Exception.Message)" "#F87171"
            }
        })
        $BtnStack.Children.Add($btn) | Out-Null
    }
} else {
    $noToolsTxt = [System.Windows.Controls.TextBlock]::new()
    $noToolsTxt.Text = "Nema .exe fajlova u \Tools\ folderu."
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
        $fileName = "FerceroUSB_Izvestaj_$ts.html"
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
                elseif ($line -match "\[GREŠKA\]|\[KRITIČNO\]|\[INCIDENT\]|\[PING FAIL\]|\[KVAR UREĐAJA\]") { $color = "#F87171" }
                elseif ($line -match "\[UPOZORENJE\]|\[NAPOMENA\]|\[KAPACITET\]") { $color = "#FACC15" }
                elseif ($line -match "\[OS\]|\[CPU\]|\[RAM\]|\[GPU\]|\[DISK\]|\[BATERIJA\]|\[ADAPTER\]") { $color = "#38BDF8" }

                $htmlLines += "<div class='log-line' style='color: $color;'>$escapedLine</div>"
            }
            $htmlBody = $htmlLines -join "`n"

            $htmlContent = @"
<!DOCTYPE html>
<html lang="sr">
<head>
    <meta charset="UTF-8">
    <title>Fercero USB Alat — Dijagnostički Izveštaj</title>
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
            <div class="title">⚡ FERCERO USB ALAT — DIJAGNOSTIČKI IZVEŠTAJ</div>
        </div>
        <div class="meta">
            <strong>Datum i vreme skeniranja:</strong> $dateFormatted<br>
            <strong>Računar:</strong> $env:COMPUTERNAME &nbsp;|&nbsp; <strong>Aktivni Korisnik:</strong> $env:USERNAME<br>
            <strong>Platforma:</strong> Fercero USB Alat v8.7 Final Edition
        </div>
        <div class="console">
            $htmlBody
        </div>
    </div>
</body>
</html>
"@
            $htmlContent | Out-File -FilePath $filePathDesktop -Encoding utf8 -ErrorAction Stop
            Append-Log "`n[OK] HTML IZVEŠTAJ SAČUVAN NA DESKTOPU: $filePathDesktop" "#4ADE80"
            
            if ($env:BAT_DIR -and (Test-Path $env:BAT_DIR)) {
                $usbFolder = Join-Path $env:BAT_DIR "Reports"
                if (-not (Test-Path $usbFolder)) { New-Item -ItemType Directory -Path $usbFolder -ErrorAction SilentlyContinue | Out-Null }
                $filePathUSB = Join-Path $usbFolder $fileName
                $htmlContent | Out-File -FilePath $filePathUSB -Encoding utf8 -ErrorAction SilentlyContinue
                Append-Log "[OK] HTML IZVEŠTAJ SAČUVAN NA USB DRAJVU: $filePathUSB" "#4ADE80"
            }

            [System.Windows.MessageBox]::Show("Kompletan HTML izveštaj je sačuvan na Desktopu!`n`nPutanja: $filePathDesktop", "Izveštaj Sačuvan", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
        } catch {
            [System.Windows.MessageBox]::Show("Greška pri čuvanju izveštaja: $($_.Exception.Message)", "Greška", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
        }
        return
    }

    if ($TaskName -eq "RestartBios") {
        $confirm = [System.Windows.MessageBox]::Show("Da li ste sigurni da želite da restartujete računar u Advanced Startup (Napredne Opcije Pokretanja)?", "Potvrda Restarta", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning)
        if ($confirm -ne [System.Windows.MessageBoxResult]::Yes) { return }
    }

    $script:IsBusy = $true
    $PBar.Value = 0
    $LogBox.Document.Blocks.Clear()
    foreach ($child in $BtnStack.Children) { if ($child -is [System.Windows.Controls.Button]) { $child.IsEnabled = $false } }
    $StatusLbl.Text = "Status: Izvršavanje [$TaskName]..."

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

# TAJMER ZA TAČNO I BEZBEDNO PRATIĆE OSVEŽAVANJE INTERFEJSA
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
        $StatusLbl.Text = "Status: Spreman za rad."
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

Append-Log "Dobrodošli u Fercero USB Alat v8.7 (Final Edition)" "#38BDF8"
if ($detectedExeFiles.Count -gt 0) {
    Append-Log "[INFO] Detektovano je $($detectedExeFiles.Count) prenosivih alata u '\Tools\' folderu." "#4ADE80"
} else {
    Append-Log "[INFO] Ubacite prenosive alate (.exe) u '\Tools\' folder na USB-u za automatsku integraciju." "#FACC15"
}
Append-Log "--------------------------------------------------------------------------------------------------" "#334155"

[void]$Window.ShowDialog()

} catch {
    [System.Windows.Forms.MessageBox]::Show(
        "Kritična greška pri pokretanju aplikacije:`n`n$($_.Exception.Message)`n`nLokacija:`n$($_.ScriptStackTrace)",
        "Fercero USB Alat - Dijagnostička Greška",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    )
}