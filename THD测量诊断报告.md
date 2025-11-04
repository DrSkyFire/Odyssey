# THD测量显示0.0%诊断报告

## 问题描述
HDMI显示THD始终为0.0%，无论输入信号类型如何（正弦波、方波、三角波）。

## 代码分析结果

### 🔍 数据流分析

THD数据流路径：
```
FFT输出 → spectrum_magnitude_calc → dual_channel_fft_controller 
→ ch1_spectrum_magnitude/valid/addr → signal_parameter_measure 
→ 谐波检测 → THD计算 → thd_filtered → thd_out → HDMI显示
```

### ❌ 发现的关键问题

#### **问题1：THD滤波器初始化缺陷（最可能的原因）**
**位置**：`signal_parameter_measure.v` 行1478-1500

**问题代码**：
```verilog
reg [15:0]  thd_history[0:7];               // THD历史值缓存
reg [2:0]   thd_hist_ptr;                   // THD历史值指针
reg [18:0]  thd_sum;                        // THD累加和
reg [15:0]  thd_filtered;                   // 滤波后的THD结果

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        for (i = 0; i < 8; i = i + 1) begin
            thd_history[i] <= 16'd0;
        end
        thd_hist_ptr <= 3'd0;
        thd_sum <= 19'd0;
        thd_filtered <= 16'd0;
    end else begin
        // 每次新的thd_calc到来时更新滑动窗口
        if (thd_pipe_valid[2]) begin
            // 减去最老的值
            thd_sum <= thd_sum - thd_history[thd_hist_ptr] + thd_calc;
            // 更新历史缓存
            thd_history[thd_hist_ptr] <= thd_calc;
            // 移动指针
            thd_hist_ptr <= thd_hist_ptr + 1'b1;
            // 计算平均值(除以8 = 右移3位)
            thd_filtered <= thd_sum[18:3];  // ⚠️ 这里输出的是OLD thd_sum！
        end
    end
end
```

**问题分析**：
1. **时序错误**：`thd_filtered <= thd_sum[18:3]` 使用的是**更新前的旧值**
2. **冷启动问题**：初始8个周期内，thd_sum从0累加，但输出的thd_filtered一直是0
3. **滞后1拍**：即使累加正常，输出也比实际值滞后1个时钟周期

**影响**：
- 前8次THD计算结果全部显示为0
- 即使后续有值，也会比实际值小（因为用的是上一次的sum）
- 如果测量周期较短，可能永远看不到正确值

---

#### **问题2：measure_done与THD更新时序不匹配**
**位置**：`signal_parameter_measure.v` 行1520-1537

**问题代码**：
```verilog
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        // ... 初始化
        thd_out <= 16'd0;
    end else if (measure_en) begin
        if (measure_done) begin  // ⚠️ 100ms周期触发
            // ...
            thd_out <= thd_filtered;  // 输出THD
        end
    end
end
```

**问题分析**：
1. **FFT周期不确定**：FFT完成一次扫描的时间取决于数据流速度
2. **更新不同步**：`measure_done`是基于100ms定时，但THD数据就绪依赖FFT扫描完成
3. **可能采样空窗期**：如果`measure_done`时刻FFT还没完成新一轮扫描，会输出旧值或0

---

#### **问题3：谐波检测可能过滤掉所有谐波**
**位置**：`signal_parameter_measure.v` 行690-720

**问题代码**：
```verilog
// 扫描结束，锁存谐波幅度（优化门限，减少噪声影响）
else if (spectrum_addr == (FFT_POINTS/2)) begin
    // 2次谐波：方波理论为0，检测到的是噪声/失真，用高门限
    if (harm2_amp > ((fft_max_amp >> 5) > 16'd150 ? (fft_max_amp >> 5) : 16'd150))
        fft_harmonic_2 <= harm2_amp;
    else
        fft_harmonic_2 <= 16'd0;  // ⚠️ 门限过高可能全部过滤
    
    // 3次谐波：降低门限以检测三角波H3
    if (harm3_amp > ((fft_max_amp >> 6) > 16'd80 ? (fft_max_amp >> 6) : 16'd80))
        fft_harmonic_3 <= harm3_amp;
    else
        fft_harmonic_3 <= 16'd0;
    
    // ...其他谐波类似
}
```

