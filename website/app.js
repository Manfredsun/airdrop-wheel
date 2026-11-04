/* ==========================================================================
   AirDrop Wheel — 互動展示模擬器與網頁核心邏輯 (app.js)
   ========================================================================== */

document.addEventListener("DOMContentLoaded", () => {
  initTheme();
  initRadialWheel();
  initDragAndDrop();
  initTabs();
  initCopyButton();
});

/* --------------------------------------------------------------------------
   1. 深淺色模式切換 (Theme Toggle)
   -------------------------------------------------------------------------- */
function initTheme() {
  const toggleBtn = document.getElementById("theme-toggle");
  const html = document.documentElement;
  const savedTheme = localStorage.getItem("airdrop-wheel-theme");

  if (savedTheme) {
    html.setAttribute("data-theme", savedTheme);
  }

  toggleBtn.addEventListener("click", () => {
    const currentTheme = html.getAttribute("data-theme");
    const nextTheme = currentTheme === "dark" ? "light" : "dark";
    html.setAttribute("data-theme", nextTheme);
    localStorage.setItem("airdrop-wheel-theme", nextTheme);
  });
}

/* --------------------------------------------------------------------------
   2. 8 扇區 SVG 徑向輪盤生成器 (Radial Wheel Generator)
   -------------------------------------------------------------------------- */
const RECIPIENTS = [
  { name: "Manfred 的 iPhone", glyph: "📱", model: "iPhone 16 Pro" },
  { name: "錄音室 MacBook Pro", glyph: "💻", model: "M3 Max" },
  { name: "客廳 iPad Pro", glyph: "📱", model: "iPad Pro M4" },
  { name: "辦公室 Mac mini", glyph: "🖥️", model: "M2 Pro" },
  { name: "設計師 MacBook Air", glyph: "💻", model: "M3" },
  { name: "訪客 iPhone", glyph: "📱", model: "iPhone 15" },
  { name: "Studio Display Mac", glyph: "🖥️", model: "Mac Studio" },
  { name: "附近新裝置", glyph: "🔍", model: "搜尋中..." }
];

let activeSectorIndex = -1;

function initRadialWheel() {
  const sectorsGroup = document.getElementById("sectors-group");
  if (!sectorsGroup) return;

  const numSectors = 8;
  const outerR = 245;
  const innerR = 86;
  const sectorAngle = (2 * Math.PI) / numSectors;

  sectorsGroup.innerHTML = "";

  for (let i = 0; i < numSectors; i++) {
    const startAngle = i * sectorAngle - Math.PI / 2 - sectorAngle / 2;
    const endAngle = startAngle + sectorAngle;

    const pathData = createSectorPath(0, 0, innerR, outerR, startAngle, endAngle);

    const path = document.createElementNS("http://www.w3.org/2000/svg", "path");
    path.setAttribute("d", pathData);
    path.setAttribute("class", "wheel-sector");
    path.setAttribute("data-index", i);
    path.id = `sector-${i}`;

    const midAngle = (startAngle + endAngle) / 2;
    const midR = (innerR + outerR) / 2;
    const textX = midR * Math.cos(midAngle);
    const textY = midR * Math.sin(midAngle);

    const glyph = document.createElementNS("http://www.w3.org/2000/svg", "text");
    glyph.setAttribute("x", textX);
    glyph.setAttribute("y", textY - 8);
    glyph.setAttribute("class", "wheel-sector-glyph");
    glyph.textContent = RECIPIENTS[i].glyph;

    const label = document.createElementNS("http://www.w3.org/2000/svg", "text");
    label.setAttribute("x", textX);
    label.setAttribute("y", textY + 12);
    label.setAttribute("class", "wheel-sector-label");
    label.textContent = truncateString(RECIPIENTS[i].name, 10);

    sectorsGroup.appendChild(path);
    sectorsGroup.appendChild(glyph);
    sectorsGroup.appendChild(label);

    path.addEventListener("mouseenter", () => selectSector(i));
    path.addEventListener("mouseleave", () => unselectSector(i));
  }
}

