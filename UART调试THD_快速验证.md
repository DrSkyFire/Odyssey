# UART调试THD - 快速验证清单

## ✅ 修改内容摘要

### 1. signal_parameter_measure.v
**新增端口**（第53-61行）：
```verilog
// 调试输出 (THD计算链路)
output wire [15:0]  dbg_fft_harmonic_2,  // 2次谐波幅度
output wire [15:0]  dbg_fft_harmonic_3,  // 3次谐波幅度
output wire [15:0]  dbg_fft_harmonic_4,  // 4次谐波幅度
output wire [15:0]  dbg_fft_harmonic_5,  // 5次谐波幅度
output wire [31:0]  dbg_harmonic_sum,    // 谐波总和
output wire [15:0]  dbg_fft_max_amp,     // 基波幅度
output wire         dbg_calc_trigger,    // THD计算触发
output wire [2:0]   dbg_pipe_valid       // 流水线有效标志
```

**新增连接**（模块末尾）：
```verilog
assign dbg_fft_harmonic_2 = fft_harmonic_2;
assign dbg_fft_harmonic_3 = fft_harmonic_3;
assign dbg_fft_harmonic_4 = fft_harmonic_4;
assign dbg_fft_harmonic_5 = fft_harmonic_5;
assign dbg_harmonic_sum   = thd_harmonic_sum;
assign dbg_fft_max_amp    = fft_max_amp;
assign dbg_calc_trigger   = thd_calc_trigger;
assign dbg_pipe_valid     = thd_pipe_valid;
```

---

### 2. signal_analyzer_top.v

**新增信号定义**（第242-250行）：
```verilog
// 通道1 THD调试信号
wire [15:0] ch1_dbg_harmonic_2;
wire [15:0] ch1_dbg_harmonic_3;
wire [15:0] ch1_dbg_harmonic_4;
wire [15:0] ch1_dbg_harmonic_5;
wire [31:0] ch1_dbg_harmonic_sum;
wire [15:0] ch1_dbg_fft_max_amp;
wire        ch1_dbg_calc_trigger;
wire [2:0]  ch1_dbg_pipe_valid;
```

**修改CH1参数测量模块实例化**（第1423-1440行）：
```verilog
signal_parameter_measure u_ch1_param_measure (
    // ... 原有端口 ...
    
    // 调试输出
    .dbg_fft_harmonic_2 (ch1_dbg_harmonic_2),
    .dbg_fft_harmonic_3 (ch1_dbg_harmonic_3),
    .dbg_fft_harmonic_4 (ch1_dbg_harmonic_4),
    .dbg_fft_harmonic_5 (ch1_dbg_harmonic_5),
    .dbg_harmonic_sum   (ch1_dbg_harmonic_sum),
    .dbg_fft_max_amp    (ch1_dbg_fft_max_amp),
    .dbg_calc_trigger   (ch1_dbg_calc_trigger),
    .dbg_pipe_valid     (ch1_dbg_pipe_valid)
);
```

**新增UART状态**（第2333行）：
```verilog
localparam UART_SEND_THD_DBG  = 8'd65;  // THD调试信息
```

**新增UART发送状态机**（第2590-2655行）：
```verilog
UART_SEND_THD_DBG: begin
    // 发送 "H2:XXXX H3:XXXX BASE:XXXX TRG:X VAL:X "
    // (38个字符)
end
```

---

## 🔧 编译步骤

### 1. 在TD IDE中
1. 打开项目
2. 点击"Synthesize" → "Run"
3. 点击"Place & Route" → "Run"
4. 点击"Generate Bitstream"
5. 下载到FPGA

---

## 🖥️ 串口监视设置

### Windows - PuTTY
1. 下载PuTTY：https://www.putty.org/
2. 选择连接类型：Serial
3. Serial line: COM3（根据实际情况，使用设备管理器查看）
4. Speed: 115200
5. 点击Open

### VS Code - Serial Monitor
```powershell
# 安装扩展
code --install-extension ms-vscode.vscode-serial-monitor

# 使用：
# 1. Ctrl+Shift+P
# 2. 输入 "Serial Monitor"
# 3. 选择COM口和波特率115200
```