**问题分析**：
1. **自适应门限**：门限基于基波幅度 `fft_max_amp`
2. **小信号问题**：如果输入信号幅度小，基波幅度小，门限降低，但谐波幅度可能更小
3. **绝对门限过高**：如 `16'd150`、`16'd80` 可能对小幅度信号来说太高
4. **方波误判**：注释说"方波理论为0"是错误的，方波含大量奇次谐波

---

#### **问题4：thd_ready信号可能未触发计算**
**位置**：`signal_parameter_measure.v` 行1357-1378

**问题代码**：
```verilog
// 检测thd_ready上升沿（从0到1）
if (thd_ready && !thd_ready_d1 && !thd_fft_trigger) begin
    // 计算谐波总和（2-5次）
    thd_harmonic_sum <= {16'd0, fft_harmonic_2} + 
                       {16'd0, fft_harmonic_3} + 
                       {16'd0, fft_harmonic_4} + 
                       {16'd0, fft_harmonic_5};
    
    // 基波幅度来自FFT峰值
    fundamental_power <= {16'd0, fft_max_amp};
    
    thd_fft_trigger <= 1'b1;
    
    // 【优化】只有谐波总和>0且基波足够大时才触发计算
    if ((fft_harmonic_2 + fft_harmonic_3 + fft_harmonic_4 + fft_harmonic_5) > 16'd0 
        && fft_max_amp > 16'd200)
        thd_calc_trigger <= 1'b1;  // ⚠️ 基波<200就不计算
    else
        thd_calc_trigger <= 1'b0;  // THD=0
end
```

**问题分析**：
1. **基波门限过高**：`fft_max_amp > 16'd200` 要求基波幅度 >200
2. **小信号无法测量**：如果ADC输入幅度小（如0.5Vpp），FFT输出可能<200
3. **谐波全0直接放弃**：如果门限过滤掉所有谐波，直接不计算

---

### 📊 根本原因总结

**最可能的原因排序**：

1. **🔴 关键bug**：THD滤波器输出的是旧值，导致初始阶段一直为0 *（90%概率）*
2. **🟠 次要bug**：谐波检测门限过高，过滤掉了所有谐波 *（70%概率）*
3. **🟡 设计缺陷**：基波门限200过高，小信号无法触发计算 *（60%概率）*
4. **🟡 时序问题**：FFT数据流未正常工作（spectrum_valid未触发）*（30%概率）*

---

## 🛠️ 修复方案

### 方案1：修复THD滤波器时序（必须）

**修改位置**：`signal_parameter_measure.v` 行1489-1500

**修改前**：
```verilog
if (thd_pipe_valid[2]) begin
    thd_sum <= thd_sum - thd_history[thd_hist_ptr] + thd_calc;
    thd_history[thd_hist_ptr] <= thd_calc;
    thd_hist_ptr <= thd_hist_ptr + 1'b1;
    thd_filtered <= thd_sum[18:3];  // ❌ 输出旧值
end
```

**修改后**：
```verilog
if (thd_pipe_valid[2]) begin
    // 更新累加和
    thd_sum <= thd_sum - thd_history[thd_hist_ptr] + thd_calc;
    thd_history[thd_hist_ptr] <= thd_calc;
    thd_hist_ptr <= thd_hist_ptr + 1'b1;
    
    // ✅ 输出更新后的值（组合逻辑）
    thd_filtered <= (thd_sum - thd_history[thd_hist_ptr] + thd_calc) >> 3;
end
```

---

### 方案2：降低谐波检测门限（推荐）

**修改位置**：`signal_parameter_measure.v` 行690-720

**修改策略**：
- 降低绝对门限：150→50，80→30，50→20
- 取消自适应门限中的"基波/N"部分（避免小信号时门限过低）

