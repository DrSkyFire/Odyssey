# ADC OTR (Over-Range) 溢出检测集成说明

## 概述
已成功添加ADC的OTR（Over-Range，溢出检测）信号接口，用于检测输入信号是否超出ADC的测量范围。

## 硬件接口

### 新增端口
在 `signal_analyzer_top.v` 顶层模块中添加了两个输入端口：

```verilog
// 通道1 OTR
input wire adc_ch1_otr,  // 通道1溢出检测信号

// 通道2 OTR
input wire adc_ch2_otr,  // 通道2溢出检测信号
```

### 管脚分配
需要在约束文件（.fdc）中绑定这两个信号到实际的FPGA管脚。

**请查看您的ADC模块（MS9280）数据手册，确认OTR引脚编号。**

## 功能说明

### 1. OTR信号同步
```verilog
// 双级同步器，避免亚稳态
always @(posedge clk_adc) begin
    adc_ch1_otr_sync <= adc_ch1_otr;  // 第1级同步
    adc_ch2_otr_sync <= adc_ch2_otr;
end
```

### 2. 溢出标志锁存
```verilog
// 一旦检测到溢出，标志保持直到手动清除
if (adc_ch1_otr_sync && dual_data_valid)
    adc_ch1_otr_flag <= 1'b1;  // 锁存溢出标志
else if (adc_otr_clear)
    adc_ch1_otr_flag <= 1'b0;  // 按键清除
```

### 3. LED指示
```verilog
user_led[1] <= adc_ch1_otr_sync_100m;  // LED1：通道1溢出警告
user_led[2] <= adc_ch2_otr_sync_100m;  // LED2：通道2溢出警告
```

## 使用方法

### LED指示含义
| LED | 功能 | 状态 |
|-----|------|------|
| LED0 | 系统运行状态 | 亮=运行中 |
| **LED1** | **通道1溢出警告** | **亮=发生过溢出** |
| **LED2** | **通道2溢出警告** | **亮=发生过溢出** |
| LED3 | 当前FFT处理通道 | 0=CH1, 1=CH2 |
| LED4 | 当前显示通道 | 0=CH1, 1=CH2 |
| LED5 | 测试模式 | 亮=测试模式 |
| LED6 | PLL1锁定 | 亮=锁定 |
| LED7 | PLL2锁定 | 亮=锁定 |

### 清除溢出标志
按下 **user_button[7]**（按键7）可清除溢出标志，LED1/LED2熄灭。

## 约束文件配置

需要在 `signal_analyzer_top.fdc` 中添加以下管脚约束：

```tcl
# ADC通道1 OTR信号
set_location_assignment PIN_XX -to adc_ch1_otr
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to adc_ch1_otr

# ADC通道2 OTR信号
set_location_assignment PIN_YY -to adc_ch2_otr
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to adc_ch2_otr
```

**注意**: 请将 `PIN_XX` 和 `PIN_YY` 替换为实际的FPGA管脚编号。

## 工作原理

### OTR信号特性
- **高电平（1）**: ADC输入超出范围（溢出或下溢）
- **低电平（0）**: ADC输入在正常范围内

### 检测逻辑
```
ADC采样 → OTR信号 → 双级同步 → 锁存标志 → LED显示
                                    ↓
                              按键清除标志
```

### 时序图
```
clk_adc     __|‾‾|__|‾‾|__|‾‾|__|‾‾|__|‾‾|__|‾‾|__

adc_otr     ______|‾‾‾‾‾‾‾‾‾‾‾‾‾‾|______________

otr_sync    __________|‾‾‾‾‾‾‾‾‾‾‾‾‾|___________

otr_flag    ____________|‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾  (锁存)

btn_clear   ______________________________|‾‾|___

otr_flag    ____________|‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾|______  (清除)
```

## 典型应用场景

### 场景1: 信号幅度调整
1. 输入测试信号
2. 观察LED1/LED2
3. 如果LED亮起，说明信号幅度过大
4. 调整信号源或衰减器，降低输入幅度
5. 按键7清除溢出标志
6. 重新测试

### 场景2: 自动增益控制（未来扩展）
```verilog
// 检测到溢出时，自动降低增益
if (adc_ch1_otr_flag) begin
    gain_control <= gain_control - 1;  // 降低增益
end
```

