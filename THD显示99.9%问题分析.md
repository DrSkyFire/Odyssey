# THD显示99.9%问题分析与修复

## 🎉 重大突破

**THD计算链路已经工作了！** 显示99.9%说明：
- ✅ FFT正常工作
- ✅ 谐波检测正常
- ✅ THD触发正常
- ✅ 流水线执行正常
- ✅ LUT查表正常
- ✅ 显示模块正常

**问题**：THD计算**数值错误**，结果被限幅到999（99.9%）

---

## 🔍 问题根因

### 测试条件
- 输入：500kHz方波，3Vpp
- 显示：THD = 99.9%
- 预期：THD ≈ 40-55%（方波典型值）

### 代码分析

**THD计算公式**：
```
THD = (谐波和 × 1000) / 基波幅度
    = 谐波和 × (1000 / 基波幅度)
    = 谐波和 × 倒数[从LUT查找]
```

**问题1：LUT索引计算错误**
```verilog
// signal_parameter_measure.v 行1430
if (fundamental_power[15:8] != 8'd0)
    thd_lut_index <= fundamental_power[15:8];  // 取高8位
else
    thd_lut_index <= 8'd1;  // 最小值
```

**场景分析**：

假设500kHz方波的FFT幅度较小（可能因为频率较低、Hann窗被禁用等）：

| fft_max_amp | fundamental_power | thd_lut_index | 倒数值 | 效果 |
|-------------|-------------------|---------------|--------|------|
| 50 | 50 | 1 | 4000 | 除以64（256/4000×1024），**严重放大** |
| 100 | 100 | 1 | 4000 | 除以64，**严重放大** |
| 200 | 200 | 1 | 4000 | 除以64，**严重放大** |
| 500 | 500 | 1 | 4000 | 除以64，**放大** |
| 1000 | 1000 | 3 | 1333 | 除以192，仍然偏小 |
| 5000 | 5000 | 19 | ~200 | 接近正确 |

**问题2：LUT数值范围不足**

LUT设计用于`fft_max_amp > 256`的情况，对于小幅度信号：
- `thd_lut_index = 1` → 倒数4000
- 实际应该是 `1024000 / 50 = 20480`（如果fft_max_amp=50）
- **误差高达5倍！**

---

## 🐞 为什么会显示99.9%？

### 计算示例（假设）

**假设值**（500kHz方波）：
```
fft_max_amp = 200（基波幅度）
fft_harmonic_2 = 10
fft_harmonic_3 = 60（3次谐波）
fft_harmonic_4 = 5
fft_harmonic_5 = 40（5次谐波）

谐波和 = 10 + 60 + 5 + 40 = 115
```

**错误计算**：
```
thd_lut_index = 200 >> 8 = 0 → 强制为1
thd_reciprocal = 4000（从LUT查表）

thd_product = 115 × 4000 = 460,000
thd_calc = 460,000 >> 10 = 449

但这被滤波器平均，如果某些值更大，可能达到999
或者谐波和实际更大（比如H3=150），导致：
thd_product = 200 × 4000 = 800,000 >> 10 = 781
经过滤波可能接近999，触发限幅
```

**正确计算应该是**：
```
THD = (115 / 200) × 1000 = 575（57.5%）
```

---

## ✅ 修复方案

### 方案1：修正LUT索引计算（推荐）

**问题**：当`fft_max_amp < 256`时，索引计算错误

**修复**：改用全范围映射
```verilog
// 修改前（行1430-1437）
if (fundamental_power[31:16] != 16'd0)
    thd_lut_index <= 8'd255;
else if (fundamental_power[15:8] != 8'd0)
    thd_lut_index <= fundamental_power[15:8];
else
    thd_lut_index <= 8'd1;

// 修改后：使用更精确的映射
if (fundamental_power > 32'd65280)  // 65280 = 255×256
    thd_lut_index <= 8'd255;  // 饱和
else if (fundamental_power > 32'd256)
    thd_lut_index <= fundamental_power[15:8];  // 正常范围
else if (fundamental_power > 32'd100)
    // 小幅度信号：线性映射到1-10范围
    thd_lut_index <= fundamental_power[7:4] + 8'd1;  // 除以16
else
    thd_lut_index <= 8'd1;  // 最小值保护
```

---

### 方案2：扩展LUT覆盖小幅度（更精确）

**问题**：当前LUT对小幅度信号（<256）覆盖不足

