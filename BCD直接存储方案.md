# BCD直接存储方案 - 彻底消除除法

## 问题根源
当前实现中，`auto_test.v` 存储频率为 `reg [31:0] freq_min`（Hz值），
然后在 `hdmi_display_ctrl.v` 中需要除法转BCD显示，导致严重时序违例。

## 解决方案
**直接存储BCD格式的数值**，完全避免BCD转换过程。

### 数据结构改造

```verilog
// auto_test.v 中
// 旧方案：
// reg [31:0] freq_min;  // 例如：100000 (Hz)

// 新方案：直接存储6位BCD
reg [3:0] freq_min_d0;  // 个位   (0-9)
reg [3:0] freq_min_d1;  // 十位   (0-9)
reg [3:0] freq_min_d2;  // 百位   (0-9)
reg [3:0] freq_min_d3;  // 千位   (0-9)
reg [3:0] freq_min_d4;  // 万位   (0-9)
reg [3:0] freq_min_d5;  // 十万位 (0-9)

// 对于幅度和占空比类似
reg [3:0] amp_min_d0, amp_min_d1, amp_min_d2, amp_min_d3;
reg [3:0] duty_min_d0, duty_min_d1, duty_min_d2, duty_min_d3;
```

### 调整逻辑改造

#### 1. 频率调整（带BCD进位）

```verilog
// 按键：频率下限增加
if (btn_limit_dn_up) begin
    case (step_mode)
        2'd0: begin  // 细调：+1Hz
            if (freq_min_d0 == 4'd9) begin
                freq_min_d0 <= 4'd0;
                // 进位到十位
                if (freq_min_d1 == 4'd9) begin
                    freq_min_d1 <= 4'd0;
                    // 进位到百位...
                    if (freq_min_d2 == 4'd9) begin
                        freq_min_d2 <= 4'd0;
                        freq_min_d3 <= freq_min_d3 + 1'b1;
                    end else begin
                        freq_min_d2 <= freq_min_d2 + 1'b1;
                    end
                end else begin
                    freq_min_d1 <= freq_min_d1 + 1'b1;
                end
            end else begin
                freq_min_d0 <= freq_min_d0 + 1'b1;
            end
        end
        
        2'd1: begin  // 中调：+100Hz
            if (freq_min_d2 == 4'd9) begin
                freq_min_d2 <= 4'd0;
                if (freq_min_d3 == 4'd9) begin
                    freq_min_d3 <= 4'd0;
                    freq_min_d4 <= freq_min_d4 + 1'b1;
                end else begin
                    freq_min_d3 <= freq_min_d3 + 1'b1;
                end
            end else begin
                freq_min_d2 <= freq_min_d2 + 1'b1;
            end
        end
        
        2'd2: begin  // 粗调：+100kHz
            if (freq_min_d5 < 4'd5)  // 不超过500kHz
                freq_min_d5 <= freq_min_d5 + 1'b1;
        end
    endcase
end
```

#### 2. 上下限比较

需要函数来比较BCD值大小：

```verilog
// BCD比较函数
function automatic bcd_greater;
    input [23:0] bcd_a;  // {d5,d4,d3,d2,d1,d0}
    input [23:0] bcd_b;
    begin
        // 从高位到低位比较
        if (bcd_a[23:20] != bcd_b[23:20])
            bcd_greater = (bcd_a[23:20] > bcd_b[23:20]);
        else if (bcd_a[19:16] != bcd_b[19:16])
            bcd_greater = (bcd_a[19:16] > bcd_b[19:16]);
        else if (bcd_a[15:12] != bcd_b[15:12])
            bcd_greater = (bcd_a[15:12] > bcd_b[15:12]);
        else if (bcd_a[11:8] != bcd_b[11:8])
            bcd_greater = (bcd_a[11:8] > bcd_b[11:8]);
        else if (bcd_a[7:4] != bcd_b[7:4])
            bcd_greater = (bcd_a[7:4] > bcd_b[7:4]);
        else
            bcd_greater = (bcd_a[3:0] > bcd_b[3:0]);
    end
endfunction

// 使用
wire [23:0] freq_min_bcd = {freq_min_d5, freq_min_d4, freq_min_d3, freq_min_d2, freq_min_d1, freq_min_d0};
wire [23:0] freq_max_bcd = {freq_max_d5, freq_max_d4, freq_max_d3, freq_max_d2, freq_max_d1, freq_max_d0};

if (bcd_greater(freq_min_bcd, freq_max_bcd)) begin
    // 错误：下限大于上限
end
```

#### 3. 实际测量值比较

由于测量模块输出的是Hz值（32位二进制），需要转换后比较。
但这个转换可以在100MHz域慢慢做，或者改造测量模块也输出BCD。

**更好的方案**：保留Hz值用于实际测量比较，BCD值仅用于显示。

```verilog
// 维护两套数据
reg [31:0] freq_min_binary;  // 用于实际测试比较
reg [23:0] freq_min_bcd;     // 用于HDMI显示

// 调整时同步更新两者
always @(posedge clk) begin
    if (btn_adjust) begin
        // 更新BCD（上述逻辑）
        freq_min_d0 <= ...;
        
        // 同步更新binary
        freq_min_binary <= freq_min_d5 * 100000 +
                          freq_min_d4 * 10000 +
                          freq_min_d3 * 1000 +
                          freq_min_d2 * 100 +
                          freq_min_d1 * 10 +
                          freq_min_d0;
    end
end
```

## 优缺点分析

### 优点
1. ✅ **完全消除除法** - HDMI域0延迟显示
2. ✅ **逻辑简单** - 仅加法和进位判断
3. ✅ **时序友好** - 组合逻辑极短

### 缺点
1. ❌ **代码量大** - 需要处理每一位的进位
2. ❌ **双数据结构** - binary用于测试，BCD用于显示
3. ⚠️ **BCD→Binary转换** - 仍需乘法，但在100MHz域可接受

## 替代方案：混合LUT

如果觉得进位逻辑太复杂，可以用小型LUT：

```verilog
// BCD加法查找表（仅100条目）
reg [3:0] bcd_add1_lut [0:9];  // 单位加1的结果和进位
initial begin
    bcd_add1_lut[0] = {1'b0, 4'd1};  // 0+1=1, 无进位
    bcd_add1_lut[1] = {1'b0, 4'd2};
    // ...
    bcd_add1_lut[9] = {1'b1, 4'd0};  // 9+1=0, 有进位
end
```

## 推荐实现路径

1. **Phase 1**: 仅修改显示部分
   - `auto_test.v` 增加 `freq_min_bcd` 输出
   - 调整时同步更新BCD和Binary
   - `hdmi_display_ctrl.v` 直接使用BCD，删除除法

2. **Phase 2**: 优化BCD更新逻辑
   - 实现BCD加减进位函数
   - 或使用小型LUT加速

3. **Phase 3**: 测量模块BCD化（可选）
   - 修改 `signal_parameter_measure.v` 输出BCD
   - 完全消除Binary↔BCD转换

## 结论

**直接存储BCD是最彻底的解决方案**，虽然需要一些额外逻辑处理进位，
但完全避免了除法运算，是解决HDMI时序违例的根本方法。
