# 锁相放大HDMI显示 - 完整实施指南

## ✅ 已完成的修改

1. ✅ 添加了输入端口（weak_sig_enable, lia_ref_freq等）
2. ✅ 添加了显示区域参数（LIA_X_START, LIA_Y_START等）  
3. ✅ 添加了信号定义（in_lia_area, lia_char_row等）

## 🔧 待手动完成的修改

### 修改1：添加复位逻辑（约Line 800）

**位置**：在 `in_auto_test_area_d3 <= 1'b0;` 后面添加

```verilog
        in_auto_test_area_d3 <= 1'b0;
        
        // 锁相放大区域标志延迟链
        in_lia_area_d1 <= 1'b0;
        in_lia_area_d2 <= 1'b0;
        in_lia_area_d3 <= 1'b0;
```

### 修改2：添加延迟链更新（约Line 825）

**位置**：在 `in_auto_test_area_d3 <= in_auto_test_area_d2;` 后面添加

```verilog
        in_auto_test_area_d3 <= in_auto_test_area_d2;
        
        // 锁相放大区域标志延迟
        in_lia_area_d1 <= in_lia_area;
        in_lia_area_d2 <= in_lia_area_d1;
        in_lia_area_d3 <= in_lia_area_d2;
```

### 修改3：添加数据预处理（约Line 900）

**位置**：在参数预计算的 `if (v_cnt == 0 && h_cnt == 0) begin` 块内添加

```verilog
    // 在现有的参数预计算块内添加：
    
    // ========== 锁相放大数据预处理（每帧更新一次）==========
    // 频率显示（Hz）
    lia_freq_display <= lia_ref_freq;
    lia_freq_d5 <= (lia_ref_freq / 100000) % 10;
    lia_freq_d4 <= (lia_ref_freq / 10000) % 10;
    lia_freq_d3 <= (lia_ref_freq / 1000) % 10;
    lia_freq_d2 <= (lia_ref_freq / 100) % 10;
    lia_freq_d1 <= (lia_ref_freq / 10) % 10;
    lia_freq_d0 <= lia_ref_freq % 10;
    
    // 幅度显示（简化：直接取高位作为mV）
    lia_mag_d3 <= (ch1_lia_magnitude[23] ? 4'd0 : ((ch1_lia_magnitude >> 14) / 1000) % 10);
    lia_mag_d2 <= (ch1_lia_magnitude[23] ? 4'd0 : ((ch1_lia_magnitude >> 14) / 100) % 10);
    lia_mag_d1 <= (ch1_lia_magnitude[23] ? 4'd0 : ((ch1_lia_magnitude >> 14) / 10) % 10);
    lia_mag_d0 <= (ch1_lia_magnitude[23] ? 4'd0 : (ch1_lia_magnitude >> 14) % 10);
    
    // 相位显示（0-65535 -> 0-360度）
    lia_phase_d2 <= ((ch1_lia_phase * 360) >> 16) / 100;
    lia_phase_d1 <= (((ch1_lia_phase * 360) >> 16) / 10) % 10;
    lia_phase_d0 <= ((ch1_lia_phase * 360) >> 16) % 10;
    
    // SNR显示（8.8定点 -> 整数dB）
    lia_snr_d2 <= (lia_snr_estimate >> 8) / 100;
    lia_snr_d1 <= ((lia_snr_estimate >> 8) / 10) % 10;
    lia_snr_d0 <= (lia_snr_estimate >> 8) % 10;
```

### 修改4：添加区域初始化（约Line 1095）

**位置**：在 `in_auto_test_area <= 1'b0;` 后面添加

```verilog
        in_auto_test_area <= 1'b0;  // 默认不在自动测试区域
        
        // 锁相放大区域初始化
        in_lia_area <= 1'b0;  // 默认不在锁相放大区域
```

### 修改5：添加显示逻辑（约Line 2260，在自动测试显示之前）

