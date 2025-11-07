# AI自动识别模块检查报告
**日期**: 2025年11月7日  
**检查对象**: 频谱仪AI信号自动识别模块  
**检查范围**: ai_signal_recognizer.v, waveform_feature_extractor.v, waveform_classifier.v

---

## 1. 模块架构总览

### 1.1 三层架构
```
ai_signal_recognizer (顶层)
    ├── waveform_feature_extractor (特征提取)
    └── waveform_classifier (决策树分类)
```

### 1.2 数据流向
```
时域信号 (11-bit ADC) ──┐
                        ├──> 特征提取器 ──> 8个特征 ──> 分类器 ──> 波形类型
FFT频谱 (16-bit幅度) ──┘                                            + 置信度
```

---

## 2. 特征提取器检查

### 2.1 ✅ 已实现的8个特征

| 特征名称 | 计算方法 | 作用 | 状态 |
|---------|---------|-----|------|
| **ZCR** (过零率) | 统计符号变化次数 | 区分周期性/噪声 | ✅ 正常 |
| **Crest Factor** (峰值因子) | Peak / RMS | 区分正弦/方波/三角波 | ✅ 正常 |
| **Form Factor** (波形因子) | RMS / 平均绝对值 | 波形形状特征 | ✅ 正常 |
| **Mean Value** (平均值) | 信号直流分量 | 检测偏置 | ✅ 正常 |
| **Std Dev** (标准差) | 能量分散程度 | 噪声/稳定性 | ✅ 正常 |
| **THD** (总谐波失真) | 谐波能量/基波 | 波形纯净度 | ✅ 正常 |
| **Spectral Centroid** (频谱质心) | 加权频率平均 | 频率集中度 | ✅ 正常 |
| **Spectral Spread** (频谱展宽) | 频率分散度 | 带宽特征 | ✅ 正常 |

### 2.2 ✅ 流水线架构优化
```verilog
IDLE → COLLECTING (1024点) → COMPUTE1 → COMPUTE2 → COMPUTE3A → COMPUTE3B → COMPUTE4 → OUTPUT
        ^                     准备数据   乘法+LUT   差值计算   插值运算   最终除法   输出特征
        |_______________________________________________________________________________________|
```

**优点**:
- 7级流水线，避免组合逻辑过长
- 使用倒数查找表 (LUT) 替代除法器，节省资源
- 时序优化：COMPUTE3A/3B 分离，减少关键路径延迟

### 2.3 ⚠️ 潜在问题

#### 问题1: **FFT数据源不匹配**
```verilog
// signal_analyzer_top.v (line 1816-1817)
.fft_magnitude    (ch1_spectrum_rd_data),  // ❌ 使用频谱RAM读出数据
.fft_bin_index    (spectrum_rd_addr[9:0]), // ❌ 使用HDMI显示读地址
.fft_valid        (ai_enable && (current_fft_channel == 1'b0)),
```

**问题分析**:
- `ch1_spectrum_rd_data` 是 **显示模块读取的数据**，不是实时FFT输出
- `spectrum_rd_addr` 由 **HDMI显示控制器** 驱动，与FFT计算不同步
- FFT数据应该直接来自 `ch1_spectrum_magnitude` + `ch1_spectrum_wr_addr`

**影响**:
- 频域特征（THD、频谱质心、频谱展宽）计算错误
- AI识别准确率严重下降

#### 问题2: **窗口大小不匹配**
```verilog
// ai_signal_recognizer.v
parameter WINDOW_SIZE = 1024,  // 时域窗口1024点
parameter FFT_BINS = 512       // FFT频点512 ❌ 实际是8192点
```

**实际系统配置**:
- FFT点数: 8192
- 频谱地址: 13位 (0~8191)
- 传入参数: 10位 (0~1023) ← **截断错误**

#### 问题3: **数据位宽不匹配**
```verilog
// ai_signal_recognizer.v
input wire signed [DATA_WIDTH-1:0] signal_in,  // 11-bit
// 但实际连接:
.signal_in (ch1_data_11b),  // ✅ 正确
```

这个部分是正确的。

---

## 3. 分类器检查

### 3.1 ✅ 支持的5种波形类型

