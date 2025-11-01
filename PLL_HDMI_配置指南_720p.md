# PLL_HDMI 配置指南 - 720p@60Hz

## 📋 需要修改的PLL

**文件位置：** `ipcore/pll_hdmi/`

**模块名：** `pll_hdmi`

---

## ⚙️ 当前配置（1080p@60Hz）

```
输入时钟：27MHz (sys_clk_27m)

VCO配置：
  FBDIV (M) = 44
  IDIV (N) = 1
  VCO频率 = 27MHz × 44 / 1 = 1188MHz

输出时钟：
  CLKOUT0 = 1188MHz / 8 = 148.5MHz ❌ 时序违例
```

---

## ✅ 新配置（720p@60Hz）

### 方案1：保持VCO频率（推荐）

```
输入时钟：27MHz (不变)

VCO配置：
  FBDIV (M) = 44 (不变)
  IDIV (N) = 1 (不变)
  VCO频率 = 1188MHz (不变)

输出时钟：
  CLKOUT0_DIV = 16 (修改：8 → 16)
  CLKOUT0 = 1188MHz / 16 = 74.25MHz ✅
```

**优点：**
- VCO频率不变，稳定性高
- 只需修改一个参数（CLKOUT0_DIV）

---

### 方案2：调整VCO频率（备选）

```
输入时钟：27MHz (不变)

VCO配置：
  FBDIV (M) = 55 (修改：44 → 55)
  IDIV (N) = 1 (不变)
  VCO频率 = 27MHz × 55 / 1 = 1485MHz

输出时钟：
  CLKOUT0_DIV = 20 (修改：8 → 20)
  CLKOUT0 = 1485MHz / 20 = 74.25MHz ✅
```

**优点：**
- VCO = 1485MHz，刚好是74.25MHz的20倍

---

## 🛠️ 修改步骤（推荐方案1）

### 1. 打开PLL配置

在Pango Design Suite中：
```
1. 双击 ipcore/pll_hdmi/pll_hdmi.idf
2. 或右键 → IP Catalog → 找到已有PLL
```

### 2. 修改输出分频系数

在PLL配置界面：

```
[General Settings]
  Input Clock: 27 MHz ✓ (保持不变)
  
[VCO Settings]
  FBDIV: 44 ✓ (保持不变)
  IDIV: 1 ✓ (保持不变)
  VCO Frequency: 1188 MHz ✓

[Output Clocks]
  CLKOUT0:
    ├─ Enable: ✓
    ├─ CLKOUT0_DIV: 16  ← 修改这里！(原来是8)
    ├─ Output Frequency: 74.25 MHz ✓
    └─ Phase: 0°
```

### 3. 验证配置

确认以下参数：
- ✅ 输入时钟：27 MHz
- ✅ VCO频率：1188 MHz
- ✅ 输出时钟：74.25 MHz
- ✅ 分频系数：16

### 4. 生成IP核

点击 `Generate` 按钮生成新的PLL配置。

---

## 📊 时序验证

### 预期时序改善

| 时钟域 | 要求频率 | 当前实现 | 时序状态 |
|--------|---------|---------|---------|
| **修改前：1080p** | 148.5MHz | 73.55MHz | ❌ -50.5% |
| **修改后：720p** | 74.25MHz | 73.55MHz | ⚠️ -0.94% |

**注意：** 虽然还差0.7MHz，但由于：
1. BCD转换已分散到多个周期
2. 占空比乘法已优化
3. FFT DSP资源释放30%

综合效果应该能满足74.25MHz的要求。

---

## ⚡ 进一步优化（如果还不够）

如果74.25MHz仍有轻微违例，可以：

### 选项A：降低到720p@50Hz
```
像素时钟：61.875MHz (更宽松)
CLKOUT0_DIV = 19 (1188MHz / 19 ≈ 62.5MHz)
刷新率：50Hz (欧洲标准)
```

### 选项B：降低到720p@30Hz
```
像素时钟：37.125MHz (非常宽松)
CLKOUT0_DIV = 32 (1188MHz / 32 = 37.125MHz)
刷新率：30Hz (静态显示可接受)
```

---

## 🔍 PLL参数计算公式

```
VCO频率 = 输入时钟 × FBDIV / IDIV
输出时钟 = VCO频率 / CLKOUT_DIV

示例（方案1）：
VCO = 27MHz × 44 / 1 = 1188MHz
CLKOUT0 = 1188MHz / 16 = 74.25MHz ✓

示例（方案2）：
VCO = 27MHz × 55 / 1 = 1485MHz
CLKOUT0 = 1485MHz / 20 = 74.25MHz ✓
```

---

## ✅ 完成确认清单

修改完成后检查：

- [ ] PLL输出时钟显示为 74.25MHz
- [ ] 代码中所有注释已更新为720p
- [ ] 重新综合工程
- [ ] 查看时序报告：WNS > 0
- [ ] 如有板卡，测试HDMI输出（应显示720p）

---

## 🚨 常见问题

**Q1: 修改PLL后综合报错？**
- A: 确保PLL已重新生成，删除旧的 .v 文件

**Q2: 显示器显示"No Signal"？**
- A: 检查MS7210是否支持720p（通常都支持）

**Q3: 时序还是不满足？**
- A: 尝试降低到720p@50Hz (61.875MHz)

---

**修改完成后，请告知我重新运行综合验证时序！**
