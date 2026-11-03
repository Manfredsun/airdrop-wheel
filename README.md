# AirDrop Wheel 2

AirDrop Wheel 2 是一款結合 FormatWheel 徑向輪盤操作哲學與原生 AirDrop 點對點傳輸的 macOS 應用程式。

## 特色

- **FormatWheel 互動體驗**：拖曳檔案直覺甩入扇區完成發送。
- **全新純 Swift AirDrop 引擎**：以原生 `Network.framework` 與 AWDL 協定進行高效能、有界記憶體的串流分塊傳輸。
- **完全靜音（Total Silence）**：零音效干擾，打造純粹高效的操作流程。
- **極簡極致 Logo**：經典米白背景與深藍幾何四分圓視覺。

## 專案位置與識別

- **專案根目錄**：`/Users/muffin/Documents/AI Projects/Airdrop wheel 2`
- **Bundle Identifier**：`app.airdropwheel2.macos`
- **App 名稱**：AirDrop Wheel 2

## 建置與執行

本專案使用原生 Xcode 專案結構，無需第三方套件管理工具：

```bash
# Debug 建置
xcodebuild -project "AirDrop Wheel 2.xcodeproj" -scheme "AirDrop Wheel 2" -configuration Debug build

# Release 建置
xcodebuild -project "AirDrop Wheel 2.xcodeproj" -scheme "AirDrop Wheel 2" -configuration Release build
```

產物將位於：
`build/DerivedData/Build/Products/Release/AirDrop Wheel 2.app`

## 設計資產

原始 Logo 保留於 `Design/Logo/magnific__design-a-minimalist-japaneseinspired-logo-for-a-ma__78247.png`。
如需重新生成 AppIcon 資產，可執行：

```bash
swift scripts/make_app_icon.swift
```

## 授權與宣告

- 本專案架構與規範詳見 `design.md`。
- FormatWheel UI 參考保留原 MIT 授權（Copyright (c) 2026 Elise616）。
