# 紫光同创PDS平台 - Hann窗ROM集成指南

## 概述
紫光同创FPGA使用Verilog的 `$readmemh` 系统函数直接初始化RAM，不需要像Xilinx/Altera那样配置IP核。

## 快速集成（3步完成）

### 步骤1: 复制HEX文件到工程根目录
在PowerShell中执行：
```powershell
Copy-Item ipcore\hann_window\hann_window_8192.hex .\
```

### 步骤2: 修改Verilog代码路径
打开 `source\source\dual_channel_fft_controller.v`，找到第78-81行：
```verilog
// 初始化Hann窗ROM
initial begin
    $readmemh("ipcore/hann_window/hann_window_8192.hex", hann_window_rom);
end
```

改为：
```verilog
// 初始化Hann窗ROM
initial begin
    $readmemh("hann_window_8192.hex", hann_window_rom);
end
```

### 步骤3: 重新编译工程
1. 打开PDS IDE
2. **Project** → **Clean** (清理旧编译文件)
3. **Project** → **Synthesize** (综合)
4. 查看综合报告，确认Block RAM增加约16Kbit

## 完成！现在可以下载到FPGA测试了

---

## 详细说明

### 紫光同创ROM初始化原理
```verilog
// Verilog标准语法，所有FPGA都支持
reg [15:0] my_rom [0:8191];  // 声明8192个16位寄存器
initial begin
    $readmemh("data.hex", my_rom);  // 从HEX文件初始化
end
```

### HEX文件格式
```
0000
0019
0065
00E4
...
7FFF  // 中间值（最大）
...
0019
0000
```
每行一个16进制值，共8192行。

### 综合后的实现
- **仿真**: `initial` 块在仿真时执行，ROM被正确初始化
- **综合**: PDS综合器识别这种模式，将其映射到Block RAM并烧录初始值

### 资源消耗
| 资源类型 | 消耗量 | 说明 |
|---------|--------|------|
| Block RAM | 16 Kbit | 8192 × 16位 |
| DSP | 1个 | 16位×16位乘法器 |
| LUT | ~50个 | 控制逻辑 |

---

## 故障排除

### 问题1: 综合报告显示ROM未初始化
**原因**: PDS找不到HEX文件

**解决方法**:
1. 检查HEX文件是否存在：
   ```powershell
   Test-Path .\hann_window_8192.hex
   # 应该返回 True
   ```

2. 尝试使用绝对路径：
   ```verilog
   $readmemh("E:/Odyssey_proj/hann_window_8192.hex", hann_window_rom);
   ```

3. 查看PDS综合日志：
   - **Tools** → **Message Window** → 搜索 "readmemh"
   - 查看是否有文件读取错误

### 问题2: 仿真时ROM数据错误
**原因**: 仿真工作目录与HEX文件路径不匹配

**解决方法**:
在仿真脚本中设置正确路径：
```tcl
# 在ModelSim .do文件中
vlog +define+HEX_PATH="E:/Odyssey_proj/ipcore/hann_window/"
```

然后修改Verilog：
```verilog
`ifdef HEX_PATH
    $readmemh({`HEX_PATH, "hann_window_8192.hex"}, hann_window_rom);
`else
    $readmemh("hann_window_8192.hex", hann_window_rom);
`endif
```

### 问题3: 时序违例
**原因**: ROM读取或乘法器延迟过大

**解决方法**:
添加流水线寄存器：
```verilog
// 原始代码（已有1级流水线）
always @(posedge clk)
    window_coeff <= hann_window_rom[send_cnt];

// 如果还需要更多流水线（添加第2级）
reg [15:0] window_coeff_d1;
always @(posedge clk) begin
    window_coeff    <= hann_window_rom[send_cnt];
    window_coeff_d1 <= window_coeff;
end
```

---

## 验证方法

### 1. 综合后检查
综合完成后，查看资源报告：
```
Block RAM Usage:
  Before: XX Kbit
  After:  XX + 16 Kbit  ← 应该增加16Kbit
```

### 2. 仿真验证
运行仿真，检查ROM数据：
```verilog
// 在Testbench中添加
initial begin
    #100;  // 等待初始化
    $display("ROM[0] = %h (应该是0000)", dut.u_fft_ctrl.hann_window_rom[0]);
    $display("ROM[4096] = %h (应该是7FFF)", dut.u_fft_ctrl.hann_window_rom[4096]);
    $display("ROM[8191] = %h (应该是0000)", dut.u_fft_ctrl.hann_window_rom[8191]);
end
```

### 3. 板级测试
下载到FPGA后，观察频谱显示：
- ✅ 频谱跳动明显减少
- ✅ 背景噪声更平滑
- ✅ 弱信号更清晰

---

## 与Xilinx/Altera的区别

| 平台 | ROM初始化方法 | 配置文件 |
|------|--------------|----------|
| **紫光同创** | **`$readmemh` (Verilog)** | **HEX** |
| Xilinx | Block Memory Generator IP | COE |
| Altera | RAM IP Megafunction | MIF |
| Lattice | IPexpress Memory | MEM |
| Gowin | IP Core Generator | MI/MIF |

### 紫光同创的优势
✅ 无需配置IP核，代码即配置
✅ 便于版本控制（纯文本）
✅ 跨平台兼容性好（标准Verilog语法）

---

## 常见问题

**Q: 为什么有COE和MIF文件？**
A: 这些文件是为了兼容Xilinx/Altera平台自动生成的，紫光同创只需要HEX文件。

**Q: HEX文件必须放在根目录吗？**
A: 不是必须，但放在根目录最简单。也可以使用相对/绝对路径。

**Q: 能否使用IP核配置ROM？**
A: 紫光同创也有ROM IP核，但 `$readmemh` 更灵活，推荐使用。

**Q: 综合需要多久？**
A: 增加Hann窗后，综合时间大约增加5-10秒（取决于机器性能）。

---

## 技术支持

### 文档资源
- 紫光同创官方文档：[Pango Design Suite用户手册]
- Verilog语法参考：IEEE 1364标准

### 联系方式
- 项目仓库：https://github.com/DrSkyFire/Odyssey
- 问题反馈：提交GitHub Issue

---

**更新时间**: 2025年10月30日  
**适用平台**: 紫光同创 (Pango Design Suite)  
**作者**: GitHub Copilot
