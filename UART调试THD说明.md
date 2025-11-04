# UART调试THD - 实时监控调试指南

## 🎯 目的

通过UART串口实时输出THD计算链路的关键信号，诊断为什么THD始终显示0.0%。

---

## 📊 调试信号说明

### 输出格式（每秒更新）

```
===STATUS===
Mode:P Run:1 CH1:1 CH2:1 Trig:A FIFO:8192 FFT:1234 Test:0 
H2:0025 H3:0015 BASE:5000 TRG:1 VAL:1
```

### 信号含义

| 字段 | 含义 | 正常值 | 异常值 | 说明 |
|------|------|--------|--------|------|
| **H2** | 2次谐波幅度 | 方波>500 | 0 | 如果为0说明谐波未被检测到 |
| **H3** | 3次谐波幅度 | 方波>300 | 0 | 方波应该有明显的3次谐波 |
| **BASE** | 基波幅度(fft_max_amp) | >1000 | <100 | 过低说明FFT输入问题 |
| **TRG** | THD计算触发 | 1 | 0 | 0表示触发条件不满足 |
| **VAL** | 流水线有效标志 | 1 | 0 | 0表示计算未执行 |

---

## 🔍 故障诊断树

### 1. 所有谐波都是0 (H2=0 H3=0)

**可能原因**：
- ❌ FFT输出无数据（spectrum_valid=0）
- ❌ 谐波bin计算错误
- ❌ 谐波搜索窗口错误

**排查步骤**：
```
1. 检查BASE值：
   - 如果BASE也=0 → FFT没工作
   - 如果BASE>0但H2=0 → 谐波检测逻辑问题
   
2. 检查FFT频谱显示：
   - HDMI屏幕上能看到谐波峰值吗？
   - 如果能看到 → 谐波锁存逻辑问题
   - 如果看不到 → FFT配置问题
```

---

### 2. 谐波有值但TRG=0

**可能原因**：
- ❌ 触发条件判断错误
- ❌ fft_fft_trigger标志异常
- ❌ 基波功率(fundamental_power)<100

**代码位置**：
```verilog
// signal_parameter_measure.v 行1395
if ((fft_harmonic_2 + fft_harmonic_3 + fft_harmonic_4 + fft_harmonic_5) > 16'd0 
    && fft_max_amp > 16'd100) begin
    thd_calc_trigger <= 1'b1;  // ← 检查这里
end
```

**检查**：
- H2+H3 > 0 ? 
- BASE > 100 ?

---

### 3. TRG=1但VAL=0

**可能原因**：
- ❌ fundamental_power计算错误
- ❌ 流水线未执行

**代码位置**：
```verilog
// signal_parameter_measure.v 行1421
if (thd_calc_trigger && fundamental_power > 32'd100) begin
    thd_pipe_valid[0] <= 1'b1;  // ← 应该被触发
end
```

**检查**：
- fundamental_power = fft_max_amp * fft_max_amp
- 1MHz 3Vpp方波的BASE应该>2000
- fundamental_power应该>4,000,000

---

### 4. VAL=1但THD显示0.0%

**可能原因**：
- ❌ LUT查表结果错误
- ❌ 滤波器清零了结果
- ❌ 显示模块未更新

**检查**：
```
1. 用逻辑分析仪抓取thd_out信号
2. 确认thd_filtered是否有值
3. 检查HDMI显示模块的table_display
```

---

## 🧪 测试用例与预期值

### 测试1：1MHz方波，3Vpp

| 信号 | 预期值 | 说明 |
|------|--------|------|
| BASE | 5000-8000 | FFT基波峰值 |
| H2 | 少量 | 偶次谐波应该很小 |
| H3 | 1500-2500 | 3次谐波约为基波的33% |
| H5 | 1000-1500 | 5次谐波约为基波的20% |
| TRG | 1 | 应该触发 |
| VAL | 1 | 应该有效 |
| **THD显示** | **40-55%** | 最终结果 |

---

### 测试2：1MHz正弦波，3Vpp

| 信号 | 预期值 | 说明 |
|------|--------|------|
| BASE | 5000-8000 | 与方波类似 |
| H2 | <100 | 正弦波谐波很小 |
| H3 | <50 | 很小 |
| H5 | <30 | 很小 |
| TRG | 0或1 | 谐波太小可能不触发 |
| VAL | 0或1 | 取决于TRG |
| **THD显示** | **<5%** | 理想正弦波 |

---

## ⚙️ 使用方法

### 1. 硬件连接

```
FPGA UART_TX (uart_tx管脚) → USB转TTL → PC
```

**波特率**：115200（根据实际uart_tx模块配置）
**数据位**：8
**停止位**：1
**奇偶校验**：无

---

### 2. 打开串口监视

**Windows PowerShell**：
```powershell
# 查看可用COM口
[System.IO.Ports.SerialPort]::getportnames()

# 使用PuTTY或其他串口工具
# 推荐：使用VS Code + Serial Monitor扩展
```

**推荐软件**：
- PuTTY (轻量)
- TeraTerm (功能强大)
- VS Code + Serial Monitor插件
- Arduino IDE Serial Monitor

---

### 3. 观察输出

编译并下载到FPGA后，串口将每秒输出一次：

