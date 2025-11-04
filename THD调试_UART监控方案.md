# THD调试 - UART实时监控方案

## 📌 修改摘要

由于THD显示始终为0.0%，即使禁用所有谐波门限后依然如此，我们添加了UART调试输出来实时监控THD计算链路的关键信号。

---

## 🔧 修改的文件

### 1. `signal_parameter_measure.v`
**修改内容**：
- ✅ 新增8个调试输出端口（dbg_*）
- ✅ 输出THD计算链路的关键中间变量

**新增端口**：
```verilog
output wire [15:0]  dbg_fft_harmonic_2,  // 2次谐波幅度
output wire [15:0]  dbg_fft_harmonic_3,  // 3次谐波幅度  
output wire [15:0]  dbg_fft_harmonic_4,  // 4次谐波幅度
output wire [15:0]  dbg_fft_harmonic_5,  // 5次谐波幅度
output wire [31:0]  dbg_harmonic_sum,    // 谐波总和
output wire [15:0]  dbg_fft_max_amp,     // 基波幅度
output wire         dbg_calc_trigger,    // THD计算触发
output wire [2:0]   dbg_pipe_valid       // 流水线有效标志
```

---

### 2. `signal_analyzer_top.v`
**修改内容**：
- ✅ 新增CH1调试信号定义
- ✅ 连接CH1参数测量模块的调试端口
- ✅ 扩展UART状态机，新增THD_DBG状态
- ✅ 每秒通过UART发送THD调试信息

**UART输出格式**：
```
===STATUS===
Mode:P Run:1 CH1:1 CH2:1 Trig:A FIFO:8192 FFT:0123 Test:0 
H2:0123 H3:0456 BASE:5678 TRG:1 VAL:1
```

---

## 📊 调试信号含义

| 信号 | 变量名 | 含义 | 正常值(1MHz方波) |
|------|--------|------|------------------|
| **H2** | fft_harmonic_2 | 2次谐波幅度 | 少量(偶次谐波小) |
| **H3** | fft_harmonic_3 | 3次谐波幅度 | 1500-2500 |
| **BASE** | fft_max_amp | 基波幅度 | 5000-8000 |
| **TRG** | thd_calc_trigger | THD计算触发 | 1 |
| **VAL** | thd_pipe_valid[2] | 流水线有效 | 1 |

---

## 🎯 诊断逻辑

### 场景1：BASE=0
**问题**：FFT没有输出数据
**排查**：
- spectrum_valid信号
- dual_channel_fft_controller模块
- ADC采样是否正常

---

### 场景2：BASE>0, H2=H3=0
**问题**：谐波检测逻辑失败
**排查**：
- 谐波bin计算（harm2_bin, harm3_bin）
- 谐波搜索窗口（±3 bin）
- spectrum_addr扫描过程

---

### 场景3：H2、H3>0, TRG=0
**问题**：触发条件不满足
**排查**：
```verilog
// 行1395
if ((fft_harmonic_2 + fft_harmonic_3 + fft_harmonic_4 + fft_harmonic_5) > 16'd0 
    && fft_max_amp > 16'd100)
```
- 检查H4、H5是否也为0
- 检查BASE是否<100

---

### 场景4：TRG=1, VAL=0
**问题**：流水线未启动
**排查**：
```verilog
// 行1421
if (thd_calc_trigger && fundamental_power > 32'd100)
```
- fundamental_power = fft_max_amp^2
- BASE>1000时，功率应该>1,000,000

---

### 场景5：TRG=1, VAL=1, THD=0.0%
**问题**：LUT或显示模块问题
**排查**：
- thd_product（LUT输出）
- thd_filtered（滤波后）
- table_display模块的THD显示逻辑

---

## 🧪 测试流程

### 第一步：编译下载
1. TD IDE编译项目
2. 生成bitstream
3. 下载到FPGA

### 第二步：打开串口
- 波特率：115200
- 数据位：8
- 停止位：1
- 无校验

**推荐工具**：
- PuTTY
- TeraTerm
- VS Code + Serial Monitor

### 第三步：输入测试信号
**信号1**：1MHz方波，3Vpp
**预期输出**：
```
H2:0050 H3:1500 BASE:6000 TRG:1 VAL:1
```

**信号2**：1MHz正弦波，3Vpp
**预期输出**：
```
H2:0020 H3:0015 BASE:6000 TRG:0 VAL:0
```

### 第四步：分析结果
对比UART输出和HDMI显示，定位问题环节。

---

## 📋 测试记录表

| 测试项 | 输入信号 | UART输出 | HDMI THD | 结论 |
|--------|----------|----------|----------|------|
| 测试1 | 1MHz方波 3Vpp | H2:____ H3:____ BASE:____ TRG:__ VAL:__ | ____% | ____ |
| 测试2 | 1MHz正弦 3Vpp | H2:____ H3:____ BASE:____ TRG:__ VAL:__ | ____% | ____ |
| 测试3 | 100kHz方波 3Vpp | H2:____ H3:____ BASE:____ TRG:__ VAL:__ | ____% | ____ |

---

## 💡 关键检查点

### ✅ FFT工作正常
- [ ] BASE > 1000
- [ ] FFT计数每秒递增约30次

### ✅ 谐波检测正常
- [ ] H3约为BASE的20-40%（方波）
- [ ] H2、H3 < BASE的1%（正弦波）

### ✅ 触发逻辑正常
- [ ] 方波时TRG=1
- [ ] 正弦波时TRG可能=0（谐波太小）

### ✅ 计算流水线正常
- [ ] TRG=1时，VAL=1

### ✅ 显示正常
- [ ] VAL=1时，HDMI THD>0%

---

## 🚨 已知问题回顾

### Bug 1-7修复历史
1. ✅ THD滤波器时序错误
2. ✅ 基波门限过高（200→100）
3. ✅ 谐波门限过高
4. ✅ 谐波bin时序错误
5. ✅ Hann窗不适用低频
6. ✅ THD触发只执行一次
7. ✅ 谐波门限完全禁用

### Bug 8：正在调查
**现象**：即使H2、H3有值，THD仍显示0.0%
**策略**：通过UART输出定位具体哪个环节出错

---

## 📞 下一步

**请执行以下操作**：

1. ✅ 编译项目（无错误）
2. ⏳ 下载到FPGA
3. ⏳ 打开串口监视器（115200波特率）
4. ⏳ 输入1MHz方波，3Vpp
5. ⏳ 记录UART输出
6. ⏳ 报告结果

**将UART输出粘贴给我，格式**：
```
===STATUS===
Mode:P Run:1 CH1:1 CH2:1 Trig:A FIFO:8192 FFT:0123 Test:0 
H2:____ H3:____ BASE:____ TRG:_ VAL:_

HDMI显示THD: ____%
```

根据您的输出，我将立即定位问题所在！

---

**修改日期**：2025年11月5日
**版本**：THD修复v6（UART调试版）
**状态**：待测试验证
**优先级**：P0（最高）
