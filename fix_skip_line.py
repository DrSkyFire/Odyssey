#!/usr/bin/env python3
"""
批量修改为跳行显示（16px视觉高度）
"""

def fix_to_skip_line_display():
    filepath = r"e:\Odyssey_proj\source\source\hdmi_display_ctrl.v"
    
    # 读取文件
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # ========== 第一步：修改Y范围 ==========
    # 参数区6行
    param_replacements = [
        # 第1行：0-31 → 0-15
        ("PARAM_Y_START && pixel_y_d1 < PARAM_Y_START + 32",
         "PARAM_Y_START && pixel_y_d1 < PARAM_Y_START + 16"),
        
        # 第2行：24-55 → 20-35
        ("PARAM_Y_START + 24 && pixel_y_d1 < PARAM_Y_START + 56",
         "PARAM_Y_START + 20 && pixel_y_d1 < PARAM_Y_START + 36"),
        
        # 第3行：48-79 → 40-55
        ("PARAM_Y_START + 48 && pixel_y_d1 < PARAM_Y_START + 80",
         "PARAM_Y_START + 40 && pixel_y_d1 < PARAM_Y_START + 56"),
        
        # 第4行：72-103 → 60-75
        ("PARAM_Y_START + 72 && pixel_y_d1 < PARAM_Y_START + 104",
         "PARAM_Y_START + 60 && pixel_y_d1 < PARAM_Y_START + 76"),
        
        # 第5行：96-127 → 80-95
        ("PARAM_Y_START + 96 && pixel_y_d1 < PARAM_Y_START + 128",
         "PARAM_Y_START + 80 && pixel_y_d1 < PARAM_Y_START + 96"),
        
        # 第6行：120-151 → 100-115
        ("PARAM_Y_START + 120 && pixel_y_d1 < PARAM_Y_START + 152",
         "PARAM_Y_START + 100 && pixel_y_d1 < PARAM_Y_START + 116"),
    ]
    
    # Y轴标度
    y_axis_replacements = [
        # 100%: 50-81 → 50-65
        ("pixel_y >= 50 && pixel_y < 82",
         "pixel_y >= 50 && pixel_y < 66"),
        
        # 75%: 175-206 → 175-190
        ("pixel_y >= 175 && pixel_y < 207",
         "pixel_y >= 175 && pixel_y < 191"),
        
        # 50%: 300-331 → 300-315
        ("pixel_y >= 300 && pixel_y < 332",
         "pixel_y >= 300 && pixel_y < 316"),
        
        # 25%: 425-456 → 425-440
        ("pixel_y >= 425 && pixel_y < 457",
         "pixel_y >= 425 && pixel_y < 441"),
        
        # 0%: 516-547 → 532-547
        ("pixel_y >= 516 && pixel_y < 548",
         "pixel_y >= 532 && pixel_y < 548"),
    ]
    
    # X轴标度: 550-581 → 550-565
    x_axis_replacements = [
        ("SPECTRUM_Y_END && pixel_y_d1 < SPECTRUM_Y_END + 32",
         "SPECTRUM_Y_END && pixel_y_d1 < SPECTRUM_Y_END + 16"),
    ]
    
    # 执行Y范围替换
    modified = content
    for old_str, new_str in param_replacements + y_axis_replacements + x_axis_replacements:
        count = modified.count(old_str)
        if count > 0:
            modified = modified.replace(old_str, new_str)
            print(f"✓ Y范围: '{old_str[:35]}...' → '{new_str[:35]}...' ({count}次)")
    
    # ========== 第二步：修改char_row计算为跳行 ==========
    # 参数区char_row（需要手动处理，因为涉及复杂替换）
    char_row_replacements = [
        # 第1行保持：char_row <= pixel_y_d1 - PARAM_Y_START
        # 实际需要改为：char_row <= (pixel_y_d1 - PARAM_Y_START) << 1
        
        # 第2行：12'd24 → 12'd20，并添加<<1
        ("char_row <= pixel_y_d1 - PARAM_Y_START - 12'd24;",
         "char_row <= (pixel_y_d1 - PARAM_Y_START - 12'd20) << 1;"),
        
        # 第3行：12'd48 → 12'd40，并添加<<1
        ("char_row <= pixel_y_d1 - PARAM_Y_START - 12'd48;",
         "char_row <= (pixel_y_d1 - PARAM_Y_START - 12'd40) << 1;"),
        
        # 第4行：12'd72 → 12'd60，并添加<<1
        ("char_row <= pixel_y_d1 - PARAM_Y_START - 12'd72;",
         "char_row <= (pixel_y_d1 - PARAM_Y_START - 12'd60) << 1;"),
        
        # 第5行：12'd96 → 12'd80，并添加<<1
        ("char_row <= pixel_y_d1 - PARAM_Y_START - 12'd96;",
         "char_row <= (pixel_y_d1 - PARAM_Y_START - 12'd80) << 1;"),
        
        # 第6行：12'd120 → 12'd100，并添加<<1
        ("char_row <= pixel_y_d1 - PARAM_Y_START - 12'd120;",
         "char_row <= (pixel_y_d1 - PARAM_Y_START - 12'd100) << 1;"),
        
        # Y轴标度char_row
        ("y_axis_char_row <= pixel_y - 12'd50;",
         "y_axis_char_row <= (pixel_y - 12'd50) << 1;"),
        ("y_axis_char_row <= pixel_y - 12'd175;",
         "y_axis_char_row <= (pixel_y - 12'd175) << 1;"),
        ("y_axis_char_row <= pixel_y - 12'd300;",
         "y_axis_char_row <= (pixel_y - 12'd300) << 1;"),
        ("y_axis_char_row <= pixel_y - 12'd425;",
         "y_axis_char_row <= (pixel_y - 12'd425) << 1;"),
        ("y_axis_char_row <= pixel_y - 12'd516;",
         "y_axis_char_row <= (pixel_y - 12'd532) << 1;"),
    ]
    
    for old_str, new_str in char_row_replacements:
        count = modified.count(old_str)
        if count > 0:
            modified = modified.replace(old_str, new_str)
            print(f"✓ char_row: '{old_str[:40]}...' ({count}次)")
    
    # 第1行特殊处理（需要添加左移）
    modified = modified.replace(
        "char_row <= pixel_y_d1 - PARAM_Y_START;",
        "char_row <= (pixel_y_d1 - PARAM_Y_START) << 1;",
        1  # 只替换第一次出现
    )
    print("✓ char_row: 第1行添加<<1")
    
    # X轴标度char_row（在else if分支中）
    modified = modified.replace(
        "char_row <= pixel_y_d1 - SPECTRUM_Y_END;",
        "char_row <= (pixel_y_d1 - SPECTRUM_Y_END) << 1;"
    )
    print("✓ char_row: X轴标度添加<<1")
    
    # 刻度线位置更新：516 → 532
    modified = modified.replace(
        "pixel_y_d3 == 425 || pixel_y_d3 == 516",
        "pixel_y_d3 == 425 || pixel_y_d3 == 532"
    )
    print("✓ 刻度线: 516→532")
    
    # 写回文件
    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(modified)
    
    print(f"\n✅ 跳行显示修改完成！")
    print("字符视觉高度：16px (每2行取1行)")
    print("参数区布局：Y=580-695 (116px)")
    print("Y轴标度：50-65, 175-190, 300-315, 425-440, 532-547")
    print("X轴标度：550-565")

if __name__ == "__main__":
    fix_to_skip_line_display()