| 类型 | 编码 | 关键特征阈值 | 置信度基准 |
|-----|------|------------|-----------|
| **正弦波** | 3'd1 | THD<5%, CF:1.37-1.56, FF:1.05-1.17 | 90-100% |
| **方波** | 3'd2 | THD>30%, CF<1.1, ZCR<2048 | 85-95% |
| **三角波** | 3'd3 | THD:10-25%, CF:1.64-1.88, FF:1.09-1.25 | 80-90% |
| **锯齿波** | 3'd4 | THD>20%, CF>1.56, ZCR>1024 | 75-85% |
| **噪声** | 3'd5 | THD>60% OR ZCR>8192 | 70-80% |

### 3.2 ✅ 决策树算法
```
第1级: THD粗分类
    ├─ THD < 5%     → 正弦波候选 (检查CF+FF)
    ├─ THD > 30%    → 方波/噪声候选
    ├─ THD: 10-25%  → 三角波候选
    └─ THD > 20%    → 锯齿波候选

第2级: 置信度修正
    ├─ 频谱集中 (spread<256) → +5分
    └─ 零均值 (|mean|<100)   → +2分
```

### 3.3 ⚠️ 阈值调优建议

#### 建议1: **正弦波THD阈值过严格**
```verilog
localparam SINE_THD_MAX = 16'd5;  // 5% ← 可能太低
```
**问题**: 实际ADC噪声可能导致THD>5%，正弦波漏检  
**建议**: 放宽到 `16'd8` (8%)

#### 建议2: **峰值因子范围**
```verilog
// 正弦波 √2 = 1.414 (Q8.8 = 362)
localparam SINE_CF_MIN = 16'd350;  // 1.37 ✅ 合理
localparam SINE_CF_MAX = 16'd400;  // 1.56 ✅ 合理

// 三角波 √3 = 1.732 (Q8.8 = 444)
localparam TRIANGLE_CF_MIN = 16'd420;  // 1.64 ✅
localparam TRIANGLE_CF_MAX = 16'd480;  // 1.88 ✅
```
**状态**: 阈值范围合理，有一定容错空间

---

## 4. 集成问题汇总

### 4.1 ❌ 关键缺陷

| 问题 | 位置 | 严重程度 | 修复优先级 |
|-----|------|---------|-----------|
| **FFT数据源错误** | signal_analyzer_top.v:1816 | 🔴 HIGH | P0 |
| **FFT_BINS参数错误** | ai_signal_recognizer.v:17 | 🔴 HIGH | P0 |
| **fft_bin_index截断** | signal_analyzer_top.v:1817 | 🟠 MEDIUM | P1 |

### 4.2 ⚠️ 次要问题

| 问题 | 建议 | 优先级 |
|-----|-----|--------|
| 正弦波THD阈值过严 | 5% → 8% | P2 |
| 缺少滤波器状态检测 | 等待特征稳定后输出 | P3 |
| 时域窗口1024点 | 可考虑扩展到2048/4096 | P4 |

---

## 5. 修复建议

### 5.1 🔧 立即修复（P0级）

#### 修复1: FFT数据源连接
```verilog
// 【修复前】signal_analyzer_top.v
.fft_magnitude    (ch1_spectrum_rd_data),     // ❌ 错误
.fft_bin_index    (spectrum_rd_addr[9:0]),   // ❌ 错误

// 【修复后】
.fft_magnitude    (ch1_spectrum_magnitude),   // ✅ 使用FFT实时输出
.fft_bin_index    (ch1_spectrum_wr_addr[9:0]),// ✅ 使用FFT写地址
.fft_valid        (ch1_spectrum_valid),       // ✅ 使用FFT有效信号
```

#### 修复2: FFT参数配置
```verilog
// 【修复前】ai_signal_recognizer.v (line 1805)
parameter FFT_BINS = 512  // ❌ 错误

// 【修复后】
parameter FFT_BINS = 4096  // ✅ 8192点FFT的有效频点数(对称性)
```

#### 修复3: 地址位宽
```verilog
// 【修复前】
input wire [9:0] fft_bin_index,  // ❌ 10位只能表示0~1023

// 【修复后】
input wire [12:0] fft_bin_index,  // ✅ 13位支持0~8191
```

### 5.2 🔨 优化改进（P1-P2级）

#### 改进1: 阈值调整
```verilog
// waveform_classifier.v
localparam SINE_THD_MAX = 16'd8;  // 5% → 8%
```

