# THD测量显示0.0%问题修复说明

## 📋 问题描述
HDMI显示THD始终为0.0%，无论输入信号类型（正弦波、方波、三角波）。

## 🔍 根本原因

经过详细代码审查，发现了**3个关键Bug**：

### Bug 1：THD滤波器时序错误（最严重）⚠️
**影响**：滤波器输出的是旧值，导致初始阶段持续显示0.0%

**位置**：`signal_parameter_measure.v` 行1489-1500

**问题代码**：
```verilog
if (thd_pipe_valid[2]) begin
    thd_sum <= thd_sum - thd_history[thd_hist_ptr] + thd_calc;
    thd_history[thd_hist_ptr] <= thd_calc;
    thd_hist_ptr <= thd_hist_ptr + 1'b1;
    thd_filtered <= thd_sum[18:3];  // ❌ 这里使用的是旧的thd_sum
}
```

**根本原因**：
- `thd_sum` 的更新和 `thd_filtered` 的赋值在同一个时钟周期
- Verilog非阻塞赋值 `<=` 导致 `thd_sum` 要到下一个时钟才更新
- `thd_filtered` 读取的是**上一个周期的旧值**
- 初始阶段 `thd_sum=0`，所以 `thd_filtered` 持续为0

**时序图**：
```
周期   thd_calc    thd_sum(更新前)  thd_filtered(输出)  thd_sum(更新后)
  1      100           0                0                  100
  2      120          100               12 (100>>3)        220
  3      110          220               27 (220>>3)        330
                       ↑                 ↑
                    旧值              滞后1拍！
```

---

### Bug 2：基波门限过高
**影响**：小信号输入时无法触发THD计算

**位置**：`signal_parameter_measure.v` 行1370-1377

**问题代码**：
```verilog
if ((fft_harmonic_2 + ... + fft_harmonic_5) > 16'd0 
    && fft_max_amp > 16'd200)  // ❌ 门限200对小信号太高
    thd_calc_trigger <= 1'b1;
```

**影响场景**：
- 输入信号幅度 < 1Vpp
- ADC采样幅度小
- FFT输出基波幅度 < 200
- 直接不计算THD → 输出0.0%

---

### Bug 3：谐波检测门限过高
**影响**：过滤掉所有谐波，导致THD计算输入为0

**位置**：`signal_parameter_measure.v` 行690-720

**问题代码**：
```verilog
// 2次谐波门限
if (harm2_amp > ((fft_max_amp >> 5) > 16'd150 ? (fft_max_amp >> 5) : 16'd150))
    fft_harmonic_2 <= harm2_amp;
else
    fft_harmonic_2 <= 16'd0;  // ❌ 门限过高，谐波全部被过滤
```

**问题分析**：
- 自适应门限 `MAX(基波/32, 150)` 对小信号过高
- 绝对门限150/80/50对低幅度谐波太严格
- 即使检测到谐波，也被门限过滤掉
- 导致 `fft_harmonic_2/3/4/5` 全为0
- THD计算条件不满足 → 不计算

---

## ✅ 修复方案

### 修复1：THD滤波器时序修复（关键）

**修改文件**：`signal_parameter_measure.v` 行1489-1500

**修改后代码**：
```verilog
if (thd_pipe_valid[2]) begin
    // 【修复】使用组合逻辑计算新的sum，避免输出滞后
    // 先计算新的累加和，再输出（避免使用旧值）
    thd_sum <= thd_sum - thd_history[thd_hist_ptr] + thd_calc;
    // 更新历史缓存
    thd_history[thd_hist_ptr] <= thd_calc;
    // 移动指针
    thd_hist_ptr <= thd_hist_ptr + 1'b1;
    // 【关键修复】计算平均值时使用更新后的值（组合逻辑）
    // thd_filtered = (thd_sum - old_value + new_value) / 8
    thd_filtered <= (thd_sum - thd_history[thd_hist_ptr] + thd_calc) >> 3;
end
```

