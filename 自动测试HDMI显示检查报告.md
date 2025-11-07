# 自动测试HDMI显示数字字符检查报告

**检查日期**：2025年11月7日  
**检查对象**：`hdmi_display_ctrl.v` - 自动测试区域数字显示逻辑  
**检查范围**：BCD输入端口 → 数字显示逻辑 → 字符编码转换

---

## 📋 检查概述

自动测试HDMI显示部分**存在多处潜在问题**，主要集中在：
1. **数字显示格式混乱**（频率、幅度、占空比、THD格式不统一）
2. **前导零抑制逻辑不完善**（有些参数显示"000123"，有些显示" 123"）
3. **BCD输入检查缺失**（未验证BCD数值是否合法 <10）
4. **单位显示缺失**（频率无Hz/kHz/MHz，幅度无mV/V）

---

## 🔍 详细检查结果

### 1️⃣ **BCD输入端口定义**（Line 64-72）

✅ **状态：正常**

```verilog
// 频率：6位BCD（000000-999999 Hz）
input  wire [3:0]   freq_min_d0, freq_min_d1, freq_min_d2,
input  wire [3:0]   freq_min_d3, freq_min_d4, freq_min_d5,
input  wire [3:0]   freq_max_d0, freq_max_d1, freq_max_d2,
input  wire [3:0]   freq_max_d3, freq_max_d4, freq_max_d5,

// 幅度：4位BCD（0000-9999 mV）
input  wire [3:0]   amp_min_d0, amp_min_d1, amp_min_d2, amp_min_d3,
input  wire [3:0]   amp_max_d0, amp_max_d1, amp_max_d2, amp_max_d3,

// 占空比：3位BCD（00.0-99.9%）
input  wire [3:0]   duty_min_d0, duty_min_d1, duty_min_d2,
input  wire [3:0]   duty_max_d0, duty_max_d1, duty_max_d2,

// THD：3位BCD（00.0-99.9%）
input  wire [3:0]   thd_max_d0, thd_max_d1, thd_max_d2,
```

**说明**：
- ✅ 端口定义清晰，支持所有参数的BCD格式输入
- ✅ 数位排列一致（d0=个位，d1=十位，...）
- ✅ 覆盖所有auto_test模块的参数范围

---

### 2️⃣ **频率显示逻辑**（Line 2743-2781）

⚠️ **状态：存在问题**

```verilog
// 当前实现（参数调整界面）：
case ((pixel_x_d1 - AUTO_TEST_X_START) / AUTO_CHAR_WIDTH)
    5: char_code <= (freq_min_d5 < 10) ? digit_to_ascii(freq_min_d5) : 8'd32;  // 高位
    6: char_code <= (freq_min_d4 < 10) ? digit_to_ascii(freq_min_d4) : 8'd32;
    7: char_code <= (freq_min_d3 < 10) ? digit_to_ascii(freq_min_d3) : 8'd32;
    8: char_code <= (freq_min_d2 < 10) ? digit_to_ascii(freq_min_d2) : 8'd32;
    9: char_code <= (freq_min_d1 < 10) ? digit_to_ascii(freq_min_d1) : 8'd32;
    10: char_code <= (freq_min_d0 < 10) ? digit_to_ascii(freq_min_d0) : 8'd32; // 低位
    default: char_code <= 8'd32;
endcase
```

**问题分析**：
| 问题类型 | 严重度 | 具体描述 |
|---------|--------|----------|
| 🔴 前导零未抑制 | 高 | 100kHz显示为"100000"而非" 100000" |
| 🟡 无单位显示 | 中 | 未显示"Hz"/"kHz"/"MHz" |
| 🟡 无千位分隔符 | 低 | 100000难以阅读，建议"100,000"或"100K" |
| 🟢 BCD检查正常 | - | `< 10`检查避免显示非法字符 |

**示例对比**：
```
当前：Min: 095000    ❌ 前导零未抑制，无单位
期望：Min:  95 kHz   ✅ 前导零抑制，带单位
```

---

### 3️⃣ **幅度显示逻辑**（Line 2782-2795）

⚠️ **状态：格式不完整**

