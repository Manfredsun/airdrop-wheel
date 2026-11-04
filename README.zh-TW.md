<p align="center">
  <img src="Design/Logo/magnific__design-a-minimalist-japaneseinspired-logo-for-a-ma__78247.png" alt="AirDrop Wheel Logo" width="160" height="160" style="border-radius: 36px; box-shadow: 0 12px 32px rgba(0,0,0,0.15);" />
</p>

<h1 align="center">AirDrop Wheel</h1>

<p align="center">
  <strong>FormatWheel 徑向輪盤操作哲學 ✕ 原生純 Swift AirDrop 傳輸引擎</strong><br>
  專為 macOS 打造的高效能、零依賴、純淨優雅的點對點檔案拋送工具。
</p>

<p align="center">
  <a href="https://manfredsun.github.io/airdrop-wheel/">🌐 <strong>官方網站與線上互動展示</strong></a> •
  <a href="README.md">🇬🇧 <strong>English Version</strong></a> •
  <a href="#快速開始">🚀 <strong>快速開始</strong></a> •
  <a href="#系統架構">📐 <strong>技術架構</strong></a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14.0%2B-blue.svg?style=flat-square&logo=apple" alt="macOS 14.0+" />
  <img src="https://img.shields.io/badge/Swift-5.0-orange.svg?style=flat-square&logo=swift" alt="Swift 5.0" />
  <img src="https://img.shields.io/badge/Architecture-Universal%20(ARM64%20%2F%20x86__64)-purple.svg?style=flat-square" alt="Universal Binary" />
  <img src="https://img.shields.io/badge/License-MIT-green.svg?style=flat-square" alt="License: MIT" />
  <img src="https://img.shields.io/badge/PRs-welcome-brightgreen.svg?style=flat-square" alt="歡迎提交 PR" />
</p>

---

## ✨ 核心特色

- 🎯 **FormatWheel 徑向輪盤互動**：在 Finder 或桌面拖曳檔案時，按住 <kbd>⌃ Control</kbd> 鍵即可直接在滑鼠游標處彈出 8 扇區徑向輪盤。將檔案甩入目標裝置扇區即可直覺發送。
- ⚡ **純 Swift 原生傳輸引擎**：以 Apple 原生 `Network.framework` 與 AWDL 協定重構，徹底摒棄繁複的 C/Python FFI，啟動秒發、藉由 POSIX ODC CPIO 分塊傳輸維持 $O(1)$ 常數記憶體邊界。
- 🤫 **完全靜音原則 (Total Silence)**：全專案嚴格零音效檔案、零音訊 API 呼叫（不調用 `NSSound`、`NSBeep`、`AudioServices`）。維持專注、純粹且安靜的專業工作流程。
- 🏷️ **動態裝置識別與過濾**：即時解析 Bonjour DNS-SD `_airdrop._tcp`，自動對應裝置外觀圖示與真實型號（MacBook Pro、iPhone、iPad），並聰明隱藏本機裝置。
- 🎨 **自適應日系極簡美學**：融合日系極簡與現代 macOS 毛玻璃深度，於米白背景（`#FEF6EA`）與深藍（`#003D6C`）之間自動隨系統外觀平滑切換，外圈點綴電光藍（`#00B4D8`）光暈。
- 🛡️ **誠實透明的安全防護**：透過 TLS 葉憑證固定（Leaf Certificate Pinning）確保同一發送任務不被中間人置換金鑰。絕不修改系統 SIP、不注入 TCC、不竊取 Keychain 私鑰、零背景追蹤。

---

## 📸 線上互動體驗

您無需預先安裝任何 App，即可在瀏覽器中直接體驗徑向輪盤的流暢操作：

