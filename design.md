# AirDrop Wheel 2 — 產品與技術架構規格 (design.md)

## 1. 專案識別與位置

- **專案名稱**：AirDrop Wheel 2
- **應用程式名稱**：AirDrop Wheel 2
- **專案根目錄**：`/Users/muffin/Documents/AI Projects/Airdrop wheel 2`（單一根目錄，無任何多餘外層或重複包裝目錄）
- **Bundle Identifier**：`app.airdropwheel2.macos`
- **目標平台**：macOS 14.0+（支援 Apple Silicon 及 Intel 通用架構）
- **程式語言**：Swift 5.0（Xcode 27.2+）
- **應用程式類型**：一般 macOS 應用程式（Regular Activation Policy），執行時於 Dock 呈現圖示、支援 ⌘Tab 切換，並於系統選單列常駐快速控制入口。

---

## 2. 應用程式 Logo 與 AppIcon 規範

- **原始設計資產**：`Design/Logo/magnific__design-a-minimalist-japaneseinspired-logo-for-a-ma__78247.png`
  - 尺寸：2048 × 2048 像素
  - SHA-256：`9e09973b22ec3fb6d141abbc4d5ffd2083856b164859d65f9ca4957ec037f390`
  - 配色：米白色背景（約 `#FEF6EA`）及深藍色四分圓（約 `#003D6C`）。
- **資產保護原則**：
  - **嚴格保留原始圖案比例、顏色及幾何結構**，絕不使用 AI 重新繪製、濾鏡或替代圖形。
  - 原圖永遠保留於專案作為設計依據。
- **macOS AppIcon 生成規範**：
  - 由 `scripts/make_app_icon.swift` 腳本透過 CoreGraphics 高品質插值等比縮放輸出。
  - 依 Apple macOS HIG 標準圖示格線（1024 畫布內繪製 824×824 連續曲率圓角 squircle，外圍預留 100 像素透明邊距）。
  - 完整涵蓋 `16x16` 至 `512x512@2x`（1024x1024）共 10 個規格插槽，編譯至 `Assets.xcassets/AppIcon`。

---

## 3. UI / UX 與操作設計

- **傳承 FormatWheel 互動體驗**：
  - 檔案拖曳與快速叫出：支援選取或拖曳檔案時透過 ⌃ Control 鍵在游標位置彈出徑向輪盤。
  - 扇區與 Hub 動態：扇區具備 Hover 高亮、外弧光暈；中心 Hub 動態放大顯示目標裝置名稱與圖示。
  - 視窗管理：輪盤採輕量層次浮動面板，平滑彈性縮放浮現，支援滾輪、Tab / Q / E 快速切換裝置分頁。
- **完全靜音（Total Silence）**：
  - **全專案零音效**：不包含任何音效檔案（無 wav / mp3 / aiff 等音訊資源）。
  - **零音訊 API 與框架連結**：不呼叫 `NSSound`、`AVAudioPlayer`、`AVAudioEngine`、`AudioServicesPlaySystemSound`、`NSBeep`，不連結 `AVFoundation` 或 `AudioToolbox` 等音訊框架。

---

## 4. AirDrop 技術架構（方案 A：全新純 Swift 混合架構）

全面重寫傳送架構，摒除舊版多層 FFI 繁複性，改以原生 Swift 與 `Network.framework` 實作：

```text
WheelUI（FormatWheel 風格，完全靜音）
   │
TransferCoordinator（狀態機：pending → asking → accepted → uploading → completed / declined / failed / cancelled）
   │
AirDropEngine 協定介面
   ├─ Discovery 模組
   │    ├─ Wake：macOS 背景 AirDrop 瀏覽（非公開接口，無 UI；獨立封裝並偵測可用性）
   │    └─ DNS-SD：NWBrowser _airdrop._tcp + includePeerToPeer → 解析 [fe80::…%awdl0]:port
   └─ Transport 模組（純 Swift，基於 Network.framework）
        ├─ TLS：原生 TLS 握手，固定 /Discover 觀察到的葉憑證 (Leaf Certificate Pinning) 供後續連線驗證
        ├─ POST /Discover → 取得接收端型號、名稱與支援協定
        ├─ POST /Ask      → 接收端原生彈出同意對話框
        └─ POST /Upload   → 串流 CPIO 打包 + 64 KiB DVZip 分塊傳輸，維持常數記憶體邊界 (Bounded Memory)
```

---

## 5. 安全界線與不可妥協之產品底線

1. **絕不開啟 Apple 原生 AirDrop 分享視窗**：不調用 `NSSharingService`，無外部彈窗干擾。
2. **保留接收方原生同意**：所有傳輸嚴格等待對方在原生 iOS / macOS 畫面上按下「接受」後才開始上傳資料。
3. **無假裝置與假進度**：搜尋中、空裝置、傳輸失敗、拒絕或連線逾時均如實呈現於介面，嚴禁假進度條。
4. **目標模式與身份誠實聲明**：
   - 僅支援接收端開啟「所有人（10 分鐘）」模式。
   - 透過 TLS 葉憑證固定（Certificate Pinning）確保同一發送任務之多條連線維持同一對端，防止中間人置換金鑰；但此技術不等於 Apple 根憑證鏈之 Apple ID 密碼學身分認證。UI 必須清晰標註「未驗證身份」。
5. **合規與安全**：
   - 嚴禁停用 SIP、修改系統 TCC 資料庫、提取 Keychain 身份私鑰或注入系統行程。
   - 嚴禁在日誌中記錄私人檔案路徑、檔案內容或裝置隱私辨識碼。
6. **專案與授權獨立**：
   - FormatWheel 原專案（`/Users/muffin/Documents/AI Projects/FormatWheel-main`）及舊版 AirDrop Wheel（`/Users/muffin/Documents/AI Projects/Airdrop Wheel`）保持原樣，嚴禁修改。
   - 參考 FormatWheel 代碼時，完整保留 MIT 授權聲明。
   - OpenDrop（GPL-3.0）僅供協定理論分析，嚴禁任何代碼引入。
