#!/usr/bin/env python3
"""
修正char_row计算中的残留旧值
"""

def fix_char_row_values():
    filepath = r"e:\Odyssey_proj\source\source\hdmi_display_ctrl.v"
    
    # 读取文件
    with open(filepath, 'r', encoding='utf-8') as f:
        lines = f.readlines()
    
    # 定义需要修正的行号和替换
    # Line 1399: char_row <= pixel_y_d1 - PARAM_Y_START - 12'd70; → 12'd48
    # Line 1544: char_row <= pixel_y_d1 - PARAM_Y_START - 12'd105; → 12'd72
    # Line 1679: char_row <= pixel_y_d1 - PARAM_Y_START - 12'd140; → 12'd96
    # Line 1860: char_row <= pixel_y_d1 - PARAM_Y_START - 12'd175; → 12'd120
    
    replacements = {
        "PARAM_Y_START + 48 && pixel_y_d1 < PARAM_Y_START + 69": "12'd70→12'd48",
        "PARAM_Y_START + 72 && pixel_y_d1 < PARAM_Y_START + 93": "12'd105→12'd72",
        "PARAM_Y_START + 96 && pixel_y_d1 < PARAM_Y_START + 117": "12'd140→12'd96",
        "PARAM_Y_START + 120 && pixel_y_d1 < PARAM_Y_START + 141": "12'd175→12'd120",
    }
    
    i = 0
    while i < len(lines):
        line = lines[i]
        
        # 找到if条件行
        for pattern, fix_desc in replacements.items():
            if pattern in line:
                # 下一行应该是char_row赋值
                if i + 1 < len(lines) and 'char_row' in lines[i+1]:
                    old_val, new_val = fix_desc.split('→')
                    if old_val in lines[i+1]:
                        lines[i+1] = lines[i+1].replace(old_val, new_val)
                        print(f"✓ Line {i+2}: {old_val} → {new_val}")
                break
        i += 1
    
    # 写回文件
    with open(filepath, 'w', encoding='utf-8') as f:
        f.writelines(lines)
    
    print(f"\n✅ char_row值修正完成！")

if __name__ == "__main__":
    fix_char_row_values()
