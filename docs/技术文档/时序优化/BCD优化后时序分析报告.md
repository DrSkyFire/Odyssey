# BCD优化后时序分析报告

**报告日期**: 2025年11月7日  
**工具版本**: Fabric Compiler 2022.2-SP6.4  
**器件**: PGL50H-6 FBG484

---

## 一、时序概览

### 1.1 时序汇总（Slow Corner）

| 时钟域 | 频率 | 周期(ns) | WNS(ns) | TNS(ns) | 违例端点 | 总端点 | 状态 |
|--------|------|----------|---------|---------|----------|--------|------|
| **clk_100m** | 100.0 MHz | 10.0 | **-15.119** | **-2079.420** | **504/38449** | 38449 | ❌ **严重违例** |
| clk_10m | 10.0 MHz | 100.0 | +95.239 | 0.000 | 0/481 | 481 | ✅ 满足时序 |
| clk_adc | 35.0 MHz | 28.6 | +15.533 | 0.000 | 0/1524 | 1524 | ✅ 满足时序 |
| **clk_hdmi_pixel** | 74.25 MHz | 13.5 | **-3.337** | **-34.907** | **22/1947** | 1947 | ❌ **轻微违例** |

### 1.2 时序汇总（Fast Corner）

| 时钟域 | WNS(ns) | TNS(ns) | 违例端点 | 状态 |
|--------|---------|---------|----------|------|
| **clk_100m** | **-7.613** | **-708.955** | **104/38449** | ❌ 违例 |
| clk_hdmi_pixel | +1.561 | 0.000 | 0/1947 | ✅ 满足 |

**结论**: BCD优化后，HDMI域时序有**显著改善**（从-21.199ns提升到-3.337ns，改善了17.86ns），但100MHz域出现了**新的严重违例**。

---

## 二、100MHz域时序违例详细分析

### 2.1 最差路径 #1: adjust_step_mode → freq_max_d4[1]

**时序详情**:
- **WNS**: -15.119 ns
- **Logic Levels**: 37级组合逻辑
- **Logic Delay**: 11.025 ns (44.90%)
- **Route Delay**: 13.531 ns (55.10%)
- **Total Data Path**: 29.517 ns (需求14.398 ns)

**路径分析**:
```
起点: adjust_step_mode[0] (调节步进模式标志)
终点: u_auto_test/freq_max_d4[1] (频率上限BCD第4位)

关键路径组成:
1. adjust_step_mode[0] 触发器输出 (fanout=138) → 1.233ns布线延迟
2. 32位减法器链 (N6664.fsub_1 ~ fsub_31):
   - 16级进位链，每级0.058ns
   - 最后一级输出 0.501ns
   - 总计: 16×0.058 + 0.501 = 1.429ns
3. 超长的多路选择器级联 (25级):
   - N6873[0]_2 → N7001[2]_1 → N7058_mux3 → N7122_mux3_3_muxf6_perm
   - N7129[2]_1 → N7193[2]_4_muxf6_perm → N7257[2]_4_muxf6_perm
   - ... (继续级联)
   - 每级延迟: 0.2~0.5ns
   - 总计约: 8.7ns逻辑 + 7.1ns布线 = 15.8ns
4. BCD转换相关逻辑:
   - N8215_sum3 → N8291[1]_3 → N8348_mux3 → N8355[2]_1
   - N8417_sum3 → N8491_sum3 → N8565_sum3 → N8641[0]
   - 总计约: 2.9ns
```

**问题诊断**:

#### 🔴 **根本原因**: BCD转换的Double Dabble算法组合逻辑过深

尽管我们删除了HDMI域的除法运算，但在100MHz域的BCD转换中，`bin32_to_bcd6` function实现的Double Dabble算法包含：

1. **32位输入 → 6位BCD输出需要32次迭代**
2. **每次迭代包含**:
   - 移位操作（4bit×6个BCD位 = 24bit）
   - Add-3规则判断（6个if判断）
   - 条件加法（最多6次）
3. **总组合逻辑深度**: 32×(移位+6个条件判断) ≈ 200级逻辑

虽然综合工具会优化，但实际形成的37级逻辑仍然过深，导致15.119ns的违例。

#### 🟡 **次要原因**: 高扇出信号

- `adjust_step_mode[0]` 的fanout=138，导致1.233ns的布线延迟
- 多个中间信号fanout=4~13，增加布线拥塞