```verilog
// 当前实现：
5: char_code <= (amp_min_d3 < 10) ? digit_to_ascii(amp_min_d3) : 8'd32;  // 千位
6: char_code <= (amp_min_d2 < 10) ? digit_to_ascii(amp_min_d2) : 8'd32;  // 百位
7: char_code <= (amp_min_d1 < 10) ? digit_to_ascii(amp_min_d1) : 8'd32;  // 十位
8: char_code <= (amp_min_d0 < 10) ? digit_to_ascii(amp_min_d0) : 8'd32;  // 个位
9: char_code <= 8'd32;  // 空格（无单位！）
```

**问题分析**：
| 问题类型 | 严重度 | 具体描述 |
|---------|--------|----------|
| 🔴 **单位缺失** | 高 | 未显示"mV"或"V" |
| 🟡 小数点缺失 | 中 | 3500应显示为"3.500V"而非"3500" |
| 🟡 前导零未抑制 | 中 | 应显示" 3500"而非"0350" |
| 🟢 BCD检查正常 | - | `< 10`检查正常 |

**示例对比**：
```
当前：Min: 2500      ❌ 无单位，无小数点
期望：Min: 2.50 V    ✅ 带单位，小数格式
```

---

### 4️⃣ **占空比显示逻辑**（Line 2796-2810）

✅ **状态：格式较好**

```verilog
// 当前实现：
5: char_code <= (duty_min_d2 < 10) ? digit_to_ascii(duty_min_d2) : 8'd32;  // 十位
6: char_code <= (duty_min_d1 < 10) ? digit_to_ascii(duty_min_d1) : 8'd32;  // 个位
7: char_code <= 8'd46;  // '.'
8: char_code <= (duty_min_d0 < 10) ? digit_to_ascii(duty_min_d0) : 8'd32;  // 小数位
9: char_code <= 8'd37;  // '%'
```

**优点**：
- ✅ 小数点位置正确（XX.X%格式）
- ✅ '%'单位显示正常
- ✅ BCD检查完整

**小问题**：
- 🟡 前导零未抑制（05.0%应显示为" 5.0%"）

**示例对比**：
```
当前：Min: 05.0%     ⚠️ 前导零未抑制
期望：Min:  5.0%     ✅ 更简洁
```

---

### 5️⃣ **THD显示逻辑**（Line 2858-2872）

✅ **状态：格式正确**

```verilog
// 当前实现（Max参数）：
5: char_code <= (thd_max_d2 < 10) ? digit_to_ascii(thd_max_d2) : 8'd32;  // 十位
6: char_code <= (thd_max_d1 < 10) ? digit_to_ascii(thd_max_d1) : 8'd32;  // 个位
7: char_code <= 8'd46;  // '.'
8: char_code <= (thd_max_d0 < 10) ? digit_to_ascii(thd_max_d0) : 8'd32;  // 小数位
9: char_code <= 8'd37;  // '%'
```

**优点**：
- ✅ 格式与占空比一致（XX.X%）
- ✅ '%'单位显示
- ✅ BCD检查完整

**小问题**：
- 🟡 前导零未抑制（同占空比）

---

### 6️⃣ **BCD检查机制**

✅ **状态：逻辑完整**

所有数字显示均使用以下检查：
```verilog
char_code <= (bcd_digit < 10) ? digit_to_ascii(bcd_digit) : 8'd32;
```

**保护措施**：
- ✅ 防止显示非法BCD值（>9）
- ✅ 非法值显示为空格（ASCII 32）
- ✅ 避免字符ROM越界访问

---

## 🐛 发现的问题汇总

### 🔴 **P0 - 严重问题**（影响功能）

| 问题ID | 描述 | 影响范围 | 修复优先级 |
|--------|------|----------|-----------|
| ❌ FMT-01 | 频率无单位显示 | auto_test调整界面 | P0 |
| ❌ FMT-02 | 幅度无单位显示 | auto_test调整界面 | P0 |

### 🟡 **P1 - 重要问题**（影响体验）

| 问题ID | 描述 | 影响范围 | 修复优先级 |
|--------|------|----------|-----------|
| ⚠️ FMT-03 | 频率前导零未抑制 | 显示混乱（"095000"） | P1 |
| ⚠️ FMT-04 | 幅度前导零未抑制 | 显示混乱（"0350"） | P1 |
| ⚠️ FMT-05 | 占空比前导零未抑制 | 显示混乱（"05.0%"） | P2 |
| ⚠️ FMT-06 | 幅度无小数点 | 不符合惯例（"2.50V"） | P2 |

