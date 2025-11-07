# 锁相放大HDMI显示功能补丁

## 修改说明
为 `hdmi_display_ctrl.v` 添加锁相放大（Lock-in Amplifier）显示功能，在屏幕左上角显示检测结果。

## 1. 添加输入端口（Line ~85，在 thd_max_d3 后面）

```verilog
    input  wire [3:0]   thd_max_d0, thd_max_d1, thd_max_d2, thd_max_d3,
    
    // ✨ 锁相放大显示输入
    input  wire         weak_sig_enable,        // 微弱信号模式使能
    input  wire [31:0]  lia_ref_freq,           // 参考频率 (Hz)
    input  wire [1:0]   lia_ref_mode,           // 参考模式 (0=DDS, 1=CH2, 2=外部)
    input  wire signed [23:0] ch1_lia_magnitude,// CH1幅度 (24-bit)
    input  wire [15:0]  ch1_lia_phase,          // CH1相位 (0-65535 -> 0-360°)
    input  wire         ch1_lia_locked,         // CH1锁定状态
    input  wire [15:0]  lia_snr_estimate,       // SNR估计 (dB, 8.8定点)
    
    // HDMI输出
    output wire [23:0]  rgb_out,
    output wire         de_out,
    output wire         hs_out,
    output wire         vs_out
);
```

## 2. 添加参数定义（Line ~155，在 AUTO_CHAR_WIDTH 后面）

```verilog
localparam AUTO_CHAR_WIDTH   = 16;      // 字符宽度

//=============================================================================
// 锁相放大显示区域参数 (屏幕左上角)
//=============================================================================
localparam LIA_X_START = 20;            // 锁相放大区域X起始
localparam LIA_Y_START = 60;            // 锁相放大区域Y起始
localparam LIA_WIDTH   = 360;           // 锁相放大区域宽度
localparam LIA_HEIGHT  = 200;           // 锁相放大区域高度
localparam LIA_LINE_HEIGHT = 28;        // 行高
localparam LIA_CHAR_WIDTH  = 16;        // 字符宽度

// 自动测试模式状态
```

## 3. 添加信号定义（Line ~300，在 auto_test_char_valid 后面）

```verilog
reg         auto_test_char_valid;   // 自动测试字符有效

// 锁相放大显示相关信号
reg         in_lia_area;            // 在锁相放大显示区域内
reg         in_lia_area_d1, in_lia_area_d2, in_lia_area_d3;  // 延迟链
reg [4:0]   lia_char_row;           // 锁相放大字符行号
reg [11:0]  lia_char_col;           // 锁相放大字符列号

// 锁相放大显示数据（预处理）
reg [31:0]  lia_freq_display;       // 参考频率显示值
reg [3:0]   lia_freq_d0, lia_freq_d1, lia_freq_d2, lia_freq_d3, lia_freq_d4, lia_freq_d5;
reg [3:0]   lia_mag_d0, lia_mag_d1, lia_mag_d2, lia_mag_d3;  // 幅度（mV）
reg [3:0]   lia_phase_d0, lia_phase_d1, lia_phase_d2;  // 相位（度）
reg [3:0]   lia_snr_d0, lia_snr_d1, lia_snr_d2;  // SNR（dB）
reg         lia_phase_sign;         // 相位符号（0=正，1=负）

//=============================================================================
// ASCII字符转换函数（复用）
//=============================================================================
```

## 4. 添加复位逻辑（Line ~765，在 in_auto_test_area_d3 复位后面）

```verilog
        in_auto_test_area_d3 <= 1'b0;
        
        // 锁相放大区域标志复位
        in_lia_area_d1 <= 1'b0;
        in_lia_area_d2 <= 1'b0;
        in_lia_area_d3 <= 1'b0;
```

## 5. 添加延迟链更新（Line ~793，在 in_auto_test_area_d3 更新后面）

```verilog
        in_auto_test_area_d3 <= in_auto_test_area_d2;
        
        // 锁相放大区域标志延迟
        in_lia_area_d1 <= in_lia_area;
        in_lia_area_d2 <= in_lia_area_d1;
        in_lia_area_d3 <= in_lia_area_d2;
```

## 6. 添加数据预处理（Line ~850，在参数预计算区域）