### 2.2 最差路径 #2: adjust_step_mode → freq_max_d5[0]

- **WNS**: -15.097 ns
- **Logic Levels**: 37级
- **与路径#1类似**，终点为BCD的另一位

### 2.3 最差路径 #3: adjust_step_mode → freq_max_d4[3]

- **WNS**: -14.955 ns
- **Logic Levels**: 37级
- **同样的问题模式**

---

## 三、HDMI域时序违例详细分析

### 3.1 最差路径: pixel_y_d1[4] → char_col[3]

**时序详情**:
- **WNS**: -3.337 ns
- **Logic Levels**: 24级组合逻辑
- **Logic Delay**: 6.730 ns (40.79%)
- **Route Delay**: 9.769 ns (59.21%)
- **Total Data Path**: 21.465 ns (需求18.128 ns)

**路径分析**:
```
起点: u_hdmi_ctrl/pixel_y_d1[4] (像素Y坐标延迟1拍)
终点: u_hdmi_ctrl/char_col[3] (字符列索引)

路径组成:
1. pixel_y_d1[4] 触发器输出 (fanout=32) → 0.644ns布线
2. Y坐标→字符行转换逻辑:
   - N4483_mux4 → N6103_3_muxf6 → N10307_3 → N10428_3
   - 总计: 4级，约2.2ns
3. 字符ROM地址计算:
   - N13093_2 → N11530_21[0]_muxf6 → N11530_22[0] → N11530_25[0] → N11530_27[0]
   - 总计: 5级，约2.3ns
4. 字符位图索引计算:
   - N11514_12[3]_4 → N11514_17[3] → N11514_19[3] → N11507_1[3]
   - N11507_2[3] → N11507_4[3] → N11507_6[3]
   - 总计: 7级，约2.1ns
5. 字符列提取:
   - N11474_136[3] → N11474_139[3] → N11470_26[3] → N11470_27[3]
   - N11459_25[3]_muxf6 → N11456_18[3] → N11456_20[3] → N11452_21[3]
   - 总计: 8级，约2.2ns
```

**问题诊断**:

#### 🟡 **主要原因**: 字符显示逻辑过于复杂

HDMI字符显示从像素坐标到字符位图的转换包含：
1. Y坐标 → 字符行号（需要除法，可能用查表或级联减法）
2. 字符行号 + X坐标 → 字符ASCII码（BRAM查表）
3. ASCII码 + 字符内行号 → 字符位图地址
4. 字符位图 + 字符内列号 → 像素值

虽然BCD优化消除了参数显示的除法，但字符坐标计算仍然包含大量组合逻辑。

#### ✅ **好消息**: 违例幅度可接受

- 从-21.199ns改善到-3.337ns，**改善了17.86ns (84.3%)**
- 剩余3.337ns违例可以通过以下方法解决（见第四章）

---

## 四、优化建议

### 4.1 100MHz域优化方案（优先级P0）

#### 方案A: BCD转换流水线化 ⭐⭐⭐⭐⭐ **强烈推荐**

**原理**: 将Double Dabble算法的32次迭代分解为多级流水线

**实现**:
```verilog
// 当前实现（组合逻辑）
function [23:0] bin32_to_bcd6(input [31:0] bin);
    // 32次迭代的组合逻辑 → 37级逻辑深度
endfunction

// 优化方案：4级流水线，每级8次迭代
module bcd_converter_pipelined (
    input clk,
    input [31:0] bin_in,
    input valid_in,
    output reg [23:0] bcd_out,
    output reg valid_out
);
    // Stage 1: 迭代0-7
    reg [31:0] bin_s1;
    reg [23:0] bcd_s1;
    reg valid_s1;
    
    always @(posedge clk) begin
        if (valid_in) begin
            // 执行8次Double Dabble迭代
            bin_s1 <= /* 迭代0-7结果 */;
            bcd_s1 <= /* 迭代0-7结果 */;
        end
        valid_s1 <= valid_in;
    end
    
    // Stage 2: 迭代8-15
    // Stage 3: 迭代16-23
    // Stage 4: 迭代24-31
    // ...
endmodule
```

**效果预期**:
- 组合逻辑深度从37级降低到约10级
- WNS从-15.119ns改善到约+2ns
- 增加4个时钟周期延迟（可接受，用户调参频率约1Hz）

