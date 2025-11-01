#!/usr/bin/env python3
"""
修正字符高度：从21px改为16px（字符ROM实际高度）
24px间距 = 16px字符 + 8px行间距
"""

def fix_char_height():
    filepath = r"e:\Odyssey_proj\source\source\hdmi_display_ctrl.v"
    
    # 读取文件
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # 定义替换映射（结束位置修正为起始+16）
    replacements = [
        # 第1行：0-20 → 0-15
        ("PARAM_Y_START && pixel_y_d1 < PARAM_Y_START + 21",
         "PARAM_Y_START && pixel_y_d1 < PARAM_Y_START + 16"),
        
        # 第2行：24-44 → 24-39
        ("PARAM_Y_START + 24 && pixel_y_d1 < PARAM_Y_START + 45",
         "PARAM_Y_START + 24 && pixel_y_d1 < PARAM_Y_START + 40"),
        
        # 第3行：48-68 → 48-63
        ("PARAM_Y_START + 48 && pixel_y_d1 < PARAM_Y_START + 69",
         "PARAM_Y_START + 48 && pixel_y_d1 < PARAM_Y_START + 64"),
        
        # 第4行：72-92 → 72-87
        ("PARAM_Y_START + 72 && pixel_y_d1 < PARAM_Y_START + 93",
         "PARAM_Y_START + 72 && pixel_y_d1 < PARAM_Y_START + 88"),
        
        # 第5行：96-116 → 96-111
        ("PARAM_Y_START + 96 && pixel_y_d1 < PARAM_Y_START + 117",
         "PARAM_Y_START + 96 && pixel_y_d1 < PARAM_Y_START + 112"),
        
        # 第6行：120-140 → 120-135
        ("PARAM_Y_START + 120 && pixel_y_d1 < PARAM_Y_START + 141",
         "PARAM_Y_START + 120 && pixel_y_d1 < PARAM_Y_START + 136"),
    ]
    
    # 执行替换
    modified = content
    for old_str, new_str in replacements:
        count = modified.count(old_str)
        modified = modified.replace(old_str, new_str)
        print(f"✓ 替换 '{old_str}' → '{new_str}' ({count}次)")
    
    # 写回文件
    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(modified)
    
    print(f"\n✅ 字符高度修正完成！")
    print("新布局：24px间距 = 16px字符高度 + 8px行间距")
    print("第1行: Y=0-15   (16px)")
    print("第2行: Y=24-39  (16px)")
    print("第3行: Y=48-63  (16px)")
    print("第4行: Y=72-87  (16px)")
    print("第5行: Y=96-111 (16px)")
    print("第6行: Y=120-135 (16px)")

if __name__ == "__main__":
    fix_char_height()