```verilog
// 在 always @(posedge clk_pixel or negedge rst_n) begin 的参数预计算部分添加：

    // ========== 锁相放大数据预处理（每帧更新一次）==========
    if (v_cnt == 0 && h_cnt == 0) begin
        // 频率显示（简化处理，直接除法）
        lia_freq_display <= lia_ref_freq;
        lia_freq_d5 <= (lia_ref_freq / 100000) % 10;
        lia_freq_d4 <= (lia_ref_freq / 10000) % 10;
        lia_freq_d3 <= (lia_ref_freq / 1000) % 10;
        lia_freq_d2 <= (lia_ref_freq / 100) % 10;
        lia_freq_d1 <= (lia_ref_freq / 10) % 10;
        lia_freq_d0 <= lia_ref_freq % 10;
        
        // 幅度显示（转换为mV，取整数部分）
        // ch1_lia_magnitude是24-bit有符号数，需要缩放
        // 假设满幅度=3300mV，则：mV = (magnitude * 3300) / (2^23)
        // 简化：mV ≈ magnitude >> 14
        lia_mag_d3 <= (ch1_lia_magnitude[23] ? 0 : (ch1_lia_magnitude >> 14) / 1000) % 10;
        lia_mag_d2 <= (ch1_lia_magnitude[23] ? 0 : (ch1_lia_magnitude >> 14) / 100) % 10;
        lia_mag_d1 <= (ch1_lia_magnitude[23] ? 0 : (ch1_lia_magnitude >> 14) / 10) % 10;
        lia_mag_d0 <= (ch1_lia_magnitude[23] ? 0 : (ch1_lia_magnitude >> 14)) % 10;
        
        // 相位显示（0-65535 映射到 0-360度）
        // Phase_deg = (ch1_lia_phase * 360) / 65536 ≈ ch1_lia_phase * 5.5 / 1000
        // 简化：Phase_deg ≈ (ch1_lia_phase * 360) >> 16
        lia_phase_d2 <= ((ch1_lia_phase * 360) >> 16) / 100;
        lia_phase_d1 <= (((ch1_lia_phase * 360) >> 16) / 10) % 10;
        lia_phase_d0 <= ((ch1_lia_phase * 360) >> 16) % 10;
        lia_phase_sign <= 1'b0;  // 相位始终正数（0-360°）
        
        // SNR显示（8.8定点，整数部分）
        lia_snr_d2 <= (lia_snr_estimate >> 8) / 100;
        lia_snr_d1 <= ((lia_snr_estimate >> 8) / 10) % 10;
        lia_snr_d0 <= (lia_snr_estimate >> 8) % 10;
    end
```

## 7. 添加字符显示逻辑（Line ~1095，在 in_auto_test_area 初始化后面）

```verilog
        in_auto_test_area <= 1'b0;  // 默认不在自动测试区域
        
        // 锁相放大区域初始化
        in_lia_area <= 1'b0;  // 默认不在锁相放大区域
```

## 8. 添加锁相放大显示区域（Line ~2260，在自动测试显示区域之前）

