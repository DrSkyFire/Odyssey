//=============================================================================
// 模块名: param_table_display
// 描述: 表格式参数显示模块（用于hdmi_display_ctrl.v）
// 作者: AI Assistant
// 日期: 2025-11-01
//=============================================================================
// 这个文件包含了新的表格式参数显示逻辑
// 将替换hdmi_display_ctrl.v中1093-2047行之间的旧代码
//=============================================================================

// 注意：这不是一个独立的module，而是要插入到hdmi_display_ctrl的always块中的代码片段

// 判断是否在参数显示区域
if (pixel_y_d1 >= PARAM_Y_START && pixel_y_d1 < PARAM_Y_END) begin
    
    //=========================================================================
    // 表头行 (Y: 580-600, 20px高)
    //=========================================================================
    if (pixel_y_d1 >= TABLE_Y_HEADER && pixel_y_d1 < TABLE_Y_HEADER + 20) begin
        char_row <= (pixel_y_d1 - TABLE_Y_HEADER) << 1;
        
        // 列1: "CH" (X: 40-80, 居中显示)
        if (pixel_x_d1 >= COL_CH_X + 4 && pixel_x_d1 < COL_CH_X + 20) begin
            char_code <= 8'd67;  // 'C'
            char_col <= pixel_x_d1 - COL_CH_X - 12'd4;
            in_char_area <= 1'b1;
        end
        else if (pixel_x_d1 >= COL_CH_X + 20 && pixel_x_d1 < COL_CH_X + 36) begin
            char_code <= 8'd72;  // 'H'
            char_col <= pixel_x_d1 - COL_CH_X - 12'd20;
            in_char_area <= 1'b1;
        end
        
        // 列2: "Freq" (X: 80-280)
        else if (pixel_x_d1 >= COL_FREQ_X + 8 && pixel_x_d1 < COL_FREQ_X + 24) begin
            char_code <= 8'd70;  // 'F'
            char_col <= pixel_x_d1 - COL_FREQ_X - 12'd8;
            in_char_area <= 1'b1;
        end
        else if (pixel_x_d1 >= COL_FREQ_X + 24 && pixel_x_d1 < COL_FREQ_X + 40) begin
            char_code <= 8'd114;  // 'r'
            char_col <= pixel_x_d1 - COL_FREQ_X - 12'd24;
            in_char_area <= 1'b1;
        end
        else if (pixel_x_d1 >= COL_FREQ_X + 40 && pixel_x_d1 < COL_FREQ_X + 56) begin
            char_code <= 8'd101;  // 'e'
            char_col <= pixel_x_d1 - COL_FREQ_X - 12'd40;
            in_char_area <= 1'b1;
        end
        else if (pixel_x_d1 >= COL_FREQ_X + 56 && pixel_x_d1 < COL_FREQ_X + 72) begin
            char_code <= 8'd113;  // 'q'
            char_col <= pixel_x_d1 - COL_FREQ_X - 12'd56;
            in_char_area <= 1'b1;
        end
        
        // 列3: "Ampl" (X: 280-400)
        else if (pixel_x_d1 >= COL_AMPL_X + 8 && pixel_x_d1 < COL_AMPL_X + 24) begin
            char_code <= 8'd65;  // 'A'
            char_col <= pixel_x_d1 - COL_AMPL_X - 12'd8;
            in_char_area <= 1'b1;
        end
        else if (pixel_x_d1 >= COL_AMPL_X + 24 && pixel_x_d1 < COL_AMPL_X + 40) begin
            char_code <= 8'd109;  // 'm'
            char_col <= pixel_x_d1 - COL_AMPL_X - 12'd24;
            in_char_area <= 1'b1;
        end
        else if (pixel_x_d1 >= COL_AMPL_X + 40 && pixel_x_d1 < COL_AMPL_X + 56) begin
            char_code <= 8'd112;  // 'p'
            char_col <= pixel_x_d1 - COL_AMPL_X - 12'd40;
            in_char_area <= 1'b1;
        end
        else if (pixel_x_d1 >= COL_AMPL_X + 56 && pixel_x_d1 < COL_AMPL_X + 72) begin
            char_code <= 8'd108;  // 'l'
            char_col <= pixel_x_d1 - COL_AMPL_X - 12'd56;
            in_char_area <= 1'b1;
        end
        
        // 列4: "Duty" (X: 400-520)
        else if (pixel_x_d1 >= COL_DUTY_X + 8 && pixel_x_d1 < COL_DUTY_X + 24) begin
            char_code <= 8'd68;  // 'D'
            char_col <= pixel_x_d1 - COL_DUTY_X - 12'd8;
            in_char_area <= 1'b1;
        end
        else if (pixel_x_d1 >= COL_DUTY_X + 24 && pixel_x_d1 < COL_DUTY_X + 40) begin
            char_code <= 8'd117;  // 'u'
            char_col <= pixel_x_d1 - COL_DUTY_X - 12'd24;
            in_char_area <= 1'b1;
        end
        else if (pixel_x_d1 >= COL_DUTY_X + 40 && pixel_x_d1 < COL_DUTY_X + 56) begin
            char_code <= 8'd116;  // 't'
            char_col <= pixel_x_d1 - COL_DUTY_X - 12'd40;
            in_char_area <= 1'b1;
        end
        else if (pixel_x_d1 >= COL_DUTY_X + 56 && pixel_x_d1 < COL_DUTY_X + 72) begin
            char_code <= 8'd121;  // 'y'
            char_col <= pixel_x_d1 - COL_DUTY_X - 12'd56;
            in_char_area <= 1'b1;
        end
        
        // 列5: "THD" (X: 520-640)
        else if (pixel_x_d1 >= COL_THD_X + 8 && pixel_x_d1 < COL_THD_X + 24) begin
            char_code <= 8'd84;  // 'T'
            char_col <= pixel_x_d1 - COL_THD_X - 12'd8;
            in_char_area <= 1'b1;
        end
        else if (pixel_x_d1 >= COL_THD_X + 24 && pixel_x_d1 < COL_THD_X + 40) begin
            char_code <= 8'd72;  // 'H'
            char_col <= pixel_x_d1 - COL_THD_X - 12'd24;
            in_char_area <= 1'b1;
        end
        else if (pixel_x_d1 >= COL_THD_X + 40 && pixel_x_d1 < COL_THD_X + 56) begin
            char_code <= 8'd68;  // 'D'
            char_col <= pixel_x_d1 - COL_THD_X - 12'd40;
            in_char_area <= 1'b1;
        end
        
        // 列6: "Wave" (X: 640-1240)
        else if (pixel_x_d1 >= COL_WAVE_X + 8 && pixel_x_d1 < COL_WAVE_X + 24) begin
            char_code <= 8'd87;  // 'W'
            char_col <= pixel_x_d1 - COL_WAVE_X - 12'd8;
            in_char_area <= 1'b1;
        end
        else if (pixel_x_d1 >= COL_WAVE_X + 24 && pixel_x_d1 < COL_WAVE_X + 40) begin
            char_code <= 8'd97;  // 'a'
            char_col <= pixel_x_d1 - COL_WAVE_X - 12'd24;
            in_char_area <= 1'b1;
        end
        else if (pixel_x_d1 >= COL_WAVE_X + 40 && pixel_x_d1 < COL_WAVE_X + 56) begin
            char_code <= 8'd118;  // 'v'
            char_col <= pixel_x_d1 - COL_WAVE_X - 12'd40;
            in_char_area <= 1'b1;
        end
        else if (pixel_x_d1 >= COL_WAVE_X + 56 && pixel_x_d1 < COL_WAVE_X + 72) begin
            char_code <= 8'd101;  // 'e'
            char_col <= pixel_x_d1 - COL_WAVE_X - 12'd56;
            in_char_area <= 1'b1;
        end
        else begin
            in_char_area <= 1'b0;
        end
    end
    
    //=========================================================================
    // CH1数据行 (Y: 600-640, 40px高)
    //=========================================================================
    else if (pixel_y_d1 >= TABLE_Y_CH1 && pixel_x_d1 < TABLE_Y_CH1 + ROW_HEIGHT) begin
        char_row <= (pixel_y_d1 - TABLE_Y_CH1) << 1;
        
        // 列1: "1" (通道号, 居中)
        if (pixel_x_d1 >= COL_CH_X + 12 && pixel_x_d1 < COL_CH_X + 28) begin
            char_code <= 8'd49;  // '1'
            char_col <= pixel_x_d1 - COL_CH_X - 12'd12;
            in_char_area <= ch1_enable;
        end
        
        // 列2: 频率 (格式: "20000Hz " 或 "656.00kHz")
        // 继续使用之前修复的频率显示逻辑...
        // (为简化，这里先留空，后续补充)
        
        else begin
            in_char_area <= 1'b0;
        end
    end
    
    //=========================================================================
    // CH2数据行 (Y: 640-680, 40px高)  
    //=========================================================================
    else if (pixel_y_d1 >= TABLE_Y_CH2 && pixel_y_d1 < TABLE_Y_CH2 + ROW_HEIGHT) begin
        char_row <= (pixel_y_d1 - TABLE_Y_CH2) << 1;
        
        // 列1: "2"
        if (pixel_x_d1 >= COL_CH_X + 12 && pixel_x_d1 < COL_CH_X + 28) begin
            char_code <= 8'd50;  // '2'
            char_col <= pixel_x_d1 - COL_CH_X - 12'd12;
            in_char_area <= ch2_enable;
        end
        else begin
            in_char_area <= 1'b0;
        end
    end
    
    //=========================================================================
    // 相位差行 (Y: 680-720, 40px高)
    //=========================================================================
    else if (pixel_y_d1 >= TABLE_Y_PHASE && pixel_y_d1 < PARAM_Y_END) begin
        char_row <= (pixel_y_d1 - TABLE_Y_PHASE) << 1;
        
        // "Phase Diff: 123.4°" (居中显示)
        if (pixel_x_d1 >= 500 && pixel_x_d1 < 516) begin
            char_code <= 8'd80;  // 'P'
            char_col <= pixel_x_d1 - 12'd500;
            in_char_area <= 1'b1;
        end
        else if (pixel_x_d1 >= 516 && pixel_x_d1 < 532) begin
            char_code <= 8'd104;  // 'h'
            char_col <= pixel_x_d1 - 12'd516;
            in_char_area <= 1'b1;
        end
        else if (pixel_x_d1 >= 532 && pixel_x_d1 < 548) begin
            char_code <= 8'd97;  // 'a'
            char_col <= pixel_x_d1 - 12'd532;
            in_char_area <= 1'b1;
        end
        else if (pixel_x_d1 >= 548 && pixel_x_d1 < 564) begin
            char_code <= 8'd115;  // 's'
            char_col <= pixel_x_d1 - 12'd548;
            in_char_area <= 1'b1;
        end
        else if (pixel_x_d1 >= 564 && pixel_x_d1 < 580) begin
            char_code <= 8'd101;  // 'e'
            char_col <= pixel_x_d1 - 12'd564;
            in_char_area <= 1'b1;
        end
        else if (pixel_x_d1 >= 580 && pixel_x_d1 < 596) begin
            char_code <= 8'd58;  // ':'
            char_col <= pixel_x_d1 - 12'd580;
            in_char_area <= 1'b1;
        end
        // 数值 "123.4°"
        else if (pixel_x_d1 >= 604 && pixel_x_d1 < 620) begin
            char_code <= digit_to_ascii(phase_d3);  // 百位
            char_col <= pixel_x_d1 - 12'd604;
            in_char_area <= 1'b1;
        end
        else if (pixel_x_d1 >= 620 && pixel_x_d1 < 636) begin
            char_code <= digit_to_ascii(phase_d2);  // 十位
            char_col <= pixel_x_d1 - 12'd620;
            in_char_area <= 1'b1;
        end
        else if (pixel_x_d1 >= 636 && pixel_x_d1 < 652) begin
            char_code <= digit_to_ascii(phase_d1);  // 个位
            char_col <= pixel_x_d1 - 12'd636;
            in_char_area <= 1'b1;
        end
        else if (pixel_x_d1 >= 652 && pixel_x_d1 < 668) begin
            char_code <= 8'd46;  // '.'
            char_col <= pixel_x_d1 - 12'd652;
            in_char_area <= 1'b1;
        end
        else if (pixel_x_d1 >= 668 && pixel_x_d1 < 684) begin
            char_code <= digit_to_ascii(phase_d0);  // 小数位
            char_col <= pixel_x_d1 - 12'd668;
            in_char_area <= 1'b1;
        end
        else if (pixel_x_d1 >= 684 && pixel_x_d1 < 700) begin
            char_code <= 8'd176;  // '°' (degree symbol, 可能需要确认字符集)
            char_col <= pixel_x_d1 - 12'd684;
            in_char_area <= 1'b1;
        end
        else begin
            in_char_area <= 1'b0;
        end
    end
    
    else begin
        in_char_area <= 1'b0;
    end
    
end  // 结束 if (pixel_y_d1 >= PARAM_Y_START && pixel_y_d1 < PARAM_Y_END)