**实施复杂度**: 中等（约200行代码，2小时工作量）

---

#### 方案B: BCD参数预存储 + 慢速更新 ⭐⭐⭐⭐

**原理**: 利用参数调整频率低（约1Hz）的特点，用时分复用降低并行度

**实现**:
```verilog
// 慢速状态机：调整参数时，分32个周期计算BCD
reg [5:0] bcd_conv_cnt;
reg [31:0] bin_temp;
reg [23:0] bcd_temp;
reg bcd_converting;

always @(posedge clk_100m) begin
    if (btn_limit_dn_up && !bcd_converting) begin
        // 启动BCD转换
        bin_temp <= freq_min + freq_step;
        bcd_temp <= 24'h0;
        bcd_conv_cnt <= 0;
        bcd_converting <= 1;
    end
    else if (bcd_converting) begin
        // 每周期执行1次Double Dabble迭代
        bcd_conv_cnt <= bcd_conv_cnt + 1;
        {bcd_temp, bin_temp} <= double_dabble_single_iter(bcd_temp, bin_temp);
        
        if (bcd_conv_cnt == 31) begin
            // 转换完成，更新寄存器
            {freq_min_d5, freq_min_d4, ..., freq_min_d0} <= bcd_temp;
            bcd_converting <= 0;
        end
    end
end

// 单次迭代函数（组合逻辑很浅）
function [55:0] double_dabble_single_iter(input [23:0] bcd, input [31:0] bin);
    reg [23:0] bcd_new;
    // 只有1次Add-3判断和移位
    bcd_new[3:0] = (bcd[3:0] >= 5) ? bcd[3:0] + 3 : bcd[3:0];
    // ... 其他5个BCD位
    double_dabble_single_iter = {bcd_new, bin} << 1;
endfunction
```

**效果预期**:
- 组合逻辑深度降低到约5级
- WNS改善到+5ns以上
- 增加32个周期延迟（320ns），对用户无感知

**实施复杂度**: 较低（约150行代码，1.5小时工作量）

---

#### 方案C: 触发器插入（Retiming） ⭐⭐⭐

**原理**: 利用EDA工具的自动优化，在长路径中插入流水线寄存器

**实现**:
```tcl
# 在综合约束中添加
set_property REGISTER_DUPLICATION TRUE [get_cells u_auto_test/*]
set_property MAX_FANOUT 16 [get_nets adjust_step_mode[0]]

# 使能物理优化
set_property PHYS_OPT_DESIGN TRUE [current_design]
place_design -directive ExtraPostPlacementOpt
phys_opt_design -directive AggressiveExplore
route_design -directive AggressiveExplore
```

**效果预期**:
- 可能改善2-5ns
- 需要多次迭代尝试
- 可能增加资源使用

**实施复杂度**: 低（只需修改TCL脚本）

---

#### 方案D: 简化调参逻辑 ⭐⭐⭐

**原理**: 减少`adjust_step_mode`的逻辑扇出

**实现**:
```verilog
// 当前实现：adjust_step_mode直接参与大量运算（fanout=138）
wire [31:0] freq_step = (adjust_step_mode == 0) ? 1000 :
                        (adjust_step_mode == 1) ? 10000 :
                        (adjust_step_mode == 2) ? 100000 : 1000000;

// 优化：预先注册步进值
reg [31:0] freq_step_reg;
always @(posedge clk_100m) begin
    freq_step_reg <= freq_step;  // 加一级寄存器
end

// 使用注册的步进值
if (btn_limit_dn_up && freq_min + freq_step_reg < freq_max) begin
    freq_min_new = freq_min + freq_step_reg;
    // ...
end
```

**效果预期**:
- 减少fanout，可能改善1-2ns
- 简单易行

**实施复杂度**: 极低（约10行代码，10分钟工作量）

---

### 4.2 HDMI域优化方案（优先级P1）

#### 方案E: 字符坐标计算流水线化 ⭐⭐⭐⭐

**原理**: 将像素坐标→字符位图的24级逻辑分解为多级流水线