---

## 💡 修复建议

### **修复方案A：完整格式化（推荐）**

```verilog
// 频率显示：智能单位+前导零抑制
// 示例："  100 kHz", " 1200 kHz", "   10 MHz"
wire [31:0] freq_hz = {freq_min_d5, freq_min_d4, freq_min_d3, 
                        freq_min_d2, freq_min_d1, freq_min_d0};
wire is_mhz = (freq_hz >= 1000000);
wire is_khz = (freq_hz >= 1000);

// 显示逻辑：
if (is_mhz) begin
    // 显示 "XXX MHz" (000-999)
    display_bcd3(freq_hz / 1000000);
    display_unit("MHz");
end else if (is_khz) begin
    // 显示 "XXX kHz" (000-999)
    display_bcd3(freq_hz / 1000);
    display_unit("kHz");
end else begin
    // 显示 "XXX Hz" (000-999)
    display_bcd3(freq_hz);
    display_unit("Hz");
end
```

**优点**：
- ✅ 自动选择合适单位（Hz/kHz/MHz）
- ✅ 数值范围统一（000-999）
- ✅ 易于阅读

**缺点**：
- ❌ 需要除法运算（可能影响时序）
- ❌ 需要额外逻辑资源

---

### **修复方案B：简化格式（快速修复）**

```verilog
// 频率：6位BCD + "Hz"
// 示例："100000 Hz", " 95000 Hz"（前导零抑制）

// 修改显示逻辑（Line 2743）：
5: char_code <= (freq_min_d5 == 0) ? 8'd32 : digit_to_ascii(freq_min_d5);  // 十万位
6: char_code <= (freq_min_d5 == 0 && freq_min_d4 == 0) ? 8'd32 : digit_to_ascii(freq_min_d4);  // 万位
7: char_code <= (freq_min_d5 == 0 && freq_min_d4 == 0 && freq_min_d3 == 0) ? 8'd32 : digit_to_ascii(freq_min_d3);  // 千位
8: char_code <= digit_to_ascii(freq_min_d2);  // 百位（始终显示）
9: char_code <= digit_to_ascii(freq_min_d1);  // 十位
10: char_code <= digit_to_ascii(freq_min_d0); // 个位
11: char_code <= 8'd32;  // 空格
12: char_code <= 8'd72;  // 'H'
13: char_code <= 8'd122; // 'z'

// 幅度：4位BCD + "mV"
// 示例："3500 mV", " 250 mV"

5: char_code <= (amp_min_d3 == 0) ? 8'd32 : digit_to_ascii(amp_min_d3);  // 千位
6: char_code <= (amp_min_d3 == 0 && amp_min_d2 == 0) ? 8'd32 : digit_to_ascii(amp_min_d2);  // 百位
7: char_code <= digit_to_ascii(amp_min_d1);  // 十位（始终显示）
8: char_code <= digit_to_ascii(amp_min_d0);  // 个位
9: char_code <= 8'd32;   // 空格
10: char_code <= 8'd109; // 'm'
11: char_code <= 8'd86;  // 'V'
```

**优点**：
- ✅ 修改量小（仅调整字符编码逻辑）
- ✅ 无时序影响（纯组合逻辑）
- ✅ 快速实施（1小时内完成）

**缺点**：
- ⚠️ 大数值显示冗长（"100000 Hz"而非"100 kHz"）
- ⚠️ 前导零抑制逻辑复杂（需要级联判断）

---

### **修复方案C：预计算单位（最佳平衡）**

让`auto_test.v`模块输出预计算的单位标志：