**关键**：插入位置在 `else if (auto_test_enable && pixel_y_d1 >= AUTO_TEST_Y_START...` **之前**

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
        
        // ===== 第1行：标题 "Lock-in Amp" =====
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
            end else begin
                in_char_area <= 1'b0;
            end
        end
        
        // ===== 第2行："Ref: 001000 Hz" =====
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
            end else begin
                in_char_area <= 1'b0;
            end
        end
        
        // ===== 第3行："Mode: DDS/CH2/Ext" =====
        else if (pixel_y_d1 < (LIA_Y_START + 3*LIA_LINE_HEIGHT)) begin
            if (pixel_x_d1 >= LIA_X_START && pixel_x_d1 < LIA_X_START + 15*LIA_CHAR_WIDTH) begin
                case ((pixel_x_d1 - LIA_X_START) / LIA_CHAR_WIDTH)
                    0: char_code <= 8'd77;  // 'M'
                    1: char_code <= 8'd111; // 'o'
                    2: char_code <= 8'd100; // 'd'
                    3: char_code <= 8'd101; // 'e'
                    4: char_code <= 8'd58;  // ':'
                    5: char_code <= 8'd32;  // ' '
                    // DDS模式
                    6: char_code <= (lia_ref_mode == 2'd0) ? 8'd68 : 8'd32;  // 'D'
                    7: char_code <= (lia_ref_mode == 2'd0) ? 8'd68 : 8'd32;  // 'D'
                    8: char_code <= (lia_ref_mode == 2'd0) ? 8'd83 : 8'd32;  // 'S'
                    // CH2模式
                    9: char_code <= (lia_ref_mode == 2'd1) ? 8'd67 : 8'd32;  // 'C'
                    10: char_code <= (lia_ref_mode == 2'd1) ? 8'd72 : 8'd32;  // 'H'
                    11: char_code <= (lia_ref_mode == 2'd1) ? 8'd50 : 8'd32;  // '2'
                    // Ext模式
                    12: char_code <= (lia_ref_mode == 2'd2) ? 8'd69 : 8'd32;  // 'E'
                    13: char_code <= (lia_ref_mode == 2'd2) ? 8'd120 : 8'd32; // 'x'
                    14: char_code <= (lia_ref_mode == 2'd2) ? 8'd116 : 8'd32; // 't'
                    default: char_code <= 8'd32;
                endcase
                char_col <= lia_char_col;
                in_char_area <= 1'b1;
            end else begin
                in_char_area <= 1'b0;
            end
        end
        
        // ===== 第4行："Mag: 0000 mV" =====
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
            end else begin
                in_char_area <= 1'b0;
            end
        end
        
        // ===== 第5行："Phase: 000 deg" =====
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
            end else begin
                in_char_area <= 1'b0;
            end
        end
        
        // ===== 第6行："SNR: 00 dB" =====
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
            end else begin
                in_char_area <= 1'b0;
            end
        end
        
        // ===== 第7行："Status: LOCKED/UNLOCK" =====
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
                    // LOCKED or UNLOCK
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
            end else begin
                in_char_area <= 1'b0;
            end
        end
        
        else begin
            in_char_area <= 1'b0;
        end
    end
```

### 修改6：添加颜色合成（约Line 2920）

**位置**：在自动测试区域颜色合成之后、参数显示区域之前

```verilog
        // 自动测试区域颜色（深蓝背景+白字）
        if (in_auto_test_area_d3) begin
            ... // 现有自动测试颜色代码
        end
        
        // 锁相放大区域颜色（深绿背景+白字）
        else if (in_lia_area_d3) begin
            if (char_pixel_row_d2[char_col_d2]) begin
                // 字符像素：白色
                rgb_out_reg <= 24'hFFFFFF;
            end else begin
                // 背景：深绿色（与锁相放大功能相关）
                rgb_out_reg <= 24'h003300;
            end
        end
        
        // 参数显示区域（深灰背景）
        else if (pixel_y_d4 >= PARAM_Y_START && ...
```

## 时序注意事项

1. **延迟链匹配**：`in_lia_area_d3` 必须与 `pixel_y_d4` 对齐（3拍延迟）
2. **预计算优化**：所有除法/取模在帧开始时完成，避免实时计算违例
3. **fanout控制**：`weak_sig_enable` 只在字符生成阶段判断一次
4. **流水线深度**：保持与auto_test相同的4级流水线

## 验证检查清单

- [ ] 复位逻辑已添加
- [ ] 延迟链更新已添加
- [ ] 数据预处理已添加
- [ ] 区域初始化已添加
- [ ] 显示逻辑已添加（7行文字）
- [ ] 颜色合成已添加
- [ ] 顶层模块连接已更新
- [ ] 编译无语法错误
- [ ] 时序检查WNS > -5ns
- [ ] 硬件测试显示正确

## 下一步：顶层模块连接

见《锁相放大HDMI显示补丁.md》第11节