---

## 📊 预期输出

### 初始状态（无信号输入）
```
===STATUS===
Mode:P Run:1 CH1:1 CH2:1 Trig:A FIFO:8192 FFT:0000 Test:0 
H2:0000 H3:0000 BASE:0000 TRG:0 VAL:0
```

### 输入1MHz方波，3Vpp后
```
===STATUS===
Mode:P Run:1 CH1:1 CH2:1 Trig:A FIFO:8192 FFT:0123 Test:0 
H2:0025 H3:1234 BASE:5678 TRG:1 VAL:1
```

**关键检查**：
- ✅ BASE > 1000：FFT正常工作
- ✅ H3 > 500：检测到3次谐波
- ✅ TRG = 1：THD计算被触发
- ✅ VAL = 1：流水线执行
- ✅ **如果以上都满足，但HDMI显示THD=0.0%，问题在显示模块或LUT**

---

## 🎯 测试流程

### 测试1：系统自检
- [ ] 编译无错误
- [ ] 下载成功
- [ ] 串口能打开，波特率115200
- [ ] 每秒收到一条"===STATUS==="信息
- [ ] Mode显示"P"（参数测量模式）
- [ ] Run显示"1"（运行中）

### 测试2：无信号输入
- [ ] BASE = 0或很小（<100）
- [ ] 所有谐波 = 0
- [ ] TRG = 0
- [ ] VAL = 0
- [ ] HDMI显示THD = 0.0%

### 测试3：1MHz方波，3Vpp输入
- [ ] BASE > 1000（记录实际值：______）
- [ ] H2值：______
- [ ] H3值：______（应该是BASE的20-40%）
- [ ] TRG = ____（应该是1）
- [ ] VAL = ____（应该是1）
- [ ] HDMI显示THD = ____%（应该40-55%）

### 测试4：1MHz正弦波，3Vpp输入
- [ ] BASE > 1000（应该与方波类似）
- [ ] H2、H3 < 100（正弦波谐波很小）
- [ ] TRG = ____
- [ ] VAL = ____
- [ ] HDMI显示THD = ____%（应该<5%）

---

## 🐛 故障诊断快速参考

| UART输出 | 问题定位 | 解决方向 |
|----------|----------|----------|
| BASE=0 | FFT无数据 | 检查spectrum_valid、FFT使能 |
| BASE>0, H2=H3=0 | 谐波检测失败 | 检查bin计算、搜索窗口 |
| H2、H3>0, TRG=0 | 触发条件不满足 | 检查fft_max_amp门限、谐波和计算 |
| TRG=1, VAL=0 | 流水线未执行 | 检查fundamental_power |
| TRG=1, VAL=1, THD=0 | 计算或显示问题 | 检查LUT、滤波器、显示模块 |

---

## 📸 请提供以下信息

编译并测试后，请将以下内容发给我：

### 1. 串口输出（至少5行）
```
粘贴实际UART输出：




```

### 2. 输入信号
- 波形类型：____波
- 频率：____MHz
- 幅度：____Vpp

### 3. HDMI显示
- 频率显示：________
- 幅度显示：________
- THD显示：________%

### 4. FFT频谱
- 能否看到基波峰值？____
- 能否看到谐波峰值？____
- 谐波是否清晰可见？____

---

## ⚡ 快速测试命令

如果您想快速验证数值格式是否正确：

```powershell
# 转换十进制到4位十六进制显示
python -c "val=5234; print(f'H2:{val:04X}'); print(f'十进制{val}')"

# 输出示例：
# H2:1472
# 十进制5234
```

**UART输出是4位数字（0-9），代表0-9999的十进制值**

示例：
- "H2:1234" → H2幅度 = 1234（十进制）
- "BASE:5678" → 基波幅度 = 5678（十进制）

---

## 🚀 立即开始

1. ✅ 代码已修改
2. ⏳ 编译项目
3. ⏳ 下载到FPGA
4. ⏳ 打开串口监视器
5. ⏳ 输入1MHz方波
6. ⏳ 观察输出并报告

**期待您的测试结果！** 📊
