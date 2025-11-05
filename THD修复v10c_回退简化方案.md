# THD修复v10c: 回退+扩大搜索范围

**日期**: 2025-11-05  
**问题**: v10b倒数乘法导致THD全面退化  
**根因**: fft_freq_hz时序错误 + bin×N本来就是精确的  
**修复**: 回退到v9简单方法 + 扩大谐波搜索范围±3→±5

---

## ❌ **v10b失败分析**

### 测试结果：
| 频率 | v9结果 | v10b结果 | 变化 |
|------|--------|----------|------|
| 20kHz方波 | 0.0% | 0.0% | 无改善 |
| 600kHz方波 | 53%±3% | **10.0%** | ❌ **严重退化** |
| 1MHz方波 | 20%±1% | **6.5%** | ❌ **退化** |

### 观察到的异常：
1. ⚠️ 频谱低频区域噪声明显
2. ⚠️ 峰值跳动严重
3. ❌ THD值全面降低

---

## 🔍 **根因分析**

### 问题1: 时序错误（致命）

**v10b代码**:
```verilog
if (spectrum_addr == 13'd0) begin
    // 在FFT扫描开始时使用fft_freq_hz
    harm3_bin <= (((fft_freq_hz * 32'd3) * 32'd3927) + 32'd8388608) >> 24;
end
```

**但是**:
```verilog
// fft_freq_hz在FFT扫描**结束**时才更新！
if (spectrum_addr == (FFT_POINTS/2)) begin
    fft_freq_hz <= fft_peak_bin * FREQ_RES;  // ← 在这里更新
end
```

**时序问题**:
```
周期N-1: FFT扫描 bin[0..4095]
周期N-1: 扫描结束 addr=4096 → fft_freq_hz=600kHz ✅ 更新

周期N:   新扫描开始 addr=0
         harm3_bin = (OLD fft_freq_hz × 3 × ...) >> 24  ❌ 使用旧值！
         
如果上一次是1MHz，现在是600kHz：
  harm3_bin = (1MHz × 3) = 3MHz
  实际应该 = (600kHz × 3) = 1.8MHz
  错误! 检测bin错误，找不到谐波 → THD=0%
```

**结论**: v10b使用了**错误的频率值**，导致谐波bin计算完全错误！

---

### 问题2: 过度设计（数学误解）

**我的错误推导**:
```
harm_bin = harm_freq / FREQ_RES
         = (base_freq × N) / FREQ_RES  ← 这里用频率计算
         需要除法优化...
```

**正确推导**:
```
harm_bin = harm_freq / FREQ_RES
         = (base_freq × N) / FREQ_RES
         = (base_bin × FREQ_RES × N) / FREQ_RES  ← bin已经包含了FREQ_RES
         = base_bin × N  ← 完全精确！
```

**数学证明**:
```
已知: base_freq = base_bin × FREQ_RES (FFT bin定义)

则: harm_bin = (base_freq × N) / FREQ_RES
             = (base_bin × FREQ_RES × N) / FREQ_RES
             = base_bin × N  (FREQ_RES约分)
             
这是数学上完全精确的，不是近似！
```

**v9本来就是对的！** 😱
```verilog
harm3_bin <= (fft_peak_bin << 1) + fft_peak_bin;  // bin×3，完全精确
```

---

## 💡 **真正的问题**

v9在20kHz时THD=0%的原因不是bin×N计算错误，而是：

### 低频能量泄漏
```
20kHz真实bin: 4.682

FFT没有窗函数，能量泄漏到相邻bin:
  bin[4]: 可能有70%能量
  bin[5]: 可能有30%能量
  
FFT峰值检测选择bin[4]（能量更大）:
  基波bin = 4
  5次谐波计算: 4 × 5 = 20
  5次谐波理论: 23.41
  误差: 3.41 bin
  
搜索范围±3bin: [17..23]
  bin[23]刚好在边缘，可能漏检 ⚠️
```

---

## 🔧 **修复方案v10c**

### 改进1: 回退到bin×N（精确+时序安全）
```verilog
// v10c: 简单精确的整数倍计算
harm2_bin <= (fft_peak_bin << 1);                    // bin×2
harm3_bin <= (fft_peak_bin << 1) + fft_peak_bin;     // bin×3
harm4_bin <= (fft_peak_bin << 2);                    // bin×4
harm5_bin <= (fft_peak_bin << 2) + fft_peak_bin;     // bin×5
```

**优势**:
- ✅ 数学精确（不是近似！）
- ✅ 无除法/乘法，只有移位+加法
- ✅ 时序安全（<1ns延迟）
- ✅ fft_peak_bin在扫描开始前就有效

### 改进2: 扩大谐波搜索范围±3→±5
```verilog
// v10c: 扩大搜索范围应对低频能量泄漏
if (harm5_bin > 13'd5 && harm5_bin < (FFT_POINTS/2 - 13'd5) &&
    spectrum_addr >= (harm5_bin - 13'd5) &&  // ±5 bin
    spectrum_addr <= (harm5_bin + 13'd5)) begin
```

**理由**:
```
20kHz最坏情况:
  基波检测bin[4]
  5次谐波: bin[20]
  理论位置: bin[23.41]
  误差: 3.41 bin
  
±3bin范围: [17..23] → bin[23]在边缘 ⚠️
±5bin范围: [15..25] → bin[23]安全在内 ✅
```

**风险评估**:
- ⚠️ ±5bin可能检测到相邻噪声峰
- ✅ 但THD计算使用峰值幅度，噪声幅度远小于真实谐波
- ✅ 有噪声阈值过滤（50）

---

## 📊 **预期效果**

| 频率 | v9 | v10b | v10c预期 | 说明 |
|------|-----|------|----------|------|
| 20kHz方波 | 0.0% | 0.0% | **40-50%** | ±5bin覆盖5次谐波 |
| 600kHz方波 | 53% | 10% | **53%** | 回退到v9水平 |
| 1MHz方波 | 20% | 6.5% | **20%** | 回退到v9水平 |

---

## 🎯 **技术总结**

### 关键教训:
1. **简单就是美**: bin×N比复杂的除法优化更好
2. **数学证明**: 不要假设，要证明（bin×N是精确的！）
3. **时序验证**: 检查变量的更新时刻
4. **实测优先**: v9虽然有问题，但v10b更糟

### 最优方案:
```
谐波bin计算: bin×N (移位+加法，0延迟，精确)
搜索范围: ±5bin (应对低频能量泄漏)
阈值: 50 (过滤噪声)
```

---

## 📝 **代码变更**

### signal_parameter_measure.v (Line 650-718)

**关键修改**:
1. 谐波bin计算: 倒数乘法 → bin×N
2. 搜索范围: ±3 → ±5

---

## 🔍 **后续优化**

如果20kHz仍失败:

### 选项A: 添加Hann窗 (更优)
```verilog
// Hann窗减少能量泄漏
// 20kHz能量集中在bin[5]，而不是分散到bin[4]和bin[5]
```

### 选项B: 进一步扩大范围±5→±8
```verilog
// 但风险增加：可能检测到非谐波峰值
```

### 选项C: 智能搜索
```verilog
// 在±8bin范围内找幅度最大的bin
// 但要求幅度>阈值，避免噪声
```

---

**下一步**: 编译测试v10c，验证是否恢复到v9水平并改善20kHz