function createSectorPath(cx, cy, rInner, rOuter, startAngle, endAngle) {
  const x1 = cx + rOuter * Math.cos(startAngle);
  const y1 = cy + rOuter * Math.sin(startAngle);
  const x2 = cx + rOuter * Math.cos(endAngle);
  const y2 = cy + rOuter * Math.sin(endAngle);

  const x3 = cx + rInner * Math.cos(endAngle);
  const y3 = cy + rInner * Math.sin(endAngle);
  const x4 = cx + rInner * Math.cos(startAngle);
  const y4 = cy + rInner * Math.sin(startAngle);

  return [
    `M ${x1} ${y1}`,
    `A ${rOuter} ${rOuter} 0 0 1 ${x2} ${y2}`,
    `L ${x3} ${y3}`,
    `A ${rInner} ${rInner} 0 0 0 ${x4} ${y4}`,
    "Z"
  ].join(" ");
}

function truncateString(str, maxLen) {
  return str.length > maxLen ? str.slice(0, maxLen - 1) + "…" : str;
}

function selectSector(index) {
  if (index < 0 || index >= RECIPIENTS.length) return;
  activeSectorIndex = index;

  document.querySelectorAll(".wheel-sector").forEach((el, idx) => {
    if (idx === index) {
      el.classList.add("active");
    } else {
      el.classList.remove("active");
    }
  });

  const hubDefault = document.getElementById("hub-default");
  const hubActive = document.getElementById("hub-active");
  const hubTargetGlyph = document.getElementById("hub-target-glyph");
  const hubTargetName = document.getElementById("hub-target-name");

  if (hubDefault && hubActive) {
    hubDefault.style.display = "none";
    hubActive.style.display = "flex";
    hubTargetGlyph.textContent = RECIPIENTS[index].glyph;
    hubTargetName.textContent = RECIPIENTS[index].name;
  }
}

function unselectSector(index) {
  if (activeSectorIndex === index) {
    activeSectorIndex = -1;
  }
  const sectorEl = document.getElementById(`sector-${index}`);
  if (sectorEl) sectorEl.classList.remove("active");

  const hubDefault = document.getElementById("hub-default");
  const hubActive = document.getElementById("hub-active");

  if (activeSectorIndex === -1 && hubDefault && hubActive) {
    hubDefault.style.display = "flex";
    hubActive.style.display = "none";
  }
}

/* --------------------------------------------------------------------------
   3. 檔案拖曳手勢引擎 (Drag & Drop Engine)
   -------------------------------------------------------------------------- */
function initDragAndDrop() {
  const draggableFile = document.getElementById("draggable-file");
  const wheelStage = document.getElementById("wheel-stage");

  if (!draggableFile || !wheelStage) return;

  draggableFile.addEventListener("dragstart", (e) => {
    e.dataTransfer.setData("text/plain", "專案提案簡報.pdf");
    e.dataTransfer.effectAllowed = "copy";
  });

  wheelStage.addEventListener("dragover", (e) => {
    e.preventDefault();
    e.dataTransfer.dropEffect = "copy";
    detectSectorFromCoords(e.clientX, e.clientY);
  });

  wheelStage.addEventListener("dragleave", () => {
    if (activeSectorIndex !== -1) {
      unselectSector(activeSectorIndex);
    }
  });

  wheelStage.addEventListener("drop", (e) => {
    e.preventDefault();
    if (activeSectorIndex !== -1) {
      triggerTransferSimulation(RECIPIENTS[activeSectorIndex]);
    }
  });

  // 行動裝置觸控支援
  draggableFile.addEventListener("touchmove", (e) => {
    const touch = e.touches[0];
    detectSectorFromCoords(touch.clientX, touch.clientY);
  });

  draggableFile.addEventListener("touchend", () => {
    if (activeSectorIndex !== -1) {
      triggerTransferSimulation(RECIPIENTS[activeSectorIndex]);
    }
  });
}

