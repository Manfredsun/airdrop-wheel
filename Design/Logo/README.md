# AirDrop Wheel — 應用程式 Logo 資產規範

## 原始圖案資訊

- **檔案名稱**：`magnific__design-a-minimalist-japaneseinspired-logo-for-a-ma__78247.png`
- **原始尺寸**：2048 × 2048 像素
- **色彩空間**：sRGB (8-bit per channel, RGB, 無 Alpha 通道)
- **SHA-256 校驗碼**：`9e09973b22ec3fb6d141abbc4d5ffd2083856b164859d65f9ca4957ec037f390`
- **圖案特徵**：米白色背景（約 `#FEF6EA` / RGB 254, 246, 234），中央為深藍色四分圓幾何圖形（約 `#003D6C` / RGB 0, 61, 108）。
- **圖案定位**：四分圓包圍盒位於 (582, 578) 至 (1464, 1468)，中心座標為 (1023, 1023)，完全居中，直徑佔全畫布約 43%。

## 資產保護與使用規範

1. **嚴禁重新生成或改動**：
   - 必須嚴格保留原始圖案比例、幾何線條粗細、深藍與米白色值。
   - 不得透過 AI 重新繪製、濾鏡變形或自行更換替代圖案。
2. **macOS AppIcon 生成規範**：
   - 依 Apple macOS Human Interface Guidelines (HIG) 標準圖示格線規範（1024 畫布內使用 824×824 圓角矩形區域，外圍預留 100 像素邊界透明），透過 `scripts/make_app_icon.swift` 腳本以 CoreGraphics 高品質插值等比縮放製作。
   - 裁切使用 Apple 標準連曲率圓角（continuous squircle），原圖左上角 (10, 6) 之微小瑕疵自然落在圓角之外被裁除，維持圖形純淨。
3. **保留原樣**：
   - 本目錄下的原檔作為永久設計資產保留，不得刪除或改名。
