# THD频率相关问题诊断报告

**日期**: 2025-11-05  
**版本**: v10诊断  
**状态**: 🔍 根因分析完成

---

## 📊 问题现象

| 频率 | 波形 | THD测量 | THD理论 | 状态 |
|------|------|---------|---------|------|
| 600kHz | 方波 | 53%±3% | 48.3% | ✅ 准确 |
| 500kHz | 正弦波 | 8.0%±3% | <1% | ⚠️ 偏高 |
| 1MHz | 方波 | 20%±1% | 48.3% | ⚠️ 偏低 |
| 20kHz | 方波 | 0.0% | 48.3% | ❌ 失败 |

---

## 🔍 根因分析

### 问题1: 20kHz方波THD=0% ❌

**根本原因**: **整数bin计算误差在低频时累积严重**

#### 当前实现（有问题）:
```verilog
// 在扫描开始时计算谐波bin
harm2_bin <= (fft_peak_bin << 1);                    // 2次 = bin×2
harm3_bin <= (fft_peak_bin << 1) + fft_peak_bin;     // 3次 = bin×3
harm4_bin <= (fft_peak_bin << 2);                    // 4次 = bin×4
harm5_bin <= (fft_peak_bin << 2) + fft_peak_bin;     // 5次 = bin×5
```

#### 误差分析:
```
频率分辨率: 35MHz / 8192 = 4272.46 Hz/bin

20kHz方波:
  基波理论bin: 20000 / 4272.46 = 4.681
  FFT检测结果: bin[4] 或 bin[5] （取决于能量分布）
  
  如果检测为bin[4]:
    3次谐波: 4×3 = 12, 理论14.04, 误差 -2.04 bin ❌
    5次谐波: 4×5 = 20, 理论23.41, 误差 -3.41 bin ❌❌
    搜索范围±3bin: [17..23] 刚好能找到bin[23]
    但3次谐波bin[12]搜索[9..15]可以找到bin[14] ✅
  
  如果检测为bin[5]:
    3次谐波: 5×3 = 15, 理论14.04, 误差 +0.96 bin ⚠️
    5次谐波: 5×5 = 25, 理论23.41, 误差 +1.59 bin ⚠️
    搜索范围±3bin: 都能找到，但边缘情况

对比600kHz (THD正常):
  基波理论bin: 600000 / 4272.46 = 140.43
  FFT检测结果: bin[140]
  
  3次谐波: 140×3 = 420, 理论421.30, 误差 -1.30 bin ✅
  5次谐波: 140×5 = 700, 理论702.17, 误差 -2.17 bin ✅
  搜索范围±3bin: 都能轻松找到
```

**结论**: 
- ✅ 高频(bin>100)时，整数倍计算误差<3bin，可以找到谐波
- ❌ 低频(bin<10)时，整数倍计算误差>3bin，谐波检测失败

---

### 问题2: 1MHz方波THD=20% (理论53.3%) ⚠️

**根本原因**: **只检测到3次和5次谐波，7次和9次未检测**

#### 方波频谱特性:
```
理想方波只有奇次谐波: 1, 3, 5, 7, 9, 11, ...
幅度比例: 1 : 1/3 : 1/5 : 1/7 : 1/9 : ...

1MHz方波THD (Nyquist=17.5MHz):
  基波: 1MHz, 幅度=1.0
  3次: 3MHz, 幅度=0.333 ✅ 检测
  5次: 5MHz, 幅度=0.200 ✅ 检测
  7次: 7MHz, 幅度=0.143 ❌ 未检测
  9次: 9MHz, 幅度=0.111 ❌ 未检测

当前代码检测: 2, 3, 4, 5次谐波
  2次: 偶次谐波=0 (方波无偶次)
  3次: 检测到 ✅
  4次: 偶次谐波=0 (方波无偶次)
  5次: 检测到 ✅

实际THD = (H3+H5)/H1 = (0.333+0.200)/1.0 = 53.3%
测量THD = 20%

差异分析:
  53.3% - 20% = 33.3% ≈ H3 (0.333)
  可能3次谐波未检测到，只检测到H5=20%
```

**结论**: 
- 1MHz×3=3MHz, bin[702], 搜索范围应该能找到
- **可能是幅度阈值问题**: 3次谐波幅度被噪声阈值过滤掉了

---

### 问题3: 500kHz正弦波THD=8% (理论<1%) ⚠️

**可能原因**:
1. **ADC非线性**: 10位ADC本身的THD性能
2. **系统噪声**: 采样电路、时钟抖动
3. **DC去除误差**: 自适应DC估计不够精确
4. **量化噪声**: FFT量化导致谐波泄漏

