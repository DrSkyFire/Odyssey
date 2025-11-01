#!/usr/bin/env python3
"""
批量修改hdmi_display_ctrl.v中的字符行间距
从1080p的35px间距改为720p的24px间距
"""

def fix_char_spacing():
    filepath = r"e:\Odyssey_proj\source\source\hdmi_display_ctrl.v"
    
    # 读取文件
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # 定义替换映射（旧值→新值）
    replacements = [
        # 第3行间距：70 → 48, 结束102 → 69
        ("PARAM_Y_START + 70 && pixel_y_d1 < PARAM_Y_START + 102", 
         "PARAM_Y_START + 48 && pixel_y_d1 < PARAM_Y_START + 69"),
        ("12'd70", "12'd48", 1),  # 只替换第一个出现
        
        # 第4行间距：105 → 72, 结束137 → 93
        ("PARAM_Y_START + 105 && pixel_y_d1 < PARAM_Y_START + 137",
         "PARAM_Y_START + 72 && pixel_y_d1 < PARAM_Y_START + 93"),
        ("12'd105", "12'd72", 1),
        
        # 第5行间距：140 → 96, 结束172 → 117
        ("PARAM_Y_START + 140 && pixel_y_d1 < PARAM_Y_START + 172",
         "PARAM_Y_START + 96 && pixel_y_d1 < PARAM_Y_START + 117"),
        ("12'd140", "12'd96", 1),
        
        # 第6行间距：175 → 120, 结束207 → 141
        ("PARAM_Y_START + 175 && pixel_y_d1 < PARAM_Y_START + 207",
         "PARAM_Y_START + 120 && pixel_y_d1 < PARAM_Y_START + 141"),
        ("12'd175", "12'd120", 1),
        
        # 颜色判断阈值（L2124-2133附近）
        ("PARAM_Y_START + 35)", "PARAM_Y_START + 24)"),
        ("PARAM_Y_START + 70)", "PARAM_Y_START + 48)"),
        ("PARAM_Y_START + 105)", "PARAM_Y_START + 72)"),
        ("PARAM_Y_START + 140)", "PARAM_Y_START + 96)"),
        ("PARAM_Y_START + 175)", "PARAM_Y_START + 120)"),
    ]
    
    # 执行替换
    modified = content
    for item in replacements:
        if len(item) == 3:  # 带计数的替换
            old_str, new_str, count = item
            modified = modified.replace(old_str, new_str, count)
            print(f"✓ 替换 '{old_str}' → '{new_str}' (前{count}次)")
        else:
            old_str, new_str = item
            count = modified.count(old_str)
            modified = modified.replace(old_str, new_str)
            print(f"✓ 替换 '{old_str}' → '{new_str}' ({count}次)")
    
    # 写回文件
    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(modified)
    
    print(f"\n✅ 修改完成！已更新文件: {filepath}")

if __name__ == "__main__":
    fix_char_spacing()