**实现**:
```verilog
// 当前实现：单周期完成
assign char_col = f(pixel_y_d1);  // 24级组合逻辑

// 优化方案：3级流水线
reg [10:0] pixel_y_d2, pixel_y_d3;
reg [5:0] char_row_d2;
reg [7:0] char_ascii_d3;

// Stage 1: 像素Y → 字符行号
always @(posedge clk_hdmi_pixel) begin
    pixel_y_d2 <= pixel_y_d1;
    char_row_d2 <= pixel_y_d1[10:4];  // 除以16（移位代替除法）
end

// Stage 2: 字符行号 + X坐标 → ASCII码
always @(posedge clk_hdmi_pixel) begin
    pixel_y_d3 <= pixel_y_d2;
    char_ascii_d3 <= char_rom[{char_row_d2, pixel_x[9:3]}];
end

// Stage 3: ASCII + 行内偏移 → 字符位图 → 像素
always @(posedge clk_hdmi_pixel) begin
    char_col <= font_rom[{char_ascii_d3, pixel_y_d3[3:0]}];
end
```

**效果预期**:
- 逻辑深度从24级降低到约8级/每阶段
- WNS从-3.337ns改善到+1ns以上
- 增加2个时钟周期延迟（对显示效果无影响）

**实施复杂度**: 中等（约300行修改，3小时工作量）

---

#### 方案F: 字符显示异步BRAM读取 ⭐⭐⭐

**原理**: 利用BRAM的双端口特性，异步预读取字符数据

**实现**:
```verilog
// 使用BRAM的异步读端口（如果支持）
BRAM_SDP_MACRO #(
    .BRAM_SIZE("18Kb"),
    .DEVICE("7SERIES"),
    .WRITE_MODE("READ_FIRST")
) char_rom_inst (
    .DO(char_ascii_async),      // 异步读数据（1周期延迟）
    .RDADDR(char_addr_async),   // 异步读地址
    .RDCLK(clk_hdmi_pixel),
    .RDEN(1'b1),
    // ...
);
```

**效果预期**:
- 减少2-4级逻辑
- 改善1-2ns

**实施复杂度**: 中等（需要理解BRAM时序）

---

#### 方案G: 降低HDMI分辨率 ⭐

**原理**: 从1280x720@60Hz (74.25MHz) 降低到1024x768@60Hz (65MHz)

**效果**:
- 时钟周期从13.468ns增加到15.384ns（+1.916ns裕量）
- WNS从-3.337ns改善到约-1.4ns

**缺点**: 显示分辨率降低，用户体验下降

**实施复杂度**: 低（修改PLL配置）

---

### 4.3 推荐优化组合

#### 🚀 **快速方案（1天工作量）**: 方案B + 方案D + 方案E

1. **上午**: 实现方案B（BCD慢速状态机）→ 预期100MHz WNS改善到+3ns
2. **中午**: 实现方案D（简化调参逻辑）→ 额外改善1-2ns
3. **下午**: 实现方案E（字符坐标流水线）→ 预期HDMI WNS改善到+1ns

**预期最终结果**:
- 100MHz域: WNS = +3~5ns ✅
- HDMI域: WNS = +1~2ns ✅
- 所有时序满足要求

---

#### 🎯 **最佳方案（2天工作量）**: 方案A + 方案E

1. **第1天**: 实现方案A（BCD流水线转换器）
   - 设计4级流水线结构
   - 实现Double Dabble分段迭代
   - 集成到auto_test模块
   - 预期100MHz WNS改善到+2ns

2. **第2天**: 实现方案E（字符坐标流水线）
   - 分析当前字符显示逻辑
   - 设计3级流水线结构
   - 修改hdmi_display_ctrl模块
   - 预期HDMI WNS改善到+2ns

**预期最终结果**:
- 100MHz域: WNS = +2~4ns ✅
- HDMI域: WNS = +2~3ns ✅
- 代码质量高，可维护性好

---

## 五、资源使用情况

### 5.1 当前资源使用（待补充）

需要从综合报告中提取：
```tcl
report_utilization -file utilization.rpt
```

**关注指标**:
- LUT使用率（目标<80%）
- FF使用率（目标<60%）
- BRAM使用率（目标<70%）
- DSP使用率
- 布线拥塞度

### 5.2 优化后资源预测

| 方案 | LUT增加 | FF增加 | BRAM增加 | 备注 |
|------|---------|--------|----------|------|
| 方案A | +200 | +128 | 0 | 4级流水线×32bit |
| 方案B | +50 | +64 | 0 | 状态机寄存器 |
| 方案E | +100 | +96 | 0 | 3级流水线×32bit |