**需要验证**:
- 查看FFT频谱，确认8%对应的频率成分在哪里
- 是否是2/3/4/5次谐波，还是宽带噪声

---

## 🔧 修复方案

### 方案A: 精确谐波bin计算（推荐） ✅

**核心思想**: 使用基波**频率**而非bin索引计算谐波bin

```verilog
// 修改前（整数倍，误差大）:
harm2_bin <= (fft_peak_bin << 1);  // bin×2

// 修改后（频率倍数，精确）:
harm2_bin <= (fft_peak_freq_output * 2) / FREQ_RESOLUTION;  // freq×2 / resolution
```

**优势**:
- ✅ 低频高频都准确
- ✅ 利用现有的`fft_peak_freq_output`（已经是实际频率Hz）
- ✅ 不改变检测逻辑，只改计算公式

**挑战**:
- ⚠️ 除法运算：需要流水线或LUT
- ⚠️ `fft_peak_freq_output`是32位，谐波bin需要13位

**实现**:
```verilog
// 参数
localparam FREQ_RESOLUTION = 4272;  // Hz/bin (35MHz/8192)

// 谐波bin计算（流水线）
reg [31:0] harm2_freq, harm3_freq, harm4_freq, harm5_freq;
reg [31:0] harm2_bin_calc, harm3_bin_calc;

always @(posedge sys_clk) begin
    if (spectrum_addr == 13'd0) begin
        // 计算谐波频率
        harm2_freq <= fft_peak_freq_output << 1;           // ×2
        harm3_freq <= fft_peak_freq_output + (fft_peak_freq_output << 1);  // ×3
        harm4_freq <= fft_peak_freq_output << 2;           // ×4
        harm5_freq <= fft_peak_freq_output + (fft_peak_freq_output << 2);  // ×5
    end
end

always @(posedge sys_clk) begin
    // 除法（可能需要多周期或LUT）
    harm2_bin <= harm2_freq / FREQ_RESOLUTION;
    harm3_bin <= harm3_freq / FREQ_RESOLUTION;
    harm4_bin <= harm4_freq / FREQ_RESOLUTION;
    harm5_bin <= harm5_freq / FREQ_RESOLUTION;
end
```

---

### 方案B: 扩大搜索范围（临时方案）

```verilog
// 当前: ±3 bin
if (spectrum_addr >= (harm2_bin - 13'd3) && 
    spectrum_addr <= (harm2_bin + 13'd3))

// 修改: ±5 bin (低频) 或 ±10 bin
if (spectrum_addr >= (harm2_bin - 13'd10) && 
    spectrum_addr <= (harm2_bin + 13'd10))
```

**缺点**: 可能检测到相邻噪声峰值 ⚠️

---

### 方案C: 添加7次和9次谐波检测

```verilog
reg [12:0] harm7_bin, harm9_bin;
reg [15:0] harm7_amp, harm9_amp;

// 计算7次和9次bin
harm7_bin <= (fft_peak_freq_output * 7) / FREQ_RESOLUTION;
harm9_bin <= (fft_peak_freq_output * 9) / FREQ_RESOLUTION;

// THD计算包含7次和9次
thd_harmonic_sum <= fft_harmonic_2 + fft_harmonic_3 + fft_harmonic_4 + 
                    fft_harmonic_5 + fft_harmonic_7 + fft_harmonic_9;
```

**优势**: 方波THD更准确（1MHz可达78%）

---

## 📋 实施计划

### 第一步: 实现方案A（精确bin计算）
- [x] 诊断完成
- [ ] 实现频率倍数计算
- [ ] 除法流水线或LUT
- [ ] 测试20kHz方波

### 第二步: 实现方案C（7次/9次谐波）
- [ ] 添加harm7/9检测
- [ ] 修改THD求和逻辑
- [ ] 测试1MHz方波

### 第三步: 诊断正弦波THD偏高
- [ ] UART输出FFT频谱前20个bin
- [ ] 分析谐波成分分布
- [ ] 评估ADC性能

---

## 🎯 预期效果

| 频率 | 修复前 | 修复后 | 理论值 |
|------|--------|--------|--------|
| 20kHz方波 | 0.0% | ~48% | 48.3% |
| 600kHz方波 | 53%±3% | 53%±3% | 48.3% |
| 1MHz方波 | 20% | ~75% | 78.7% |
| 500kHz正弦波 | 8% | 待定 | <1% |

---

**下一步行动**: 实现精确谐波bin计算（基于频率而非bin索引）