#### 改进2: 结果稳定性
```verilog
// 添加连续N次识别一致性检查
reg [2:0] prev_waveform_type;
reg [3:0] stable_count;

always @(posedge clk) begin
    if (classify_result == prev_waveform_type) begin
        if (stable_count < 4'd10)
            stable_count <= stable_count + 1'b1;
    end else begin
        stable_count <= 4'd0;
        prev_waveform_type <= classify_result;
    end
    
    // 只有稳定10次后才输出
    if (stable_count >= 4'd10) begin
        waveform_type <= prev_waveform_type;
        classification_valid <= 1'b1;
    end
end
```

---

## 6. 测试验证建议

### 6.1 单元测试

#### 测试1: 特征提取精度
```
输入信号: 1kHz正弦波, 1Vpp, 无噪声
预期特征:
  - ZCR: ~2000 (每周期2次过零)
  - Crest Factor: ~362 (√2 in Q8.8)
  - Form Factor: ~284 (1.11 in Q8.8)
  - THD: <5
  - Spectral Centroid: ~234 (1kHz @ 4.272Hz/bin)
```

#### 测试2: 分类准确率
```
测试集: 各类型波形 × 10组
  - 正弦波: 1kHz, 10kHz, 100kHz
  - 方波:   1kHz, 10kHz (50%占空比)
  - 三角波: 1kHz, 10kHz
  - 锯齿波: 1kHz, 10kHz
  - 噪声:   白噪声

目标准确率: >90%
```

### 6.2 集成测试

#### 测试3: 双通道AI识别
```
通道1: 1kHz正弦波
通道2: 10kHz方波
预期:
  - CH1: TYPE_SINE, confidence > 90%
  - CH2: TYPE_SQUARE, confidence > 85%
```

#### 测试4: 实时性能
```
测量指标:
  - 特征提取延迟: <2ms (1024点 @ 35MHz)
  - 分类决策延迟: 1个时钟周期
  - 总延迟: <3ms
```

---

## 7. 资源占用评估

### 7.1 预估资源（未综合前）

| 模块 | LUT | FF | DSP | BRAM |
|-----|-----|----|----|------|
| 特征提取器 | ~2000 | ~1500 | 8-12 | 2 |
| 分类器 | ~500 | ~200 | 0 | 0 |
| 倒数LUT (×4) | ~1000 | ~100 | 0 | 4 |
| **总计** | **~3500** | **~1800** | **8-12** | **6** |

**建议**: 综合后检查实际资源，确保LUT<30%, DSP<50%

---

## 8. 结论与建议

### 8.1 ✅ 优点
1. **架构清晰**: 三层模块化设计，便于维护
2. **特征丰富**: 8个特征覆盖时域+频域
3. **算法成熟**: 决策树分类简单高效
4. **流水线优化**: 7级流水线，时序友好

### 8.2 ❌ 必须修复的问题
1. **FFT数据源错误** - 导致频域特征全部失效
2. **FFT_BINS参数错误** - 频谱分析范围截断
3. **地址位宽不足** - 无法访问完整8192点频谱

### 8.3 📋 修复计划

#### 第1步: 立即修复（今天完成）
- [ ] 修改FFT数据源连接（3处）
- [ ] 更新FFT_BINS参数 512 → 4096
- [ ] 扩展fft_bin_index位宽 10 → 13

#### 第2步: 验证测试（明天）
- [ ] 编译检查无错误
- [ ] 正弦波测试（THD<8%）
- [ ] 方波测试（THD>30%）

#### 第3步: 优化改进（本周内）
- [ ] 阈值微调
- [ ] 添加结果稳定性过滤
- [ ] 性能基准测试

---

## 9. 风险评估

| 风险项 | 概率 | 影响 | 缓解措施 |
|-------|------|------|---------|
| FFT数据竞争 | 中 | 高 | 使用valid信号严格控制 |
| 阈值不适配实际硬件 | 高 | 中 | 提供可调参数接口 |
| 资源溢出 | 低 | 高 | 综合后检查，必要时简化LUT |
| 时序违例 | 低 | 高 | 流水线已优化，应无问题 |

---

**检查人**: GitHub Copilot  
**审核状态**: 待修复后验证  
**下一步**: 立即执行P0级修复