function detectSectorFromCoords(clientX, clientY) {
  const wheelStage = document.getElementById("wheel-stage");
  if (!wheelStage) return;

  const rect = wheelStage.getBoundingClientRect();
  const centerX = rect.left + rect.width / 2;
  const centerY = rect.top + rect.height / 2;

  const dx = clientX - centerX;
  const dy = clientY - centerY;
  const distance = Math.sqrt(dx * dx + dy * dy);

  // 中心死區 (Deadzone)
  if (distance < 75 || distance > 260) {
    if (activeSectorIndex !== -1) {
      unselectSector(activeSectorIndex);
    }
    return;
  }

  // 極坐標角度計算
  let angle = Math.atan2(dy, dx);
  const sectorAngle = (2 * Math.PI) / 8;
  let normalizedAngle = angle + Math.PI / 2 + sectorAngle / 2;
  if (normalizedAngle < 0) normalizedAngle += 2 * Math.PI;
  normalizedAngle = normalizedAngle % (2 * Math.PI);

  const sectorIndex = Math.floor(normalizedAngle / sectorAngle);
  if (sectorIndex >= 0 && sectorIndex < 8 && sectorIndex !== activeSectorIndex) {
    selectSector(sectorIndex);
  }
}

/* --------------------------------------------------------------------------
   4. 靜音傳送進度 HUD 模擬器
   -------------------------------------------------------------------------- */
let isTransferring = false;

function triggerTransferSimulation(recipient) {
  if (isTransferring) return;
  isTransferring = true;

  const hud = document.getElementById("demo-hud");
  const hudStatusText = document.getElementById("hud-status-text");
  const hudProgressBar = document.getElementById("hud-progress-bar");
  const hudPercent = document.getElementById("hud-percent");
  const hudSpeed = document.getElementById("hud-speed");

  if (!hud) return;

  hud.style.display = "block";
  hudStatusText.textContent = `正在連線至 ${recipient.name}...`;
  hudProgressBar.style.width = "0%";
  hudPercent.textContent = "0%";
  hudSpeed.textContent = "TLS 葉憑證鎖定驗證中...";

  let progress = 0;
  const interval = setInterval(() => {
    progress += Math.floor(Math.random() * 15) + 12;
    if (progress > 100) progress = 100;

    hudProgressBar.style.width = `${progress}%`;
    hudPercent.textContent = `${progress}%`;
    hudStatusText.textContent = `正在透過 AWDL 串流至 ${recipient.name}...`;
    hudSpeed.textContent = `${(Math.random() * 12 + 45).toFixed(1)} MB/s`;

    if (progress === 100) {
      clearInterval(interval);
      hudStatusText.textContent = `✓ 已成功發送至 ${recipient.name}`;
      hudSpeed.textContent = "傳輸完成（完全靜音）";

      setTimeout(() => {
        hud.style.display = "none";
        isTransferring = false;
        if (activeSectorIndex !== -1) {
          unselectSector(activeSectorIndex);
        }
      }, 2500);
    }
  }, 120);
}

/* --------------------------------------------------------------------------
   5. 安裝切換標籤 (Installation Tabs)
   -------------------------------------------------------------------------- */
function initTabs() {
  const tabs = document.querySelectorAll(".tab-btn");
  tabs.forEach((tab) => {
    tab.addEventListener("click", () => {
      tabs.forEach((t) => t.classList.remove("active"));
      tab.classList.add("active");

      const targetPane = tab.getAttribute("data-tab");
      document.querySelectorAll(".tab-pane").forEach((pane) => {
        pane.style.display = pane.id === `pane-${targetPane}` ? "block" : "none";
      });
    });
  });
}

/* --------------------------------------------------------------------------
   6. 複製指令按鈕 (Copy Command Button)
   -------------------------------------------------------------------------- */
function initCopyButton() {
  const copyBtn = document.getElementById("copy-btn");
  const copyLabel = document.getElementById("copy-label");
  const installCmd = document.getElementById("install-cmd");

  if (!copyBtn || !installCmd) return;

  copyBtn.addEventListener("click", () => {
    navigator.clipboard.writeText(installCmd.textContent).then(() => {
      copyLabel.textContent = "已複製！";
      copyBtn.style.background = "#10B981";
      setTimeout(() => {
        copyLabel.textContent = "複製";
        copyBtn.style.background = "";
      }, 2000);
    });
  });
}
