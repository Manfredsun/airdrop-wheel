# Troubleshooting & Frequently Asked Questions (FAQ)

This guide helps you diagnose and resolve common setup, permission, and connection issues with **AirDrop Wheel**.

---

## 🔍 Quick Diagnostic Checklist

Before diving into specific issues, ensure the following basics are met:
- [ ] Both your Mac and the target device have **Wi-Fi and Bluetooth turned ON**.
- [ ] The target device (iPhone, iPad, or Mac) has AirDrop set to **"Everyone for 10 minutes"** (not "Contacts Only").
- [ ] AirDrop Wheel is granted **Accessibility** and **Local Network** permissions.
- [ ] The target device screen is **unlocked** (iOS devices will not display transfer alerts while locked).

---

## 1. Discovery Issues

### ❓ "My iPhone / Mac is not appearing in the wheel sectors."

#### Cause 1: Target device is in "Contacts Only" mode
Apple's "Contacts Only" mode relies on Apple ID iCloud cryptographic identity tokens, which cannot be exchanged without signing into an official Apple account in the kernel.
- **Solution**: On the receiving iPhone or iPad, open **Control Center → long-press the Network tile → tap AirDrop → select "Everyone for 10 Minutes"**.

#### Cause 2: Local Network permission missing on macOS
If Local Network permission was denied during the first run, macOS will block mDNS queries on `_airdrop._tcp`.
- **Solution**: Open **System Settings → Privacy & Security → Local Network**, and ensure **AirDrop Wheel** is enabled.

#### Cause 3: VPN or Network Filter interfering with AWDL
Certain third-party VPNs or firewall software disable local peer-to-peer multicast or link-local IPv6 traffic.
- **Solution**: Temporarily pause your VPN or configure it to allow local network traffic.

---

## 2. Gesture & Interaction Issues

### ❓ "Dragging a file and pressing Control does not bring up the wheel."

#### Cause: Accessibility Permission (`AXIsProcessTrusted`) is disabled
macOS requires Accessibility authorization for applications to monitor mouse drag events and global keypresses.
- **Solution**:
  1. Open **System Settings → Privacy & Security → Accessibility**.
  2. Locate **AirDrop Wheel** in the list.
  3. If already checked, turn it OFF and turn it back ON.
  4. Restart AirDrop Wheel.

### ❓ "The wheel opens, but no file is attached to the center hub."
- **Solution**: Ensure you start dragging the file **before** or **simultaneously** with pressing the <kbd>⌃ Control</kbd> key. Releasing the file over an empty sector will close the wheel.

---

## 3. Transfer & Permission Issues

### ❓ "The target device sees the prompt, but transfer fails immediately upon clicking Accept."

#### Cause 1: TCC File Read Permission (Full Disk Access)
If the file you are sending is located in `~/Downloads`, `~/Documents`, `~/Desktop`, or an external USB drive, macOS sandbox may prevent AirDrop Wheel from reading the binary data.
- **Solution**:
  1. Click the **AirDrop Wheel icon** in the macOS menu bar.
  2. Select **"Open Full Disk Access Settings..."**.
  3. Add or enable **AirDrop Wheel**.

#### Cause 2: iPhone Screen Auto-Locked
If the iPhone screen turns off while the prompt is pending, iOS will immediately abort the TLS connection.
- **Solution**: Keep the screen awake and unlocked while clicking "Accept".

---

## 4. Resetting & Diagnostic Commands

### Check AirDrop Interface Status via Terminal
To check whether the Apple Wireless Direct Link (`awdl0`) interface is active:
```bash
ifconfig awdl0
```
It should report `status: active` and list an IPv6 `fe80::...` link-local address.

### Check Console Logs
To inspect live logs from AirDrop Wheel:
```bash
log stream --predicate 'subsystem == "app.airdropwheel.macos"' --info
```

### Reset Accessibility Permissions
If permissions become corrupted after a rebuild:
```bash
tccutil reset Accessibility app.airdropwheel.macos
```
Then relaunch the app to be prompted again.

---

## 💬 Still Having Issues?

If your problem persists, please check existing reports or open a new issue with your diagnostic logs:
👉 **[Open an Issue on GitHub](https://github.com/Manfredsun/airdrop-wheel/issues)**