👉 **[開啟線上互動展示頁面 (Live Playground)](https://manfredsun.github.io/airdrop-wheel/)**

---

## 📋 系統需求

| 需求項目 | 規範說明 |
| :--- | :--- |
| **作業系統** | macOS 14.0 Sonoma 或更高版本 |
| **硬體架構** | 支援 Apple Silicon (M1/M2/M3/M4) 及 Intel Mac（通用二進位版本） |
| **連線環境** | 需開啟 Wi-Fi 與藍牙（AirDrop 探索必備通道） |
| **接收端設定** | 接收裝置之 AirDrop 需設定為 **「所有人（10 分鐘）」** |

> [!NOTE]
> 與所有非 Apple 官方私有系統的 AirDrop 工具相同，在不牽涉 Apple ID 密碼學身分私鑰的前提下，接收端需開啟「所有人（10 分鐘）」。發送時，對端螢幕同樣會跳出原生「接受／拒絕」提示視窗，接收者可完全自主把關。

---

## 🔒 系統權限與設定指南

為發揮全局滑鼠拖曳與檔案發送功能，AirDrop Wheel 需要以下系統授權：

1. **輔助使用權限 (`AXIsProcessTrusted`)**：
   用於全域監聽滑鼠座標與拖曳檔案時的 <kbd>⌃ Control</kbd> 快速叫出熱鍵。
   - 前往 *系統設定 → 隱私權與安全性 → 輔助使用 → 勾選 AirDrop Wheel*。
2. **區域網絡權限 (Local Network)**：
   用於透過 AWDL 與 mDNS 搜尋附近的 AirDrop 裝置。
3. **完全磁碟取用權限 (選填)**：
   若需從受保護路徑（如 `~/Downloads`、`~/Documents` 或外接硬碟）發送檔案，建議開啟。可直接從選單列圖示快速跳轉設定。

---

## 🚀 快速開始

### 方式一：下載現成編譯發行版

1. 前往 [GitHub Releases](https://github.com/Manfredsun/airdrop-wheel/releases) 下載最新版的 `AirDrop Wheel.app`。
2. 將應用程式拖入 `/Applications`（應用程式）目錄。
3. 啟動並依提示授予輔助使用與區域網絡權限。
4. 拖曳檔案並按住 <kbd>⌃ Control</kbd> 即可呼喚輪盤！

### 方式二：從原始碼本地編譯

本專案採用純原生 Xcode 專案結構，無任何第三方套件管理工具包袱：

```bash
# 複製專案原始碼
git clone https://github.com/Manfredsun/airdrop-wheel.git
cd airdrop-wheel

# 一鍵編譯 Release 版本至 dist/ 目錄
bash scripts/build_release.sh
```

編譯完成並已通過代碼簽署之產物將位於：
`dist/AirDrop Wheel.app`

---

## 📐 系統技術架構

AirDrop Wheel 採分層架構設計：

```text
  [ 使用者於 Finder 或桌面拖曳檔案 ]
               │
               ▼ (按住 ⌃ Control 鍵)
     ┌───────────────────┐
     │   WheelOverlay    │ ◄── 全螢幕 35% 柔和暗化層，確保極座標判定無死角
     └─────────┬─────────┘
               │ (極座標角度與距離計算)
               ▼
     ┌───────────────────┐
     │  WheelView (NSUI) │ ◄── 8 扇區刻度環、純功能性動態讀出 Hub、深淺自適應
     └─────────┬─────────┘
               │
               ▼ (甩入扇區並放開滑鼠)
 ┌───────────────────────────┐
 │    TransferCoordinator    │ ◄── 嚴格狀態機 (pending → asking → accepted → uploading)
 └─────────────┬─────────────┘
               │
        ┌──────┴─────────────────────────────────┐
        ▼                                        ▼
┌───────────────────────────────┐ ┌───────────────────────────────┐
│       Discovery 探索模組      │ │       Transport 傳輸模組      │
│ • 綁定 awdl0 介面             │ │ • 原生 TLS 葉憑證釘選驗證     │
│ • NWBrowser _airdrop._tcp     │ │ • HTTP POST /Discover, /Ask   │
│ • 動態裝置分類與自身排除      │ │ • POSIX ODC CPIO 64KiB 分塊串流│
└───────────────────────────────┘ └───────────────────────────────┘
```

更深入的協定二進位解析、CPIO 標頭結構與數學幾何演算法，請參閱 **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)**。

---

## ❓ 疑難排解與常見問答

若遇到搜尋不到附近裝置、權限無法啟用或輪盤未呼喚的情況，請閱讀完整排查手冊：

👉 **[疑難排解與常見問題 (docs/TROUBLESHOOTING.md)](docs/TROUBLESHOOTING.md)**

---

## 🤝 參與貢獻

誠摯歡迎任何 Issue 回報、功能構想與 Pull Request！提交代碼前請務必詳閱 **[CONTRIBUTING.md](CONTRIBUTING.md)**。

### 專案不可妥協之四大底線：
1. **完全靜音 (Total Silence)**：嚴禁加入任何音訊資源檔或呼叫任何系統音效 API。
2. **絕不開啟 Apple 原生分享彈窗**：絕不調用 `NSSharingService`。
3. **無假裝置與假進度**：網路位元進度嚴格反映實際 Socket 握手進度。
4. **維護原始設計資產**：2048×2048 原始設計資產與 Apple HIG squircle 規範受嚴格保護。

---

## 📄 授權條款與版權宣告

- **AirDrop Wheel** 主專案代碼採用 [MIT License](LICENSE) 開源。Copyright (c) 2026 Manfred Sun。
- **FormatWheel 致敬宣告**：徑向輪盤操作哲學與甩送互動參考 FormatWheel（Copyright (c) 2026 Elise616，MIT 授權）。
- **品牌資產宣告**：專案名稱「AirDrop Wheel」及 Logo 原始圖檔為創作者專屬著作資產，保留一切權利。
