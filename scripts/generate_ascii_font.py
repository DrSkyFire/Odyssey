#!/usr/bin/env python3
# -*- coding: utf-8 -*-
#
# Copyright 2025 DrSkyFire
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0
# Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
"""
ASCII 16×32字体生成器
自动生成Verilog格式的字符ROM文件
适用于FPGA HDMI显示项目
"""

import os
import sys

# 配置参数
CHAR_WIDTH = 16
CHAR_HEIGHT = 32
ASCII_START = 32
ASCII_END = 126
OUTPUT_FILE = "source/source/ascii_rom_16x32_full.v"

# 简化版: 使用内置点阵字体数据
# 如果需要生成真实字体,请安装 Pillow: pip install Pillow
USE_PILLOW = False

try:
    from PIL import Image, ImageDraw, ImageFont
    USE_PILLOW = True
    print("✅ 检测到Pillow库,将使用TrueType字体渲染")
except ImportError:
    print("⚠️ 未安装Pillow,将使用内置简化字体")
    print("   安装方法: pip install Pillow")

def generate_char_bitmap_pillow(char, font):
    """使用Pillow生成字符位图"""
    img = Image.new('1', (CHAR_WIDTH, CHAR_HEIGHT), color=0)
    draw = ImageDraw.Draw(img)
    
    # 获取字符边界并居中
    bbox = draw.textbbox((0, 0), char, font=font)
    w, h = bbox[2] - bbox[0], bbox[3] - bbox[1]
    x = (CHAR_WIDTH - w) // 2
    y = (CHAR_HEIGHT - h) // 2 - 2
    draw.text((x, y), char, fill=1, font=font)
    
    # 转换为Verilog二进制格式
    bitmap = []
    for y in range(CHAR_HEIGHT):
        row = 0
        for x in range(CHAR_WIDTH):
            if img.getpixel((x, y)):
                row |= (1 << (15 - x))
        bitmap.append(f"16'b{row:016b}")
    
    return bitmap

def generate_char_bitmap_builtin(char):
    """使用内置简化字体(仅数字和基本符号)"""
    # 这里返回空白字符,实际项目中应该有完整的点阵数据
    # 或者使用现有的char_rom_16x32.v中的数据
    bitmap = [f"16'b{'0'*16}" for _ in range(CHAR_HEIGHT)]
    
    # 简单示例:为数字0-9生成竖线
    ascii_code = ord(char)
    if 48 <= ascii_code <= 57:  # 数字0-9
        digit = ascii_code - 48
        for row in range(8, 22):
            bitmap[row] = "16'b0000001111000000"
    
    return bitmap

def main():
    print(f"=== ASCII 16×32字体ROM生成器 ===\n")
    
    # 加载字体
    font = None
    if USE_PILLOW:
        font_paths = [
            "C:/Windows/Fonts/consola.ttf",  # Windows Consolas
            "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",  # Linux
            "/System/Library/Fonts/Monaco.dfont"  # macOS
        ]
        
        for font_path in font_paths:
            if os.path.exists(font_path):
                try:
                    font = ImageFont.truetype(font_path, 24)
                    print(f"✅ 加载字体: {font_path}")
                    break
                except Exception as e:
                    print(f"⚠️ 无法加载 {font_path}: {e}")
        
        if font is None:
            print("⚠️ 未找到TrueType字体,使用默认字体")
            font = ImageFont.load_default()
    
    # 生成Verilog文件
    os.makedirs(os.path.dirname(OUTPUT_FILE), exist_ok=True)
    
    with open(OUTPUT_FILE, 'w', encoding='utf-8') as f:
        # 写入文件头
        f.write("""//=============================================================================
// 文件名: ascii_rom_16x32_full.v
// 功能: 完整ASCII字符ROM (16×32像素)
// 字符范围: ASCII 32-126 (空格到~,共95个字符)
// 自动生成: generate_ascii_font.py
// 生成时间: """ + __import__('datetime').datetime.now().strftime('%Y-%m-%d %H:%M:%S') + """
//=============================================================================

module ascii_rom_16x32_full (
    input        clk,
    input  [7:0] char_code,   // ASCII码 (32-126有效)
    input  [4:0] char_row,    // 字符行号 (0-31)
    output [15:0] char_data   // 16位字符行数据
);

//=============================================================================
// ROM存储器: 95个字符 × 32行 = 3040行数据
//=============================================================================
reg [15:0] rom [0:3039];

initial begin
""")
        
        # 生成每个字符
        char_count = 0
        for ascii_code in range(ASCII_START, ASCII_END + 1):
            char = chr(ascii_code)
            index = ascii_code - ASCII_START
            
            # 转义特殊字符用于注释
            char_repr = repr(char) if char.isprintable() else f"0x{ascii_code:02X}"
            f.write(f"\n    // ASCII {ascii_code} ({index}): {char_repr}\n")
            
            # 生成位图
            if USE_PILLOW and font:
                bitmap = generate_char_bitmap_pillow(char, font)
            else:
                bitmap = generate_char_bitmap_builtin(char)
            
            # 写入ROM数据
            for row_num, row_data in enumerate(bitmap):
                addr = index * 32 + row_num
                f.write(f"    rom[{addr:4d}] = {row_data};\n")
            
            char_count += 1
            if char_count % 10 == 0:
                print(f"  生成进度: {char_count}/{ASCII_END - ASCII_START + 1} 字符...")
        
        # 写入读取逻辑
        f.write("""
end

//=============================================================================
// ROM读取逻辑 (带流水线)
//=============================================================================
reg [15:0] char_data_reg;
reg [11:0] rom_addr;

always @(posedge clk) begin
    // 计算地址: (char_code - 32) * 32 + char_row
    if (char_code >= 32 && char_code <= 126) begin
        rom_addr <= (char_code - 32) * 32 + {7'd0, char_row};
        char_data_reg <= rom[rom_addr];
    end else begin
        char_data_reg <= 16'h0000;  // 非法字符显示空白
    end
end

assign char_data = char_data_reg;

endmodule
""")
    
    # 生成完成
    file_size = os.path.getsize(OUTPUT_FILE)
    print(f"\n✅ 字体ROM生成完成!")
    print(f"   文件: {OUTPUT_FILE}")
    print(f"   字符数: {ASCII_END - ASCII_START + 1}")
    print(f"   文件大小: {file_size / 1024:.1f} KB")
    print(f"   ROM容量: {(ASCII_END - ASCII_START + 1) * 32 * 2} 字节 (~{(ASCII_END - ASCII_START + 1) * 32 * 2 / 1024:.1f}KB)")
    print("\n📝 后续步骤:")
    print("   1. 在hdmi_display_ctrl.v中将char_rom_16x32替换为ascii_rom_16x32_full")
    print("   2. 将char_code改为8位: reg [7:0] char_code;")
    print("   3. 使用ASCII码: char_code = 8'd70; // 'F'")
    print("   4. 或使用字符常量: char_code = \"F\"; ")

if __name__ == '__main__':
    main()