```verilog
    // ========== 锁相放大显示区域（屏幕左上角）==========
    else if (weak_sig_enable && pixel_y_d1 >= LIA_Y_START && 
             pixel_y_d1 < (LIA_Y_START + LIA_HEIGHT) &&
             pixel_x_d1 >= LIA_X_START && 
             pixel_x_d1 < (LIA_X_START + LIA_WIDTH)) begin
        
        // 设置锁相放大区域标志
        in_lia_area <= 1'b1;
        
        // 计算行号和列号
        lia_char_row <= (pixel_y_d1 - LIA_Y_START) % LIA_LINE_HEIGHT;
        lia_char_col <= (pixel_x_d1 - LIA_X_START) % LIA_CHAR_WIDTH;
        char_row <= lia_char_row;
        
        // 标题行："Lock-in Amp"
        if (pixel_y_d1 < (LIA_Y_START + LIA_LINE_HEIGHT)) begin
            if (pixel_x_d1 >= LIA_X_START && pixel_x_d1 < LIA_X_START + 12*LIA_CHAR_WIDTH) begin
                case ((pixel_x_d1 - LIA_X_START) / LIA_CHAR_WIDTH)
                    0: char_code <= 8'd76;  // 'L'
                    1: char_code <= 8'd111; // 'o'
                    2: char_code <= 8'd99;  // 'c'
                    3: char_code <= 8'd107; // 'k'
                    4: char_code <= 8'd45;  // '-'
                    5: char_code <= 8'd105; // 'i'
                    6: char_code <= 8'd110; // 'n'
                    7: char_code <= 8'd32;  // ' '
                    8: char_code <= 8'd65;  // 'A'
                    9: char_code <= 8'd109; // 'm'
                    10: char_code <= 8'd112; // 'p'
                    default: char_code <= 8'd32;
                endcase
                char_col <= lia_char_col;
                in_char_area <= 1'b1;
            end
        end
        
        // 第2行："Ref: 001000 Hz"
        else if (pixel_y_d1 < (LIA_Y_START + 2*LIA_LINE_HEIGHT)) begin
            if (pixel_x_d1 >= LIA_X_START && pixel_x_d1 < LIA_X_START + 18*LIA_CHAR_WIDTH) begin
                case ((pixel_x_d1 - LIA_X_START) / LIA_CHAR_WIDTH)
                    0: char_code <= 8'd82;  // 'R'
                    1: char_code <= 8'd101; // 'e'
                    2: char_code <= 8'd102; // 'f'
                    3: char_code <= 8'd58;  // ':'
                    4: char_code <= 8'd32;  // ' '
                    5: char_code <= (lia_freq_d5 < 10) ? (8'd48 + lia_freq_d5) : 8'd32;
                    6: char_code <= (lia_freq_d4 < 10) ? (8'd48 + lia_freq_d4) : 8'd32;
                    7: char_code <= (lia_freq_d3 < 10) ? (8'd48 + lia_freq_d3) : 8'd32;
                    8: char_code <= (lia_freq_d2 < 10) ? (8'd48 + lia_freq_d2) : 8'd32;
                    9: char_code <= (lia_freq_d1 < 10) ? (8'd48 + lia_freq_d1) : 8'd32;
                    10: char_code <= (lia_freq_d0 < 10) ? (8'd48 + lia_freq_d0) : 8'd32;
                    11: char_code <= 8'd32;  // ' '
                    12: char_code <= 8'd72;  // 'H'
                    13: char_code <= 8'd122; // 'z'
                    default: char_code <= 8'd32;
                endcase
                char_col <= lia_char_col;
                in_char_area <= 1'b1;
            end
        end
        
        // 第3行："Mode: DDS/CH2/Ext"
        else if (pixel_y_d1 < (LIA_Y_START + 3*LIA_LINE_HEIGHT)) begin
            if (pixel_x_d1 >= LIA_X_START && pixel_x_d1 < LIA_X_START + 15*LIA_CHAR_WIDTH) begin
                case ((pixel_x_d1 - LIA_X_START) / LIA_CHAR_WIDTH)
                    0: char_code <= 8'd77;  // 'M'
                    1: char_code <= 8'd111; // 'o'
                    2: char_code <= 8'd100; // 'd'
                    3: char_code <= 8'd101; // 'e'
                    4: char_code <= 8'd58;  // ':'
                    5: char_code <= 8'd32;  // ' '
                    6: char_code <= (lia_ref_mode == 2'd0) ? 8'd68 : 8'd32;  // 'D'
                    7: char_code <= (lia_ref_mode == 2'd0) ? 8'd68 : 8'd32;  // 'D'
                    8: char_code <= (lia_ref_mode == 2'd0) ? 8'd83 : 8'd32;  // 'S'
                    9: char_code <= (lia_ref_mode == 2'd1) ? 8'd67 : 8'd32;  // 'C'
                    10: char_code <= (lia_ref_mode == 2'd1) ? 8'd72 : 8'd32;  // 'H'
                    11: char_code <= (lia_ref_mode == 2'd1) ? 8'd50 : 8'd32;  // '2'
                    12: char_code <= (lia_ref_mode == 2'd2) ? 8'd69 : 8'd32;  // 'E'
                    13: char_code <= (lia_ref_mode == 2'd2) ? 8'd120 : 8'd32; // 'x'
                    14: char_code <= (lia_ref_mode == 2'd2) ? 8'd116 : 8'd32; // 't'
                    default: char_code <= 8'd32;
                endcase
                char_col <= lia_char_col;
                in_char_area <= 1'b1;
            end
        end
        
        // 第4行："Mag: 0000 mV"
        else if (pixel_y_d1 < (LIA_Y_START + 4*LIA_LINE_HEIGHT)) begin
            if (pixel_x_d1 >= LIA_X_START && pixel_x_d1 < LIA_X_START + 14*LIA_CHAR_WIDTH) begin
                case ((pixel_x_d1 - LIA_X_START) / LIA_CHAR_WIDTH)
                    0: char_code <= 8'd77;  // 'M'
                    1: char_code <= 8'd97;  // 'a'
                    2: char_code <= 8'd103; // 'g'
                    3: char_code <= 8'd58;  // ':'
                    4: char_code <= 8'd32;  // ' '
                    5: char_code <= (lia_mag_d3 < 10) ? (8'd48 + lia_mag_d3) : 8'd32;
                    6: char_code <= (lia_mag_d2 < 10) ? (8'd48 + lia_mag_d2) : 8'd32;
                    7: char_code <= (lia_mag_d1 < 10) ? (8'd48 + lia_mag_d1) : 8'd32;
                    8: char_code <= (lia_mag_d0 < 10) ? (8'd48 + lia_mag_d0) : 8'd32;
                    9: char_code <= 8'd32;  // ' '
                    10: char_code <= 8'd109; // 'm'
                    11: char_code <= 8'd86;  // 'V'
                    default: char_code <= 8'd32;
                endcase
                char_col <= lia_char_col;
                in_char_area <= 1'b1;
            end
        end
        
        // 第5行："Phase: 000 deg"
        else if (pixel_y_d1 < (LIA_Y_START + 5*LIA_LINE_HEIGHT)) begin
            if (pixel_x_d1 >= LIA_X_START && pixel_x_d1 < LIA_X_START + 16*LIA_CHAR_WIDTH) begin
                case ((pixel_x_d1 - LIA_X_START) / LIA_CHAR_WIDTH)
                    0: char_code <= 8'd80;  // 'P'
                    1: char_code <= 8'd104; // 'h'
                    2: char_code <= 8'd97;  // 'a'
                    3: char_code <= 8'd115; // 's'
                    4: char_code <= 8'd101; // 'e'
                    5: char_code <= 8'd58;  // ':'
                    6: char_code <= 8'd32;  // ' '
                    7: char_code <= (lia_phase_d2 < 10) ? (8'd48 + lia_phase_d2) : 8'd32;
                    8: char_code <= (lia_phase_d1 < 10) ? (8'd48 + lia_phase_d1) : 8'd32;
                    9: char_code <= (lia_phase_d0 < 10) ? (8'd48 + lia_phase_d0) : 8'd32;
                    10: char_code <= 8'd32;  // ' '
                    11: char_code <= 8'd100; // 'd'
                    12: char_code <= 8'd101; // 'e'
                    13: char_code <= 8'd103; // 'g'
                    default: char_code <= 8'd32;
                endcase
                char_col <= lia_char_col;
                in_char_area <= 1'b1;
            end
        end
        
        // 第6行："SNR: 00 dB"
        else if (pixel_y_d1 < (LIA_Y_START + 6*LIA_LINE_HEIGHT)) begin
            if (pixel_x_d1 >= LIA_X_START && pixel_x_d1 < LIA_X_START + 12*LIA_CHAR_WIDTH) begin
                case ((pixel_x_d1 - LIA_X_START) / LIA_CHAR_WIDTH)
                    0: char_code <= 8'd83;  // 'S'
                    1: char_code <= 8'd78;  // 'N'
                    2: char_code <= 8'd82;  // 'R'
                    3: char_code <= 8'd58;  // ':'
                    4: char_code <= 8'd32;  // ' '
                    5: char_code <= (lia_snr_d1 < 10) ? (8'd48 + lia_snr_d1) : 8'd32;
                    6: char_code <= (lia_snr_d0 < 10) ? (8'd48 + lia_snr_d0) : 8'd32;
                    7: char_code <= 8'd32;  // ' '
                    8: char_code <= 8'd100; // 'd'
                    9: char_code <= 8'd66;  // 'B'
                    default: char_code <= 8'd32;
                endcase
                char_col <= lia_char_col;
                in_char_area <= 1'b1;
            end
        end
        
        // 第7行："Status: LOCKED/UNLOCK"
        else if (pixel_y_d1 < (LIA_Y_START + 7*LIA_LINE_HEIGHT)) begin
            if (pixel_x_d1 >= LIA_X_START && pixel_x_d1 < LIA_X_START + 18*LIA_CHAR_WIDTH) begin
                case ((pixel_x_d1 - LIA_X_START) / LIA_CHAR_WIDTH)
                    0: char_code <= 8'd83;  // 'S'
                    1: char_code <= 8'd116; // 't'
                    2: char_code <= 8'd97;  // 'a'
                    3: char_code <= 8'd116; // 't'
                    4: char_code <= 8'd117; // 'u'
                    5: char_code <= 8'd115; // 's'
                    6: char_code <= 8'd58;  // ':'
                    7: char_code <= 8'd32;  // ' '
                    8: char_code <= ch1_lia_locked ? 8'd76 : 8'd85;  // 'L' or 'U'
                    9: char_code <= ch1_lia_locked ? 8'd79 : 8'd78;  // 'O' or 'N'
                    10: char_code <= ch1_lia_locked ? 8'd67 : 8'd76; // 'C' or 'L'
                    11: char_code <= ch1_lia_locked ? 8'd75 : 8'd79; // 'K' or 'O'
                    12: char_code <= ch1_lia_locked ? 8'd69 : 8'd67; // 'E' or 'C'
                    13: char_code <= ch1_lia_locked ? 8'd68 : 8'd75; // 'D' or 'K'
                    default: char_code <= 8'd32;
                endcase
                char_col <= lia_char_col;
                in_char_area <= 1'b1;
            end
        end
        
        else begin
            in_char_area <= 1'b0;
        end
    end
    
    // ========== 自动测试显示区域（屏幕右下角）==========
    else if (auto_test_enable && pixel_y_d1 >= AUTO_TEST_Y_START && ...
```

