# Contributing to AirDrop Wheel

Thank you for your interest in contributing to **AirDrop Wheel**! We welcome bug fixes, documentation enhancements, UI polish, and performance optimizations.

Before starting, please take a moment to read through these guidelines to ensure smooth collaboration.

---

## 🏛️ Inviolable Architectural Principles (Core Guardrails)

AirDrop Wheel was created with an uncompromising design philosophy. Every pull request is expected to honor these core principles:

1. **Total Silence (完全靜音)**:
   - **Zero sound files**: Do not add `.wav`, `.mp3`, `.aiff`, or any audio assets.
   - **Zero sound APIs**: Do not invoke `NSSound`, `AVAudioPlayer`, `AVAudioEngine`, `AudioServicesPlaySystemSound`, or `NSBeep`. Do not link `AVFoundation` or `AudioToolbox`.
2. **No Apple Sharing Dialogs**:
   - Never call `NSSharingService` or trigger system AirDrop modals. The experience must remain purely within the radial wheel and lightweight HUD.
3. **No Fake Devices or Progress**:
   - If a device is unreachable, refused, or disconnected, the UI must faithfully transition to a declined or failed state. Progress bars must correspond strictly to acknowledged network socket bytes.
4. **Preserve Original Design Assets**:
   - The master 2048×2048 PNG in `Design/Logo/` and the Apple HIG continuous squircle proportions must never be altered or replaced with AI regenerations.
5. **No System Tampering**:
   - Do not require disabling System Integrity Protection (SIP), injecting into system daemons, extracting private Keychain secrets, or modifying system TCC databases.

---

## 🛠️ Development Setup

AirDrop Wheel is designed with zero third-party dependencies (no CocoaPods, Carthage, or SPM packages).

### Prerequisites
- macOS 14.0 Sonoma or later.
- Xcode 15.0 or later (with Command Line Tools installed: `xcode-select --install`).
- Python 3 (for project generation tools).

### Building & Running
You can open `AirDrop Wheel.xcodeproj` directly in Xcode, or build from the command line:

```bash
# Debug build
xcodebuild -project "AirDrop Wheel.xcodeproj" -scheme "AirDrop Wheel" -configuration Debug build

# Release build & package to dist/
bash scripts/build_release.sh
```

### Regrowing App Icons
If you ever adjust the icon rendering script, run:
```bash
swift scripts/make_app_icon.swift
```

---

## 🌿 Branching & Git Workflow

1. **Fork** the repository on GitHub.
2. **Clone** your fork locally:
   ```bash
   git clone https://github.com/<your-username>/airdrop-wheel.git
   cd airdrop-wheel
   ```
3. Create a feature branch with a descriptive name:
   ```bash
   git checkout -b feat/your-feature-name
   # or
   git checkout -b fix/your-bugfix-name
   ```
4. Commit your changes following [Conventional Commits](https://www.conventionalcommits.org/):
   - `feat(...)`: A new feature
   - `fix(...)`: A bug fix
   - `docs(...)`: Documentation updates
   - `refactor(...)`: Code refactoring without behavior change
   - `perf(...)`: Performance improvement
5. Push to your fork and submit a **Pull Request**.

---

## 🧪 Pull Request Checklist

Before opening your PR, please verify:
- [ ] Code compiles without warnings on macOS 14+ (`bash scripts/build_release.sh`).
- [ ] The Total Silence policy is strictly maintained (no audio APIs or sound assets).
- [ ] No local absolute paths (e.g. `/Users/...`) or personal credentials are hardcoded.
- [ ] All public methods and core types maintain clear Swift documentation comments.
- [ ] Relevant documentation or troubleshooting entries are updated.

---

## 💬 Community & Questions

Feel free to open an [Issue](https://github.com/Manfredsun/airdrop-wheel/issues) for discussion or join ongoing topics!