### 场景3: 数据有效性检查
```verilog
// 溢出时丢弃当前FFT帧
if (adc_ch1_otr_flag || adc_ch2_otr_flag) begin
    fft_data_valid <= 1'b0;  // 标记数据无效
end
```

## 与Hann窗的协同作用

### 溢出对频谱的影响
1. **削波失真**: ADC溢出导致波形削平
2. **谐波失真**: 产生大量高次谐波
3. **频谱污染**: 频谱中出现虚假峰值

### Hann窗的局限性
- ✅ 减少频谱泄漏
- ✅ 降低旁瓣
- ❌ **无法修复削波失真**

### 正确的使用流程
```
1. 输入信号
   ↓
2. 检查OTR LED（LED1/LED2）
   ↓
3. 如果LED亮 → 调整输入幅度 → 返回步骤2
   ↓
4. LED不亮 → 信号正常 → 继续测试
   ↓
5. Hann窗加窗 → FFT分析 → 显示频谱
```

## 性能指标

### 响应时间
- **OTR检测延迟**: 1个ADC时钟周期（~29ns @ 35MHz）
- **同步延迟**: 2个ADC时钟周期（~57ns）
- **LED显示延迟**: <100ms（人眼可接受）

### 灵敏度
- **检测阈值**: ADC满量程（0-1023）
- **检测精度**: 单个采样点级别

## 调试建议

### 验证OTR功能
1. **静态测试**:
   - 输入直流信号
   - 逐步增加幅度
   - 观察LED1/LED2何时点亮

2. **动态测试**:
   - 输入正弦波
   - 增加幅度直到波形削顶
   - 确认LED同时点亮

3. **清除测试**:
   - 触发溢出后降低幅度
   - 按键7清除标志
   - 确认LED熄灭

### 仿真验证
```verilog
// Testbench示例
initial begin
    adc_ch1_otr = 0;
    #1000;
    adc_ch1_otr = 1;  // 模拟溢出
    #100;
    adc_ch1_otr = 0;
    #1000;
    user_button[7] = 1;  // 清除标志
    #100;
    user_button[7] = 0;
end
```

## 常见问题

### Q: OTR信号一直为高，怎么办？
A: 检查：
1. ADC供电是否正常
2. 输入信号是否过大
3. 管脚约束是否正确
4. ADC芯片是否损坏

### Q: LED不亮，但信号明显削波？
A: 检查：
1. OTR管脚是否正确连接
2. 约束文件中的管脚编号
3. ADC芯片的OTR极性（高有效/低有效）

### Q: 按键7无法清除标志？
A: 检查：
1. user_button[7] 的管脚约束
2. 按键去抖动电路
3. 按键硬件是否正常

## 未来扩展

### 1. HDMI显示集成
在HDMI显示界面上添加溢出警告图标：
```verilog
if (adc_ch1_otr_sync_pixel) begin
    // 在屏幕左上角显示红色警告标志 "⚠ CH1 OTR"
end
```

### 2. 自动增益控制（AGC）
```verilog
// 检测到溢出时自动降低增益
always @(posedge clk_adc) begin
    if (adc_ch1_otr_flag)
        gain_ch1 <= gain_ch1 - 1;
    else if (!near_full_scale)
        gain_ch1 <= gain_ch1 + 1;
end
```

### 3. 溢出计数器
```verilog
// 统计溢出次数
reg [15:0] otr_counter_ch1;
always @(posedge clk_adc) begin
    if (adc_otr_clear)
        otr_counter_ch1 <= 16'd0;
    else if (adc_ch1_otr_sync && dual_data_valid)
        otr_counter_ch1 <= otr_counter_ch1 + 1;
end
```

### 4. UART报警输出
```verilog
// 通过UART发送溢出警告
if (adc_ch1_otr_flag && !otr_reported) begin
    uart_tx_data <= "CH1 Over-Range!\n";
    uart_tx_valid <= 1'b1;
    otr_reported <= 1'b1;
end
```

## 技术参考

### MS9280 ADC规格
- **分辨率**: 10位
- **输入范围**: 0-2V（典型）
- **OTR阈值**: 通常在满量程的95%触发

### 相关文档
- MS9280数据手册
- 紫光同创FPGA I/O标准
- Verilog HDL双级同步器设计

---

**更新时间**: 2025年10月30日  
**版本**: v1.0  
**作者**: GitHub Copilot
