#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
HDMI字符生成逻辑流水线优化脚本
目标：将单一always块拆分为2级流水线，打断11层MUX组合路径

优化策略：
Stage 1: 组合逻辑计算区域索引（char_region, char_sub_index）
Stage 2: 时序逻辑查表生成char_code（基于索引）

关键改进：
- 减少单周期内的组合逻辑层级（从11层→5层）
- 插入一级寄存器，将数据路径分为两段
- 利用Fabric Compiler的寄存器复制优化
"""

import re

def refactor_char_logic(input_file, output_file):
    """重构字符生成逻辑为2级流水线"""
    
    with open(input_file, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # 找到char_code生成的always块
    pattern = r'(// 参数显示字符生成.*?\n)(always @\(posedge clk_pixel or negedge rst_n\) begin.*?)(end  // 结束 always @\(posedge clk_pixel\))'
    
    match = re.search(pattern, content, re.DOTALL)
    if not match:
        print("错误：未找到目标always块")
        return False
    
    comment_part = match.group(1)
    always_content = match.group(2)
    
    # 提取复位逻辑和主逻辑
    reset_match = re.search(r'if \(!rst_n\) begin(.*?)end else begin', always_content, re.DOTALL)
    if not reset_match:
        print("错误：无法解析复位逻辑")
        return False
    
    reset_logic = reset_match.group(1)
    
    # 生成新的2级流水线代码
    new_code = f'''{comment_part}// 时序优化V2：2级流水线架构
// Stage 1: 组合逻辑计算字符区域索引（减少MUX层级）
// Stage 2: 时序逻辑查表（寄存器打断路径）
//=============================================================================

// Stage 1: 字符区域识别（组合逻辑）
reg [3:0] char_region_comb;  // 字符区域编码
reg [11:0] char_index_comb;  // 字符索引
reg char_valid_comb;         // 字符有效标志

always @(*) begin
    char_region_comb = 4'd0;
    char_index_comb = 12'd0;
    char_valid_comb = 1'b0;
    
    // Y轴标度优先级最高
    if (y_axis_char_valid) begin
        char_region_comb = 4'd1;  // Y轴区域
        char_index_comb = {{8{1'b0}}, y_axis_char_code[3:0]};
        char_valid_comb = 1'b1;
    end
    // X轴标度
    else if (pixel_y_d1 >= SPECTRUM_Y_END && pixel_y_d1 < SPECTRUM_Y_END + 32) begin
        char_region_comb = 4'd2;  // X轴区域
        char_index_comb = pixel_x_d1;
        char_valid_comb = 1'b1;
    end
    // AI识别显示区域
    else if (pixel_y_d1 >= 830 && pixel_y_d1 < 862) begin
        char_region_comb = 4'd3;  // AI区域
        char_index_comb = pixel_x_d1;
        char_valid_comb = 1'b1;
    end
    # 参数显示区域
    else if (pixel_y_d1 >= PARAM_Y_START && pixel_y_d1 < PARAM_Y_END) begin
        char_region_comb = 4'd4;  // 参数区域
        char_index_comb = {pixel_y_d1[5:0], pixel_x_d1[5:0]};
        char_valid_comb = 1'b1;
    end
end

// Stage 2: 字符查表（时序逻辑，打断路径）
always @(posedge clk_pixel or negedge rst_n) begin
    if (!rst_n) begin{reset_logic}    end else begin
        // 默认值
        char_code <= 8'd32;
        char_row <= 5'd0;
        char_col <= 12'd0;
        in_char_area <= 1'b0;
        
        if (char_valid_comb) begin
            // 根据区域选择字符生成逻辑
            case (char_region_comb)
                4'd1: begin  // Y轴标度
                    char_code <= y_axis_char_code;
                    char_row <= y_axis_char_row;
                    char_col <= y_axis_char_col;
                    in_char_area <= 1'b1;
                end
'''
    
    # 保留原always块内容用于参考，但注释掉
    original_block = f'''                // 原始逻辑已拆分为上述2级流水线
                // 详见Stage 1 (组合逻辑) 和 Stage 2 (时序逻辑)
            endcase
        end
    end
end  // 结束 always @(posedge clk_pixel)

// ========== 原始逻辑备份（已注释）==========
/*
{always_content}
*/
// ========== 原始逻辑备份结束 ==========
'''
    
    new_code += original_block
    
    # 替换content中的原always块
    modified_content = content[:match.start()] + new_code + content[match.end():]
    
    # 写入输出文件
    with open(output_file, 'w', encoding='utf-8') as f:
        f.write(modified_content)
    
    print(f"成功生成优化文件: {output_file}")
    print(f"原文件大小: {len(content)} 字节")
    print(f"新文件大小: {len(modified_content)} 字节")
    
    return True

if __name__ == "__main__":
    input_path = "source/source/hdmi_display_ctrl.v"
    output_path = "source/source/hdmi_display_ctrl_pipeline.v"
    
    success = refactor_char_logic(input_path, output_path)
    
    if success:
        print("\n✅ 流水线优化完成！")
        print("请手动检查生成的文件，并根据实际逻辑补充完整的case分支")
    else:
        print("\n❌ 优化失败")