```
===STATUS===
Mode:P Run:1 CH1:1 CH2:1 Trig:A FIFO:8192 FFT:0123 Test:0 
H2:0000 H3:0000 BASE:0000 TRG:0 VAL:0

===STATUS===
Mode:P Run:1 CH1:1 CH2:1 Trig:A FIFO:8192 FFT:0234 Test:0 
H2:0025 H3:0015 BASE:5234 TRG:1 VAL:1
```

---

### 4. 分析流程

**步骤1：输入1MHz 3Vpp方波**

**观察BASE**：
- [ ] BASE > 1000? （FFT工作正常）
- [ ] BASE值稳定？（ADC采样稳定）

**观察谐波**：
- [ ] H2 > 0? 
- [ ] H3 > 0?
- [ ] H3约为BASE的20-30%?

**观察触发**：
- [ ] TRG = 1? （THD计算被触发）
- [ ] VAL = 1? （流水线执行）

**观察结果**：
- [ ] HDMI屏幕THD显示 > 0%?

---

## 🐞 常见问题诊断

### Q1: BASE=0, 所有谐波=0

**问题**：FFT没有数据输出

**检查**：
1. spectrum_valid信号是否拉高？
2. dual_channel_fft_controller工作吗？
3. ADC数据是否进入FFT？

**解决**：
- 检查FFT模块使能信号
- 检查时钟域同步
- 用逻辑分析仪抓取spectrum_valid

---

### Q2: BASE>0, 但H2=H3=0

**问题**：谐波检测逻辑失败

**检查**：
1. 禁用谐波门限后仍然为0？
2. harm2_amp, harm3_amp中间变量值？
3. bin计算是否正确？

**解决**：
```verilog
// 在signal_parameter_measure.v添加更多调试信号
output wire [15:0] dbg_harm2_amp,  // 中间变量
output wire [15:0] dbg_harm3_amp,
output wire [12:0] dbg_harm2_bin,  // bin位置
output wire [12:0] dbg_harm3_bin
```

---

### Q3: H2、H3有值，但TRG=0

**问题**：触发条件不满足

**检查代码**：
```verilog
// 行1395-1400
if ((fft_harmonic_2 + fft_harmonic_3 + fft_harmonic_4 + fft_harmonic_5) > 16'd0 
    && fft_max_amp > 16'd100) begin
    thd_calc_trigger <= 1'b1;
```

**可能原因**：
- fft_max_amp < 100（基波门限过高）
- 谐波和仍然=0（4、5次谐波也需要检查）

**解决**：
- 输出H4、H5到UART（已包含在代码中，但未显示）
- 降低fft_max_amp门限至50

---

### Q4: TRG=1, VAL=0

**问题**：流水线未执行

**检查代码**：
```verilog
// 行1421
if (thd_calc_trigger && fundamental_power > 32'd100) begin
    thd_pipe_valid[0] <= 1'b1;
end
```

**可能原因**：
- fundamental_power = fft_max_amp^2 仍然<100
- 这几乎不可能（BASE>1000时，功率>1,000,000）

**解决**：
- 添加fundamental_power到UART输出
- 检查乘法器是否正常

---

### Q5: TRG=1, VAL=1, 但THD=0.0%

**问题**：LUT查表或滤波器问题

**检查**：
1. thd_product值（LUT输出）
2. thd_filtered值（滤波后）
3. thd_out值（最终输出）

**解决**：
- 添加这些信号到UART
- 使用逻辑分析仪抓取
- 检查LUT数据是否正确生成

---

## 📝 调试记录模板

```
测试日期：____年__月__日
FPGA版本：THD修复v5 + UART调试

输入信号：____MHz ____波 ____Vpp

UART输出：
===STATUS===
Mode:_ Run:_ CH1:_ CH2:_ Trig:_ FIFO:____ FFT:____ Test:_ 
H2:____ H3:____ BASE:____ TRG:_ VAL:_

HDMI显示：
THD: ___.__%

分析：
□ FFT工作正常 (BASE>1000)
□ 谐波被检测到 (H2、H3>0)
□ 触发条件满足 (TRG=1)
□ 流水线执行 (VAL=1)
□ THD正确显示

问题定位：
_____________________________________________

下一步：
_____________________________________________
```

---

## 🚀 快速诊断命令

如果您提供UART输出，我可以立即分析问题：

**示例1**：
```
H2:0000 H3:0000 BASE:0000 TRG:0 VAL:0
→ FFT没有数据，检查spectrum_valid信号
```

**示例2**：
```
H2:0000 H3:0000 BASE:5234 TRG:0 VAL:0
→ 基波检测到，但谐波全为0，检查谐波bin计算
```

**示例3**：
```
H2:0123 H3:0234 BASE:5234 TRG:1 VAL:1
→ 一切正常！如果THD仍=0，问题在显示模块
```

---

## 💡 小技巧

1. **记录连续输出**：使用串口软件的"Log to File"功能
2. **对比不同波形**：切换正弦/方波，观察谐波变化
3. **改变频率**：从100kHz→1MHz，观察BASE和谐波的变化
4. **FFT计数**：FFT值应该每秒递增约30次（35MHz/8192/128≈33）

---

**编译并测试后，请将UART输出贴给我分析！** 📊