## 9. 添加颜色合成（Line ~2878，在自动测试颜色合成之后）

```verilog
        // 自动测试区域颜色（深蓝背景+白字）
        if (in_auto_test_area_d3) begin
            ... // 现有代码
        end
        
        // 锁相放大区域颜色（深绿背景+白字）
        else if (in_lia_area_d3) begin
            if (char_pixel_row_d2[char_col_d2]) begin
                // 字符像素：白色
                rgb_out_reg <= 24'hFFFFFF;
            end else begin
                // 背景：深绿色
                rgb_out_reg <= 24'h003300;
            end
        end
        
        // 参数显示区域（深灰背景）
        else if (pixel_y_d4 >= PARAM_Y_START && ...
```

## 10. 时序注意事项

1. **延迟链匹配**：in_lia_area_d3 必须与 pixel_y_d4 对齐
2. **预计算优化**：所有除法/取模在帧开始时完成，避免实时计算
3. **fanout控制**：weak_sig_enable 只在字符生成阶段判断一次
4. **流水线深度**：保持与现有auto_test相同的4级流水线

## 11. 顶层模块连接（signal_analyzer_top.v）

```verilog
hdmi_display_ctrl u_hdmi_display (
    // ... 现有信号 ...
    
    // 锁相放大显示
    .weak_sig_enable    (weak_sig_enable),
    .lia_ref_freq       (weak_sig_ref_freq),
    .lia_ref_mode       (weak_sig_ref_mode),
    .ch1_lia_magnitude  (ch1_lia_magnitude),
    .ch1_lia_phase      (ch1_lia_phase),
    .ch1_lia_locked     (ch1_lia_locked),
    .lia_snr_estimate   (lia_snr),
    
    // ... HDMI输出 ...
);
```

## 测试计划

1. **显示位置测试**：确认左上角显示不遮挡波形
2. **数值准确性**：验证频率/幅度/相位/SNR显示正确
3. **锁定状态**：测试LOCKED/UNLOCK切换显示
4. **模式切换**：验证DDS/CH2/Ext模式显示
5. **时序验证**：确认WNS满足要求（目标：> -5ns）