**原理**：
- 使用组合逻辑直接计算新的累加和
- `(thd_sum - thd_history[thd_hist_ptr] + thd_calc)` 在同一周期计算完成
- 输出的 `thd_filtered` 是基于**当前周期的最新值**
- 消除1拍滞后

**时序改进**：
```
周期   thd_calc    组合逻辑计算                    thd_filtered(输出)
  1      100      (0 - 0 + 100) >> 3 = 12           12  ✅
  2      120      (100 - 0 + 120) >> 3 = 27         27  ✅
  3      110      (220 - 100 + 110) >> 3 = 41       41  ✅
                           ↑
                        实时计算！
```

---

### 修复2：降低基波门限

**修改文件**：`signal_parameter_measure.v` 行1370-1377

**修改内容**：
```verilog
// 【修复】降低基波门限从200→100，支持小信号测量
if ((fft_harmonic_2 + fft_harmonic_3 + fft_harmonic_4 + fft_harmonic_5) > 16'd0 
    && fft_max_amp > 16'd100)  // ✅ 降低到100
    thd_calc_trigger <= 1'b1;
```

**效果**：
- 支持更小幅度的输入信号
- 基波幅度 > 100 即可触发THD计算
- 对应ADC约0.3Vpp以上的输入

---

### 修复3：降低谐波检测门限

**修改文件**：`signal_parameter_measure.v` 行690-720

**修改策略**：
- 取消自适应门限（避免小信号时门限过高）
- 使用固定的低门限
- 门限值：H2=50, H3=30, H4=40, H5=20

**修改后代码**：
```verilog
else if (spectrum_addr == (FFT_POINTS/2)) begin
    // 【修复】降低绝对门限，提高THD检测成功率
    // 使用纯绝对门限策略，避免小信号时自适应门限过高
    
    // 2次谐波：降低门限以检测实际失真（原150→50）
    if (harm2_amp > 16'd50)
        fft_harmonic_2 <= harm2_amp;
    else
        fft_harmonic_2 <= 16'd0;
    
    // 3次谐波：降低门限以检测三角波H3（原80→30）
    if (harm3_amp > 16'd30)
        fft_harmonic_3 <= harm3_amp;
    else
        fft_harmonic_3 <= 16'd0;
    
    // 4次谐波：降低门限（原100→40）
    if (harm4_amp > 16'd40)
        fft_harmonic_4 <= harm4_amp;
    else
        fft_harmonic_4 <= 16'd0;
    
    // 5次谐波：降低门限以检测三角波H5（原50→20）
    if (harm5_amp > 16'd20)
        fft_harmonic_5 <= harm5_amp;
    else
        fft_harmonic_5 <= 16'd0;
    
    thd_ready <= 1'b1;
end
```

**门限对比**：
| 谐波 | 修复前 | 修复后 | 降低比例 |
|------|--------|--------|----------|
| H2   | 150    | 50     | 66.7%    |
| H3   | 80     | 30     | 62.5%    |
| H4   | 100    | 40     | 60.0%    |
| H5   | 50     | 20     | 60.0%    |

---

## 📊 预期效果

### 修复前
- THD显示：**0.0%**（所有信号）
- 原因：滤波器输出旧值0 + 谐波被过滤 + 基波门限过高

### 修复后
| 信号类型 | 理论THD | 预期显示范围 |
|---------|---------|-------------|
| 纯正弦波 | <1%     | 0.0-2.0%    |
| 1kHz方波 | 48%     | 35-55%      |
| 1kHz三角波 | 12%   | 10-15%      |

---

## 🧪 验证步骤

### 第一步：编译烧录
```powershell
# 在TD IDE中编译工程
# 烧录bitstream到FPGA
```

### 第二步：基础功能验证
1. **输入**：1kHz方波，幅度2Vpp
2. **观察**：HDMI显示THD值
3. **预期**：THD显示 35-55%（方波富含奇次谐波）
4. **状态**：□ 通过 / □ 失败

