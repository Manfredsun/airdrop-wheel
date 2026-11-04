<p align="center">
  <img src="Design/Logo/magnific__design-a-minimalist-japaneseinspired-logo-for-a-ma__78247.png" alt="AirDrop Wheel Logo" width="160" height="160" style="border-radius: 36px; box-shadow: 0 12px 32px rgba(0,0,0,0.15);" />
</p>

<h1 align="center">AirDrop Wheel</h1>

<p align="center">
  <strong>Radial File Dropping Meets Native AirDrop for macOS.</strong><br>
  A high-performance, zero-dependency, pure Swift macOS utility that reimagines peer-to-peer file sharing.
</p>

<p align="center">
  <a href="https://manfredsun.github.io/airdrop-wheel/">🌐 <strong>Official Website & Live Demo</strong></a> •
  <a href="README.zh-TW.md">🇹🇼 <strong>繁體中文版說明</strong></a> •
  <a href="#quick-start">🚀 <strong>Quick Start</strong></a> •
  <a href="#architecture">📐 <strong>Architecture</strong></a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14.0%2B-blue.svg?style=flat-square&logo=apple" alt="macOS 14.0+" />
  <img src="https://img.shields.io/badge/Swift-5.0-orange.svg?style=flat-square&logo=swift" alt="Swift 5.0" />
  <img src="https://img.shields.io/badge/Architecture-Universal%20(ARM64%20%2F%20x86__64)-purple.svg?style=flat-square" alt="Universal Binary" />
  <img src="https://img.shields.io/badge/License-MIT-green.svg?style=flat-square" alt="License: MIT" />
  <img src="https://img.shields.io/badge/PRs-welcome-brightgreen.svg?style=flat-square" alt="PRs Welcome" />
</p>

---

## ✨ Features

- 🎯 **FormatWheel Radial Interaction**: Hold <kbd>⌃ Control</kbd> while dragging files in Finder or on your Desktop to instantly reveal the radial wheel right at your cursor. Flick into any sector and release to send.
- ⚡ **Pure Swift Engine**: Completely rewritten in modern native Swift using Apple's `Network.framework` and native AWDL (`awdl0`) streaming. Zero C/Python FFI bloat, instantaneous launch, and bounded constant memory ($O(1)$) through POSIX ODC CPIO chunking.
- 🤫 **Total Silence Policy**: Strictly 100% silent. Zero audio files included, zero system beeps or sound APIs linked (`NSSound`, `AudioServices`, etc.). Your workflow stays completely undisturbed.
- 🏷️ **Dynamic Device Classification**: Real-time Bonjour DNS-SD discovery (`_airdrop._tcp`). Automatically maps device glyphs and models (MacBook Pro, iPhone, iPad) and intelligently excludes your own host machine.
- 🎨 **Adaptive Brand Aesthetics**: Blends minimalist Japanese graphic design with glassmorphic depth. Dynamically adapts between rice-white (`#FEF6EA`) and deep navy (`#003D6C`) palettes with neon cyan accents.
- 🛡️ **Zero Privacy Compromise**: Transparent peer-to-peer connection with TLS Leaf Certificate Pinning. No SIP disabling, no TCC injection, no Keychain credential theft, and no analytics or telemetry.

---

## 📸 Interactive Demo

Experience the interactive radial wheel simulation directly in your browser without installing anything:

