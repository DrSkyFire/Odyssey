#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
hdmi_display_ctrl.v 表格式参数显示重构脚本
功能：替换1094-2047行的旧参数显示代码为新的表格框架
"""

import sys

# 新的表格框架代码（简化版，包含表头和占位符）
NEW_TABLE_CODE = '''    //=========================================================================
    // 表格式参数显示区域 (新版)
    //=========================================================================
    if (pixel_y_d1 >= PARAM_Y_START && pixel_y_d1 < PARAM_Y_END) begin
        
        //=====================================================================
        // 表头行 (Y: 580-600, 20px高)
        //=====================================================================
        if (pixel_y_d1 >= TABLE_Y_HEADER && pixel_y_d1 < TABLE_Y_HEADER + 20) begin
            char_row <= (pixel_y_d1 - TABLE_Y_HEADER) << 1;
            
            // 列1: "CH"
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
            
            // 列2: "Freq"
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
            
            // 列3: "Ampl"
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
            
            // 列4: "Duty"
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
            
            // 列5: "THD"
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
            
            // 列6: "Wave"
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
        
        //=====================================================================
        // CH1数据行 (Y: 600-640, 40px高) - 临时简化版
        //=====================================================================
        else if (pixel_y_d1 >= TABLE_Y_CH1 && pixel_y_d1 < TABLE_Y_CH1 + ROW_HEIGHT) begin
            char_row <= (pixel_y_d1 - TABLE_Y_CH1) << 1;
            
            // 临时显示 "1" 作为占位符
            if (pixel_x_d1 >= COL_CH_X + 12 && pixel_x_d1 < COL_CH_X + 28) begin
                char_code <= 8'd49;  // '1'
                char_col <= pixel_x_d1 - COL_CH_X - 12'd12;
                in_char_area <= ch1_enable;
            end
            else begin
                in_char_area <= 1'b0;
            end
        end
        
        //=====================================================================
        // CH2数据行 (Y: 640-680, 40px高) - 临时简化版
        //=====================================================================
        else if (pixel_y_d1 >= TABLE_Y_CH2 && pixel_y_d1 < TABLE_Y_CH2 + ROW_HEIGHT) begin
            char_row <= (pixel_y_d1 - TABLE_Y_CH2) << 1;
            
            // 临时显示 "2" 作为占位符
            if (pixel_x_d1 >= COL_CH_X + 12 && pixel_x_d1 < COL_CH_X + 28) begin
                char_code <= 8'd50;  // '2'
                char_col <= pixel_x_d1 - COL_CH_X - 12'd12;
                in_char_area <= ch2_enable;
            end
            else begin
                in_char_area <= 1'b0;
            end
        end
        
        //=====================================================================
        // 相位差行 (Y: 680-720, 40px高) - 临时简化版
        //=====================================================================
        else if (pixel_y_d1 >= TABLE_Y_PHASE && pixel_y_d1 < PARAM_Y_END) begin
            char_row <= (pixel_y_d1 - TABLE_Y_PHASE) << 1;
            
            // 临时显示 "Phase" 作为占位符
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
            else begin
                in_char_area <= 1'b0;
            end
        end
        
        else begin
            in_char_area <= 1'b0;
        end
    end  // 结束 if (pixel_y_d1 >= PARAM_Y_START && pixel_y_d1 < PARAM_Y_END)
'''

def refactor_hdmi_display():
    """重构hdmi_display_ctrl.v文件"""
    
    file_path = 'source/source/hdmi_display_ctrl.v'
    
    print(f"读取文件: {file_path}")
    with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
        lines = f.readlines()
    
    print(f"原始文件行数: {len(lines)}")
    
    # 替换策略：保留1-1093行，插入新代码，保留2048行之后
    # 注意：Python列表索引从0开始，行号从1开始
    new_lines = []
    new_lines.extend(lines[0:1093])  # 保留1-1093行
    new_lines.append(NEW_TABLE_CODE)  # 插入新代码
    new_lines.extend(lines[2047:])    # 保留2048行之后
    
    print(f"新文件行数: {len(new_lines)}")
    print(f"删除行数: {2047 - 1093 + 1} = 955行")
    print(f"新增代码: {NEW_TABLE_CODE.count(chr(10)) + 1}行")
    
    # 写回文件
    print(f"写回文件: {file_path}")
    with open(file_path, 'w', encoding='utf-8', errors='ignore') as f:
        f.writelines(new_lines)
    
    print("✅ 重构完成！")
    return 0

if __name__ == '__main__':
    sys.exit(refactor_hdmi_display())