### 第三步：不同波形验证
| 测试 | 信号 | 频率 | 幅度 | 预期THD | 实测THD | 状态 |
|------|------|------|------|---------|---------|------|
| 1 | 正弦波 | 1kHz | 2Vpp | <2% | _____ % | □ |
| 2 | 方波   | 1kHz | 2Vpp | 35-55% | _____ % | □ |
| 3 | 三角波 | 1kHz | 2Vpp | 10-15% | _____ % | □ |

### 第四步：小信号验证
| 测试 | 信号 | 幅度 | 预期THD | 实测THD | 状态 |
|------|------|------|---------|---------|------|
| 4 | 方波 | 1Vpp | 35-55% | _____ % | □ |
| 5 | 方波 | 0.5Vpp | 35-55% | _____ % | □ |

---

## 🔧 如果问题仍未解决

### 调试步骤1：检查FFT数据流
在代码中添加临时调试信号：
```verilog
// 在signal_analyzer_top.v中添加
reg [15:0] debug_spectrum_count;

always @(posedge clk_fft) begin
    if (ch1_spectrum_valid)
        debug_spectrum_count <= debug_spectrum_count + 1;
end

// 将debug_spectrum_count连接到LED观察
assign led[7:4] = debug_spectrum_count[7:4];
```

**预期**：LED应周期性闪烁，表示FFT数据在持续输出

---

### 调试步骤2：检查谐波检测结果
在 `signal_parameter_measure.v` 中添加：
```verilog
// 临时调试：将谐波幅度输出到未使用的端口
// （需要在顶层模块连接到LED或调试端口）
wire [15:0] debug_harm2 = fft_harmonic_2;
wire [15:0] debug_harm3 = fft_harmonic_3;
wire [15:0] debug_max_amp = fft_max_amp;
```

**检查点**：
- `fft_max_amp` 应 >100（基波幅度）
- 方波输入时 `fft_harmonic_3` 应明显>0（方波主要谐波）
- 如果全为0，说明谐波检测有问题

---

### 调试步骤3：检查HDMI显示链路
验证其他参数（频率、幅度）是否正常显示：
- 如果频率/幅度正常，THD异常 → THD计算问题
- 如果所有参数都异常 → HDMI显示链路问题

---

## 📁 修改文件清单

| 文件 | 修改内容 | 行数 |
|------|----------|------|
| `signal_parameter_measure.v` | THD滤波器时序修复 | 1489-1500 |
| `signal_parameter_measure.v` | 降低基波门限100 | 1370-1377 |
| `signal_parameter_measure.v` | 降低谐波检测门限 | 690-720 |

---

## 💡 技术要点总结

### 关键教训1：Verilog非阻塞赋值的坑
```verilog
// ❌ 错误：读取的是旧值
always @(posedge clk) begin
    sum <= sum + new_data;
    output <= sum;  // 这里的sum是旧值！
end

// ✅ 正确：使用组合逻辑
always @(posedge clk) begin
    sum <= sum + new_data;
    output <= sum + new_data;  // 组合逻辑，当前周期有效
end
```

### 关键教训2：自适应门限需谨慎
- 自适应门限在大动态范围系统中很有用
- 但需要设置合理的下限，避免小信号时门限过高
- 或者使用 `MIN(自适应值, 固定值)` 而非 `MAX`

### 关键教训3：调试思路
1. 先检查数据流（FFT输出是否有效）
2. 再检查算法逻辑（谐波检测、THD计算）
3. 最后检查时序问题（滤波器、CDC等）

---

## ✅ 修复完成确认

- [x] Bug 1：THD滤波器时序修复
- [x] Bug 2：降低基波门限至100
- [x] Bug 3：降低谐波检测门限（50/30/40/20）
- [ ] 编译测试
- [ ] 上板验证
- [ ] 性能测试

---

**修复日期**：2025年11月4日
**修复工程师**：GitHub Copilot
**审核状态**：待测试验证
