#!/usr/bin/env python3
"""
使用字符行跳过技术实现16px字符显示
原理：char_row每次+2，跳过奇数行，实现字符缩小到16px

16x32 ROM -> 显示16px高度：
- char_row = (pixel_y - start) * 2
- 这样pixel_y取0-15时，char_row取0,2,4,...,30（16个值）
"""

def calculate_skip_line_layout():
    """计算跳行布局：16px字符高度，20px间距"""
    param_start = 580
    available_height = 720 - param_start  # 140px
    char_height = 16  # 视觉高度
    spacing = 4  # 行间距
    
    positions = []
    y = 0
    for i in range(6):
        row_start = y
        row_end = y + char_height
        positions.append((row_start, row_end))
        y += char_height + spacing
    
    total_height = positions[-1][1]
    
    print("=== 720p参数区跳行布局 (16px视觉高度) ===")
    print(f"可用高度: {available_height}px")
    print(f"视觉字符高度: {char_height}px (跳行显示)")
    print(f"行间距: {spacing}px")
    print(f"总高度: {total_height}px")
    print(f"\n各行位置（相对PARAM_Y_START={param_start}）:")
    for i, (start, end) in enumerate(positions, 1):
        abs_start = param_start + start
        abs_end = param_start + end - 1
        print(f"第{i}行: Y={start:3d}-{end-1:3d} (绝对: {abs_start}-{abs_end}), char_row = (pixel_y-{start})*2")
    
    # Y轴标度：16px
    spectrum_start = 50
    spectrum_height = 500
    
    # 5个刻度点的Y位置，垂直居中对齐
    y_labels = [
        ('100%', spectrum_start),
        ('75%', spectrum_start + int(spectrum_height * 0.25)),
        ('50%', spectrum_start + int(spectrum_height * 0.50)),
        ('25%', spectrum_start + int(spectrum_height * 0.75)),
        ('0%', spectrum_start + spectrum_height - 16 - 2)
    ]
    
    print(f"\n=== Y轴标度位置 (16px视觉高度，跳行) ===")
    for label, y_start in y_labels:
        print(f"{label:>4}: Y={y_start:3d}-{y_start+15:3d}, char_row = (pixel_y-{y_start})*2")
    
    print(f"\n=== X轴标度位置 ===")
    print(f"Y范围: 550-565 (16px视觉高度，跳行)")
    
    return positions, y_labels

def generate_verilog_code():
    """生成Verilog代码片段"""
    positions, y_labels = calculate_skip_line_layout()
    
    print("\n=== Verilog代码修改要点 ===")
    print("\n// 参数区char_row计算（跳行）：")
    for i, (start, end) in enumerate(positions, 1):
        print(f"// 第{i}行: char_row <= (pixel_y_d1 - PARAM_Y_START - 12'd{start}) << 1;")
    
    print("\n// Y轴标度char_row计算（跳行）：")
    for label, y_start in y_labels:
        print(f"// {label}: char_row <= (pixel_y - 12'd{y_start}) << 1;")
    
    print("\n// X轴标度char_row计算（跳行）：")
    print("// char_row <= (pixel_y_d1 - SPECTRUM_Y_END) << 1;")

if __name__ == "__main__":
    generate_verilog_code()