**修改后**：
```verilog
else if (spectrum_addr == (FFT_POINTS/2)) begin
    // 2次谐波：降低门限，允许检测小幅度失真
    if (harm2_amp > 16'd50)  // ✅ 绝对门限50
        fft_harmonic_2 <= harm2_amp;
    else
        fft_harmonic_2 <= 16'd0;
    
    // 3次谐波
    if (harm3_amp > 16'd30)  // ✅ 绝对门限30
        fft_harmonic_3 <= harm3_amp;
    else
        fft_harmonic_3 <= 16'd0;
    
    // 4次谐波
    if (harm4_amp > 16'd40)
        fft_harmonic_4 <= harm4_amp;
    else
        fft_harmonic_4 <= 16'd0;
    
    // 5次谐波
    if (harm5_amp > 16'd20)  // ✅ 绝对门限20
        fft_harmonic_5 <= harm5_amp;
    else
        fft_harmonic_5 <= 16'd0;
}
```

---

### 方案3：降低THD计算触发门限（推荐）

**修改位置**：`signal_parameter_measure.v` 行1370-1377

**修改前**：
```verilog
if ((fft_harmonic_2 + fft_harmonic_3 + fft_harmonic_4 + fft_harmonic_5) > 16'd0 
    && fft_max_amp > 16'd200)  // ❌ 门限过高
    thd_calc_trigger <= 1'b1;
```

**修改后**：
```verilog
if ((fft_harmonic_2 + fft_harmonic_3 + fft_harmonic_4 + fft_harmonic_5) > 16'd0 
    && fft_max_amp > 16'd100)  // ✅ 降低到100
    thd_calc_trigger <= 1'b1;
```

---

### 方案4：添加调试信号监控（可选）

在顶层模块添加LED指示：
```verilog
// THD调试指示
assign led[4] = (ch1_thd > 16'd0);          // THD非零指示
assign led[5] = ch1_spectrum_valid;         // FFT数据流指示
assign led[6] = (fft_harmonic_2 > 16'd0);   // 2次谐波检测到
assign led[7] = (fft_max_amp > 16'd100);    // 基波幅度足够
```

---

## ✅ 验证步骤

### 第一步：快速验证滤波器修复
1. 只修复方案1（滤波器时序）
2. 编译烧录
3. 输入1kHz方波（THD应>30%）
4. **预期**：THD从0.0%变为有数值显示

### 第二步：降低门限验证
1. 应用方案2和方案3
2. 输入小幅度正弦波（0.5Vpp）
3. **预期**：THD能显示（纯正弦波应<2%）

### 第三步：全面测试
| 信号类型 | 预期THD | 实测值 | 状态 |
|---------|---------|--------|------|
| 纯正弦波 | <2% | _____ % | □ |
| 1kHz方波 | >30% | _____ % | □ |
| 1kHz三角波 | 10-15% | _____ % | □ |

---

## 🔬 如果问题仍未解决

检查以下可能性：

1. **FFT数据流异常**
   - 监控 `ch1_spectrum_valid` 是否有效
   - 检查 `ch1_spectrum_magnitude` 是否有数据
   
2. **Hann窗问题**
   - 检查Hann窗是否正确应用
   - 验证窗函数不会将谐波全部衰减掉

3. **时钟域问题**
   - FFT时钟 `clk_fft` 与系统时钟 `clk_100m` 的CDC
   - `spectrum_valid` 信号是否需要同步

4. **HDMI显示问题**
   - 验证 `thd_out` 确实为0，而不是显示模块问题
   - 检查其他参数（频率、幅度）是否正常显示

---

## 📝 修改优先级

| 优先级 | 修改内容 | 影响范围 | 风险 |
|--------|----------|----------|------|
| P0 | 方案1：修复滤波器时序 | 仅THD输出 | 低 |
| P1 | 方案3：降低基波门限100 | THD触发条件 | 低 |
| P2 | 方案2：降低谐波门限 | 谐波检测灵敏度 | 中（可能增加噪声误检） |
| P3 | 方案4：添加调试信号 | 调试便利性 | 无 |

建议：先实施P0+P1，验证后再考虑P2。