```verilog
// auto_test.v 新增输出：
output reg freq_unit,      // 0=Hz, 1=kHz
output reg [3:0] freq_d0,  // 显示数值（3位BCD，000-999）
output reg [3:0] freq_d1,
output reg [3:0] freq_d2,

// hdmi_display_ctrl.v 显示：
5: char_code <= (freq_d2 == 0) ? 8'd32 : digit_to_ascii(freq_d2);  // 百位
6: char_code <= (freq_d2 == 0 && freq_d1 == 0) ? 8'd32 : digit_to_ascii(freq_d1);  // 十位
7: char_code <= digit_to_ascii(freq_d0);  // 个位
8: char_code <= 8'd32;  // 空格
9: char_code <= (freq_unit == 0) ? 8'd72 : 8'd107;   // 'H' or 'k'
10: char_code <= (freq_unit == 0) ? 8'd122 : 8'd72;  // 'z' or 'H'
11: char_code <= (freq_unit == 0) ? 8'd32 : 8'd122;  // ' ' or 'z'
```

**优点**：
- ✅ 单位转换在auto_test模块完成（clk_100m时钟域）
- ✅ hdmi_display_ctrl仅负责显示（clk_hdmi_pixel时钟域）
- ✅ 避免跨时钟域复杂计算
- ✅ 显示清晰（" 95 kHz"）

**缺点**：
- ⚠️ 需要修改auto_test模块接口
- ⚠️ 需要重新连接顶层信号

---

## 📊 三种方案对比

| 方案 | 修改量 | 时序影响 | 显示效果 | 实施难度 | 推荐指数 |
|------|--------|----------|----------|----------|----------|
| A：完整格式化 | 大 | ⚠️ 除法运算 | ⭐⭐⭐⭐⭐ | 困难 | ⭐⭐ |
| B：简化格式 | 中 | ✅ 无 | ⭐⭐⭐ | 简单 | ⭐⭐⭐ |
| C：预计算单位 | 大 | ✅ 无 | ⭐⭐⭐⭐⭐ | 中等 | ⭐⭐⭐⭐⭐ |

---

## ✅ 修复检查清单

### **短期修复（快速见效）**
- [ ] 添加频率单位"Hz"（方案B - 2行代码）
- [ ] 添加幅度单位"mV"（方案B - 2行代码）
- [ ] 占空比前导零抑制（方案B - 3行代码）

### **中期优化（体验提升）**
- [ ] 频率前导零抑制（方案B - 10行代码）
- [ ] 幅度前导零抑制（方案B - 5行代码）
- [ ] 幅度小数点显示（可选 - 需要除法）

### **长期重构（最佳方案）**
- [ ] auto_test.v添加单位预计算（方案C）
- [ ] hdmi_display_ctrl.v接收新格式（方案C）
- [ ] 顶层模块信号连接更新（方案C）

---

## 🎯 建议实施策略

**优先级排序**：
1. **P0（立即修复）**：添加频率/幅度单位（方案B，10分钟）
2. **P1（本周内）**：前导零抑制（方案B，30分钟）
3. **P2（可选）**：单位预计算重构（方案C，2小时）

**修复顺序**：
```
Step1: 添加单位（10分钟）
  ├─ 频率 + "Hz"
  └─ 幅度 + "mV"

Step2: 前导零抑制（30分钟）
  ├─ 频率（6位级联判断）
  ├─ 幅度（4位级联判断）
  └─ 占空比（2位简单判断）

Step3: 编译测试（10分钟）
  └─ 语法检查 + 时序验证

Step4: 硬件验证（20分钟）
  ├─ 进入auto_test模式
  ├─ 调整频率参数（观察"Hz"显示）
  └─ 调整幅度参数（观察"mV"显示）
```

---

## 📌 总结

| 检查项 | 状态 | 评分 |
|--------|------|------|
| BCD输入端口 | ✅ 正常 | 5/5 |
| 数字显示逻辑 | ⚠️ 功能正常，格式待优化 | 3/5 |
| BCD检查机制 | ✅ 完善 | 5/5 |
| 单位显示 | ❌ 缺失 | 1/5 |
| 前导零抑制 | ⚠️ 部分实现 | 2/5 |
| **综合评分** | **🟡 基本可用，需优化** | **3.2/5** |

**核心问题**：
- 🔴 **频率和幅度无单位显示**（用户无法理解数值含义）
- 🟡 **前导零未抑制**（显示混乱）

**推荐方案**：
- **短期**：方案B（快速添加单位+前导零抑制）
- **长期**：方案C（单位预计算+清晰显示）

---

**报告生成时间**：2025年11月7日  
**报告作者**：GitHub Copilot  
**下一步行动**：根据优先级实施修复方案
