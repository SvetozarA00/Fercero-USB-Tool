# ⚡ Fercero USB Tool (v8.7 Final Edition)

**Fercero USB Tool** is an open-source, multi-threaded Windows diagnostic, repair, and optimization utility built with PowerShell and a modern WPF/XAML Dark Mode GUI. Designed to run directly from a USB drive, it streamlines IT maintenance, hardware troubleshooting, system repair, and network diagnostics.

![Windows](https://img.shields.io/badge/OS-Windows%2010%20%7C%2011-0078D6?style=flat&logo=windows)
![License](https://img.shields.io/badge/License-MIT-green.svg)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)

---

## ✨ Features

- 🔍 **Comprehensive Hardware Scan:** Inspects OS build, CPU/RAM stats, GPU VRAM, physical RAM slots, and S.M.A.R.T. disk health.
- 🚨 **Device Manager & Event Log Analysis:** Features an integrated lookup database for Device Manager error codes (Codes 1–54) and critical Windows System Event logs (BSOD, Kernel-Power, WHEA, Disk errors).
- 🌐 **Network Diagnostics:** Automated adapter scanning, IP/MAC details, DNS/Winsock resets, and response latency ping tests.
- 🔋 **Battery Health Inspector:** Evaluates laptop battery degradation, wear levels, and generates formal `battery-report.html` outputs.
- 🛠️ **System Repair Suite:** Executes `DISM` image integrity checks/restorations and `SFC` system file scans with automated log extraction.
- 🔄 **Windows Update Troubleshooter:** Resets Windows Update services and clears corrupted cache directories (`SoftwareDistribution` & `catroot2`).
- 🧰 **Dynamic Portable Tool Loader:** Auto-detects and launches third-party portable utilities placed in the `\Tools\` directory with elevated privileges.
- 📄 **HTML Report Generator:** Generates formatted dark-mode HTML diagnostic summaries saved directly to Desktop and USB drives.

---

## 🚀 Getting Started

### Prerequisites
- **Operating System:** Windows 10 / Windows 11
- **PowerShell:** Version 5.1 or higher
- **Privileges:** Administrator rights (required for DISM, SFC, Network resets, and Windows Update fixes).

## 🗺️ Roadmap & Planned Features

We are actively looking for contributors! Here is what we plan to build next:
- [ ] Real-time CPU and GPU temperature monitoring
- [ ] Multilingual support (German, Spanish, Serbian)
- [ ] Driver backup and restore module
- [ ] Automated Windows Update cache cleanup (`WinSxS` folder)
- [ ] Export diagnostic report to JSON format
- [ ] Or any useful changes!
