#!/usr/bin/env python3
"""
修正720p字符显示高度：使用完整32px高度
字符ROM是16x32，必须显示完整32行，不能截断

问题分析：
- 字符ROM: 16列 × 32行
- char_row取值范围: 0-31
- 之前错误地设置为16px高度，导致只显示了一半字符

解决方案：
1. 参数区6行：每行32px高度，总共需要192px
2. Y轴/X轴标度：32px高度
3. 行间距可以更小，让6行文字挤得更紧凑
"""

def calculate_compact_layout():
    """计算紧凑布局：6行文字塞入140px空间"""
    param_start = 580
    available_height = 720 - param_start  # 140px
    char_height = 32
    
    # 6行文字，每行32px，需要最小间距
    # 总需求：6*32 = 192px，但只有140px可用
    # 方案1：缩小间距到8px -> 6*32 + 5*8 = 232px（太大）
    # 方案2：行间距2px -> 6*32 + 5*2 = 202px（仍太大）
    # 方案3：重叠显示，间距-2px -> 6*32 + 5*(-2) = 182px（仍太大）
    
    # 最佳方案：间距-8px（允许重叠）
    spacing = -8
    positions = []
    y = 0
    for i in range(6):
        row_start = y
        row_end = y + char_height
        positions.append((row_start, row_end))
        y += char_height + spacing
    
    total_height = positions[-1][1]
    
    print("=== 720p参数区紧凑布局 (32px字符高度) ===")
    print(f"可用高度: {available_height}px")
    print(f"字符高度: {char_height}px")
    print(f"行间距: {spacing}px (重叠)")
    print(f"总高度: {total_height}px")
    print(f"\n各行位置（相对PARAM_Y_START={param_start}）:")
    for i, (start, end) in enumerate(positions, 1):
        abs_start = param_start + start
        abs_end = param_start + end
        print(f"第{i}行: Y={start}-{end-1} (绝对: {abs_start}-{abs_end-1})")
    
    # Y轴标度：也需要32px
    spectrum_start = 50
    spectrum_height = 500
    
    # 5个刻度点的Y位置（居中对齐）
    y_positions = {
        '100%': spectrum_start,
        '75%': spectrum_start + int(spectrum_height * 0.25),
        '50%': spectrum_start + int(spectrum_height * 0.50),
        '25%': spectrum_start + int(spectrum_height * 0.75),
        '0%': spectrum_start + spectrum_height - 32 - 2
    }
    
    print(f"\n=== Y轴标度位置 (32px字符高度) ===")
    for label, y_start in y_positions.items():
        print(f"{label:>4}: Y={y_start}-{y_start+31}")
    
    print(f"\n=== X轴标度位置 ===")
    print(f"Y范围: 550-581 (32px高)")
    
    return positions, y_positions

def fix_char_height_to_32px():
    filepath = r"e:\Odyssey_proj\source\source\hdmi_display_ctrl.v"
    
    positions, y_positions = calculate_compact_layout()
    
    # 读取文件
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # 参数区6行替换（间距-8px，重叠显示）
    param_replacements = [
        # 第1行：0-15 → 0-31
        ("PARAM_Y_START && pixel_y_d1 < PARAM_Y_START + 16",
         "PARAM_Y_START && pixel_y_d1 < PARAM_Y_START + 32"),
        
        # 第2行：24-39 → 24-55
        ("PARAM_Y_START + 24 && pixel_y_d1 < PARAM_Y_START + 40",
         "PARAM_Y_START + 24 && pixel_y_d1 < PARAM_Y_START + 56"),
        ("12'd24", "12'd24", 1),  # char_row计算保持
        
        # 第3行：48-63 → 48-79
        ("PARAM_Y_START + 48 && pixel_y_d1 < PARAM_Y_START + 64",
         "PARAM_Y_START + 48 && pixel_y_d1 < PARAM_Y_START + 80"),
        ("12'd48", "12'd48", 1),
        
        # 第4行：72-87 → 72-103
        ("PARAM_Y_START + 72 && pixel_y_d1 < PARAM_Y_START + 88",
         "PARAM_Y_START + 72 && pixel_y_d1 < PARAM_Y_START + 104"),
        ("12'd72", "12'd72", 1),
        
        # 第5行：96-111 → 96-127
        ("PARAM_Y_START + 96 && pixel_y_d1 < PARAM_Y_START + 112",
         "PARAM_Y_START + 96 && pixel_y_d1 < PARAM_Y_START + 128"),
        ("12'd96", "12'd96", 1),
        
        # 第6行：120-135 → 120-151
        ("PARAM_Y_START + 120 && pixel_y_d1 < PARAM_Y_START + 136",
         "PARAM_Y_START + 120 && pixel_y_d1 < PARAM_Y_START + 152"),
        ("12'd120", "12'd120", 1),
    ]
    
    # Y轴标度替换（32px高度）
    y_axis_replacements = [
        # 100%: 50-65 → 50-81
        ("pixel_y >= 50 && pixel_y < 66",
         "pixel_y >= 50 && pixel_y < 82"),
        
        # 75%: 175-190 → 175-206
        ("pixel_y >= 175 && pixel_y < 191",
         "pixel_y >= 175 && pixel_y < 207"),
        ("12'd175", "12'd175", 1),
        
        # 50%: 300-315 → 300-331
        ("pixel_y >= 300 && pixel_y < 316",
         "pixel_y >= 300 && pixel_y < 332"),
        ("12'd300", "12'd300", 1),
        
        # 25%: 425-440 → 425-456
        ("pixel_y >= 425 && pixel_y < 441",
         "pixel_y >= 425 && pixel_y < 457"),
        ("12'd425", "12'd425", 1),
        
        # 0%: 530-545 → 516-547 (向上移动保持在范围内)
        ("pixel_y >= 530 && pixel_y < 546",
         "pixel_y >= 516 && pixel_y < 548"),
        ("12'd530", "12'd516", 1),
    ]
    
    # X轴标度：16px → 32px
    x_axis_replacements = [
        ("SPECTRUM_Y_END && pixel_y_d1 < SPECTRUM_Y_END + 16",
         "SPECTRUM_Y_END && pixel_y_d1 < SPECTRUM_Y_END + 32"),
    ]
    
    all_replacements = param_replacements + y_axis_replacements + x_axis_replacements
    
    # 执行替换
    modified = content
    for item in all_replacements:
        if len(item) == 3:
            old_str, new_str, count = item
            modified = modified.replace(old_str, new_str, count)
        else:
            old_str, new_str = item
            count = modified.count(old_str)
            modified = modified.replace(old_str, new_str)
            if count > 0:
                print(f"✓ 替换 '{old_str[:40]}...' ({count}次)")
    
    # 写回文件
    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(modified)
    
    print(f"\n✅ 字符高度修正为32px完成！")

if __name__ == "__main__":
    fix_char_height_to_32px()