**修复**：添加更多LUT条目
```verilog
case (thd_lut_index)
    // 新增：小幅度信号支持
    8'd1:   thd_reciprocal <= 20'd4000;     // 1024000/256
    8'd2:   thd_reciprocal <= 20'd2000;     // 1024000/512
    8'd3:   thd_reciprocal <= 20'd1333;     // 1024000/768
    8'd4:   thd_reciprocal <= 20'd1000;     // 1024000/1024
    8'd5:   thd_reciprocal <= 20'd800;      // 1024000/1280
    8'd6:   thd_reciprocal <= 20'd667;      // 1024000/1536
    8'd7:   thd_reciprocal <= 20'd571;      // 1024000/1792
    8'd8:   thd_reciprocal <= 20'd500;      // 1024000/2048
    // ... 继续到255
```

---

### 方案3：直接除法（简单但可能有时序问题）

**修复**：用实际除法替代LUT
```verilog
// 流水线第2级：直接计算
if (thd_pipe_valid[1]) begin
    // thd_calc = (谐波和 × 1000) / 基波幅度
    // 防止溢出：先检查
    if (fundamental_power > 32'd0)
        thd_calc <= (thd_harmonic_sum * 32'd1000) / fundamental_power;
    else
        thd_calc <= 16'd0;
        
    // 限幅
    if (thd_calc > 16'd1000)
        thd_calc <= 16'd1000;
end
```

⚠️ **注意**：除法可能导致时序违例，需要测试

---

## 🧪 紧急验证方法

### 不修改代码，先验证假设

通过改变输入幅度测试：

| 测试 | 输入信号 | 预测THD显示 | 说明 |
|------|----------|-------------|------|
| 1 | 500kHz方波 1Vpp | 99.9% | 幅度更小，问题更严重 |
| 2 | 500kHz方波 5Vpp | <99.9% | 幅度更大，问题减轻 |
| 3 | 1MHz方波 3Vpp | <99.9% | 频率高，FFT幅度可能更大 |

**如果测试2和3显示THD降低，则确认是小幅度问题**

---

## 🚀 推荐修复（立即可用）

### 修复代码（方案1+限幅增强）

修改`signal_parameter_measure.v`第1428-1437行：

```verilog
// 流水线第0级：基波幅度归一化到8位索引（256级）
if (thd_calc_trigger && fundamental_power > 32'd100) begin
    // 【修复】改进索引计算，更精确地映射全范围
    if (fundamental_power > 32'd65280)  // 65280 = 255×256
        thd_lut_index <= 8'd255;  // 饱和到最大
    else if (fundamental_power >= 32'd256)
        thd_lut_index <= fundamental_power[15:8];  // 高8位（正常范围）
    else begin
        // 小幅度信号：fundamental_power在100-255范围
        // 映射到索引1-10（避免过度放大）
        // index = (fundamental_power / 16) 确保至少为1
        if (fundamental_power >= 32'd160)
            thd_lut_index <= 8'd10;  // ~1024000/2560 = 400
        else if (fundamental_power >= 32'd128)
            thd_lut_index <= 8'd8;   // ~1024000/2048 = 500
        else
            thd_lut_index <= fundamental_power[7:4] + 8'd1;  // 除以16，范围6-15
    end
```

---

## 📊 修复后预期

### 500kHz方波，3Vpp
- 当前：THD = 99.9%
- 修复后：THD = 40-60%

### 1MHz方波，3Vpp  
- 当前：可能也接近99.9%
- 修复后：THD = 40-55%

### 正弦波（任何频率）
- 当前：可能>50%
- 修复后：THD < 5%

---

## 🎯 调试建议

在UART输出中添加更多调试信息：

**新增字段**：
```
FBASE:____ (fundamental_power实际值)
INDEX:___ (thd_lut_index值)
RECIP:____ (thd_reciprocal值)
```

这样可以确认问题是否在LUT索引计算。

---

## 💡 为什么之前修复无效？

回顾之前的7次修复：
1. ✅ THD滤波器时序 → 修复了滤波器，但计算值本身错误
2. ✅ 基波门限降低 → 允许更多信号触发，但计算错误
3. ✅ 谐波门限降低/禁用 → 谐波能检测到，但计算放大了
4. ✅ 谐波bin时序 → 修复了检测，但计算错误
5. ✅ 禁用Hann窗 → 增加了谐波幅度，但LUT索引不匹配
6. ✅ THD触发逻辑 → 允许重复计算，但每次都算错
7. ✅ 完全禁用谐波门限 → 谐波全部通过，但被错误放大

**核心问题**：LUT索引计算假设`fft_max_amp > 256`，但实际可能更小！

---

**立即修复此问题，THD应该就能正常显示了！** 🎯

修改日期：2025年11月5日  
版本：THD修复v7（LUT索引修复）  
优先级：P0（最高）
