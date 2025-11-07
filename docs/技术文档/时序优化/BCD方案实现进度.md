# BCD直接存储方案实现进度

## 已完成 ✅

### 1. auto_test.v 重构完成
- ✅ 添加BCD格式寄存器（freq/amp/duty/thd的每一位）
- ✅ 添加Binary↔BCD转换函数
- ✅ 修改阈值调整逻辑，同步更新Binary和BCD
- ✅ 添加BCD输出端口（28个新端口）
- ✅ 编译通过，无语法错误

### 2. signal_analyzer_top.v 部分完成
- ✅ 添加BCD信号线定义
- ✅ 连接auto_test模块的BCD输出端口
- ⏳ **待完成**：连接到hdmi_display_ctrl模块

## 待完成 🔧

### 3. hdmi_display_ctrl.v 修改（关键）
需要完成以下修改：

#### 3.1 添加BCD输入端口
```verilog
// 在模块端口定义中添加（约在Line 60附近）
input  wire [3:0]   freq_min_d0, freq_min_d1, freq_min_d2,
input  wire [3:0]   freq_min_d3, freq_min_d4, freq_min_d5,
input  wire [3:0]   freq_max_d0, freq_max_d1, freq_max_d2,
input  wire [3:0]   freq_max_d3, freq_max_d4, freq_max_d5,
input  wire [3:0]   amp_min_d0, amp_min_d1, amp_min_d2, amp_min_d3,
input  wire [3:0]   amp_max_d0, amp_max_d1, amp_max_d2, amp_max_d3,
input  wire [3:0]   duty_min_d0, duty_min_d1, duty_min_d2, duty_min_d3,
input  wire [3:0]   duty_max_d0, duty_max_d1, duty_max_d2, duty_max_d3,
input  wire [3:0]   thd_max_d0, thd_max_d1, thd_max_d2, thd_max_d3,
```

#### 3.2 删除BCD转换逻辑
需要删除以下代码（约在Line 730-780）：
```verilog
// 删除这些除法运算！
if (v_cnt == 12'd0 && h_cnt == 12'd215) begin
    freq_min_d0 <= freq_min_khz % 10;
    freq_min_d1 <= (freq_min_khz / 10) % 10;
    freq_min_d2 <= (freq_min_khz / 100) % 10;
    freq_min_d3 <= (freq_min_khz / 1000) % 10;
    freq_min_d4 <= (freq_min_khz / 10000) % 10;
    freq_min_d5 <= (freq_min_khz / 100000) % 10;
end
// ... 类似的代码还有freq_max, amp_min/max, duty_min/max, thd_max
```

#### 3.3 改为直接使用BCD输入
将原来的BCD寄存器声明（Line 268-290）改为wire或删除：
```verilog
// 删除或改为wire：
reg [3:0] freq_min_d0, freq_min_d1, ...  // 现在这些是输入端口了
```

#### 3.4 修改字符显示逻辑
字符显示部分（Line 2480-2650）不需要修改，因为它直接使用`freq_min_d0`等信号，
只是这些信号从"内部计算的reg"变成了"外部传入的input"。

### 4. signal_analyzer_top.v 完成连接
在hdmi_display_ctrl实例化中添加BCD端口连接（Line 1980附近）：
```verilog
hdmi_display_ctrl u_hdmi_ctrl (
    // ... 现有端口 ...
    
    // 新增BCD格式输入
    .freq_min_d0(freq_min_d0), .freq_min_d1(freq_min_d1), .freq_min_d2(freq_min_d2),
    .freq_min_d3(freq_min_d3), .freq_min_d4(freq_min_d4), .freq_min_d5(freq_min_d5),
    .freq_max_d0(freq_max_d0), .freq_max_d1(freq_max_d1), .freq_max_d2(freq_max_d2),
    .freq_max_d3(freq_max_d3), .freq_max_d4(freq_max_d4), .freq_max_d5(freq_max_d5),
    .amp_min_d0(amp_min_d0), .amp_min_d1(amp_min_d1), .amp_min_d2(amp_min_d2), .amp_min_d3(amp_min_d3),
    .amp_max_d0(amp_max_d0), .amp_max_d1(amp_max_d1), .amp_max_d2(amp_max_d2), .amp_max_d3(amp_max_d3),
    .duty_min_d0(duty_min_d0), .duty_min_d1(duty_min_d1), .duty_min_d2(duty_min_d2), .duty_min_d3(duty_min_d3),
    .duty_max_d0(duty_max_d0), .duty_max_d1(duty_max_d1), .duty_max_d2(duty_max_d2), .duty_max_d3(duty_max_d3),
    .thd_max_d0(thd_max_d0), .thd_max_d1(thd_max_d1), .thd_max_d2(thd_max_d2), .thd_max_d3(thd_max_d3),
    
    // ... 其他端口 ...
);
```

## 预期效果 🎯

### 时序改善
- **HDMI域（74.25MHz）**：
  - 当前WNS: -21.199ns（除法运算导致）
  - 预期WNS: 0ns或正值（完全消除除法）
  - **改善幅度：~20ns** ✨
  
- **100MHz域**：
  - Binary→BCD转换在调整时进行，非关键路径
  - BCD→Binary转换用于测试比较，使用乘法（可接受）

### 代码质量
- ✅ 彻底消除HDMI域的除法运算
- ✅ 保持十进制显示，用户友好
- ✅ Binary格式保留用于测试比较
- ⚠️ 代码量略增加（但逻辑更清晰）

## 下一步操作 📝

1. **修改 hdmi_display_ctrl.v**
   - 添加BCD输入端口
   - 删除Line 730-780的BCD转换逻辑
   - 删除BCD寄存器声明

2. **完成 signal_analyzer_top.v 连接**
   - 在hdmi_display_ctrl实例化中添加BCD端口连接

3. **编译验证**
   - 检查语法错误
   - 运行综合
   - 检查时序报告

4. **Git提交**
   - 提交所有修改
   - 创建对比文档

## 技术亮点 💡

这个方案的核心思想是：
> **将计算从时序紧张的HDMI域转移到时序宽松的100MHz域，
> 并通过直接传递结果（而非原始数据）来避免重复计算。**

这是一个典型的**时序优化设计模式**：
1. **跨时钟域数据传递** - 传递处理结果而非原始数据
2. **预计算** - 在空闲时间提前计算
3. **数据格式优化** - 使用显示友好的BCD格式存储

类似的优化手法可以应用到其他模块，如：
- 相位差的三角函数计算
- THD的RMS计算
- AI识别的神经网络推理