---

## 六、下一步行动计划

### 6.1 立即执行（今天）

1. ✅ **已完成**: 分析时序报告，识别关键路径
2. ⏳ **进行中**: 制定优化方案，评估风险
3. 🔲 **待执行**: 
   - 选择优化方案（推荐：快速方案 或 最佳方案）
   - 备份当前代码（Git tag）
   - 开始实现选定方案

### 6.2 本周计划

- **周一下午**: 完成方案B或方案A的实现
- **周二上午**: 完成方案D的实现
- **周二下午**: 完成方案E的实现
- **周三**: 综合测试，时序验证
- **周四**: 硬件测试，功能验证
- **周五**: 总结文档，代码提交

### 6.3 验证计划

#### 时序验证
```tcl
# 重新综合
synthesize
place_route

# 生成详细时序报告
report_timing -nworst 100 -path_type full -file timing_optimized.rpt

# 检查时序
report_timing_summary
```

**成功标准**:
- ✅ 100MHz域 WNS ≥ 0 ns
- ✅ HDMI域 WNS ≥ 0 ns
- ✅ 所有时钟域满足时序要求
- ✅ Hold时序无违例

#### 功能验证
1. 硬件测试：
   - 进入自动测试模式
   - 调整频率参数（测试BCD转换）
   - 切换步进模式（1k/10k/100k/1M）
   - 验证HDMI显示正确性
   - 验证阈值判断逻辑

2. 波形测试：
   - 示波器观察HDMI时序
   - 逻辑分析仪抓取BCD更新过程

---

## 七、风险评估

### 7.1 技术风险

| 风险项 | 概率 | 影响 | 缓解措施 |
|--------|------|------|----------|
| 流水线化后功能错误 | 中 | 高 | 充分仿真测试，保留原版代码 |
| 优化后时序仍不满足 | 低 | 中 | 准备方案C（EDA工具优化）作为备选 |
| 资源使用超限 | 低 | 中 | 监控资源报告，方案B资源开销最小 |
| CDC问题引入 | 极低 | 高 | 所有优化都在单时钟域内，无CDC风险 |

### 7.2 进度风险

- 方案A复杂度较高，可能需要3天
- 建议先实现方案B+D+E（快速方案），确保本周完成

---

## 八、总结

### 8.1 BCD优化成果

✅ **HDMI域时序改善显著**:
- 从WNS=-21.199ns改善到-3.337ns
- 改善幅度: **17.86ns (84.3%)**
- 违例端点: 从200/2525减少到22/1947
- TNS: 从-1692.088ns改善到-34.907ns

✅ **除法运算完全消除**:
- 删除58个除法/取模运算
- HDMI域组合逻辑从约50级降低到24级

### 8.2 新问题

❌ **100MHz域时序恶化**:
- WNS: -15.119ns（原-3.437ns，恶化11.68ns）
- 根本原因: Double Dabble算法的组合逻辑过深（37级）
- 影响: 504个端点违例，需要紧急修复

### 8.3 优化方向

🎯 **核心策略**: 流水线化 + 时序优化
- 方案B（慢速状态机）: 最简单，风险最低，推荐作为第一步
- 方案A（流水线转换）: 性能最优，适合长期维护
- 方案E（字符流水线）: 解决HDMI剩余3.3ns违例

🚀 **预期结果**: 
- 实施快速方案后，所有时钟域满足时序
- 代码质量提升，可维护性增强
- 为后续功能扩展留出时序裕量

---

## 附录A：关键代码位置

### A.1 100MHz域违例相关文件

- `source/source/auto_test.v`
  - Line 111-179: BCD转换函数（需要优化）
  - Line 222-410: 参数调整逻辑（高扇出问题）

### A.2 HDMI域违例相关文件

- `source/source/hdmi_display_ctrl.v`
  - Line 1200-1500: 字符显示逻辑（需要流水线化）
  - Line 2480-2650: 字符位图提取（关键路径）

### A.3 时序约束文件

- `constraint_check/signal_analyzer_top.sdc`
  - 需要检查时钟周期定义
  - 可能需要添加false path或multicycle path约束

---

**报告结束**  
**建议**: 立即实施方案B（BCD慢速状态机）+ 方案D（降低扇出）+ 方案E（字符流水线），预计1天完成，时序满足率100%。
