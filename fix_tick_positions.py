#!/usr/bin/env python3
"""
修正Y轴刻度线位置
"""

def fix_tick_positions():
    filepath = r"e:\Odyssey_proj\source\source\hdmi_display_ctrl.v"
    
    # 读取文件
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # 替换Y轴刻度线位置
    replacements = [
        # 注释中的位置说明
        ("位置：Y=75 (100%), Y=262 (75%), Y=450 (50%), Y=637 (25%), Y=825 (0%)",
         "位置：Y=50 (100%), Y=175 (75%), Y=300 (50%), Y=425 (25%), Y=530 (0%) - 720p"),
        
        # 实际的判断条件
        ("pixel_y_d3 == 75 || pixel_y_d3 == 262 || pixel_y_d3 == 450",
         "pixel_y_d3 == 50 || pixel_y_d3 == 175 || pixel_y_d3 == 300"),
        
        ("pixel_y_d3 == 637 || pixel_y_d3 == 825",
         "pixel_y_d3 == 425 || pixel_y_d3 == 530"),
    ]
    
    # 执行替换
    modified = content
    for old_str, new_str in replacements:
        count = modified.count(old_str)
        if count > 0:
            modified = modified.replace(old_str, new_str)
            print(f"✓ 替换 '{old_str[:50]}...' ({count}次)")
        else:
            print(f"⚠ 未找到: '{old_str[:50]}...'")
    
    # 写回文件
    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(modified)
    
    print(f"\n✅ Y轴刻度线位置修正完成！")
    print("新刻度位置：50, 175, 300, 425, 530")

if __name__ == "__main__":
    fix_tick_positions()