👉 **[Launch Online Interactive Playground](https://manfredsun.github.io/airdrop-wheel/)**

---

## 📋 Requirements

| Requirement | Specification |
| :--- | :--- |
| **Operating System** | macOS 14.0 Sonoma or later |
| **Hardware** | Apple Silicon (M1/M2/M3/M4) or Intel Mac (Universal Binary) |
| **Connectivity** | Wi-Fi and Bluetooth turned on (required for AirDrop discovery) |
| **Recipient Device** | AirDrop set to **"Everyone for 10 minutes"** |

> [!NOTE]
> Like all non-Apple AirDrop engines, targeting contacts without exposing Apple ID cryptographically requires the recipient device to be set to **"Everyone for 10 minutes"**. When sending, the recipient will receive the standard native prompt asking to Accept or Decline.

---

## 🔒 Permissions & Setup

To function smoothly as a system-wide file-drag companion, AirDrop Wheel requires:

1. **Accessibility Permission (`AXIsProcessTrusted`)**:
   Required to monitor mouse coordinates and global drag events when holding <kbd>⌃ Control</kbd>.
   - *System Settings → Privacy & Security → Accessibility → Enable AirDrop Wheel*.
2. **Local Network Permission**:
   Required to browse nearby AirDrop peers over AWDL Bonjour.
3. **Full Disk Access (Optional)**:
   Recommended if you plan to send files from protected folders (e.g. `~/Downloads`, `~/Documents`, external drives). A direct shortcut is accessible via the menu bar icon.

---

## 🚀 Quick Start

### Option 1: Download Pre-built App

1. Download the latest `AirDrop Wheel.app` from [GitHub Releases](https://github.com/Manfredsun/airdrop-wheel/releases).
2. Move `AirDrop Wheel.app` to your `/Applications` folder.
3. Launch the app and grant Accessibility and Local Network permissions when prompted.
4. Drag any file and hold <kbd>⌃ Control</kbd> to bring up the wheel!

### Option 2: Build from Source

AirDrop Wheel uses native Xcode configuration with zero external package manager dependencies:

```bash
# Clone the repository
git clone https://github.com/Manfredsun/airdrop-wheel.git
cd airdrop-wheel

# Build Release application into dist/
bash scripts/build_release.sh
```

The compiled application will be generated and code-signed at:
`dist/AirDrop Wheel.app`

---

## 📐 Architecture

AirDrop Wheel adopts a strict layered architecture:

```text
  [ User Drag / Finder Gesture ]
               │
               ▼ (⌃ Control Key)
     ┌───────────────────┐
     │   WheelOverlay    │ ◄── Full-screen 35% immersive backdrop
     └─────────┬─────────┘
               │ (Polar coordinate sector mapping)
               ▼
     ┌───────────────────┐
     │  WheelView (NSUI) │ ◄── 8-sector slices, central readout hub, adaptive palette
     └─────────┬─────────┘
               │
               ▼ (Flick & Release)
 ┌───────────────────────────┐
 │    TransferCoordinator    │ ◄── Finite State Machine (pending → asking → accepted → uploading)
 └─────────────┬─────────────┘
               │
        ┌──────┴─────────────────────────────────┐
        ▼                                        ▼
┌───────────────────────────────┐ ┌───────────────────────────────┐
│       Discovery Module        │ │       Transport Module        │
│ • AWDL Interface Binding      │ │ • Native TLS Leaf Pinning     │
│ • NWBrowser _airdrop._tcp     │ │ • POST /Discover & POST /Ask  │
│ • Dynamic Device Classifier   │ │ • POSIX ODC CPIO 64KiB Chunks │
└───────────────────────────────┘ └───────────────────────────────┘
```

For comprehensive technical specifications, protocols, and math formulas, see **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)**.

---

## ❓ Troubleshooting

Having issues discovering devices or triggering the wheel? Check out our step-by-step diagnostic guide:

👉 **[Troubleshooting & FAQ Guide](docs/TROUBLESHOOTING.md)**

---

## 🤝 Contributing

Contributions, bug reports, and pull requests are warmly welcomed! Please read our **[CONTRIBUTING.md](CONTRIBUTING.md)** before submitting code.

### Irrevocable Project Principles:
1. **Total Silence**: Never add audio files or invoke audio frameworks.
2. **No Apple Sharing Dialogs**: Never invoke `NSSharingService`.
3. **No Fake Progress**: All UI progress bars must strictly reflect acknowledged network bytes.
4. **Preserve Design Assets**: The 2048×2048 logo artwork and squircle proportions are strictly protected.

---

## 📄 License & Attribution

- **AirDrop Wheel** is released under the [MIT License](LICENSE). Copyright (c) 2026 Manfred Shen (申承羲).
- **FormatWheel**: Radial wheel interaction philosophy references FormatWheel (Copyright (c) 2026 Elise616, MIT License).
- **Brand Assets**: The name "AirDrop Wheel" and original logo assets are proprietary and reserved.
