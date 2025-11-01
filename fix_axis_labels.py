#!/usr/bin/env python3
"""
修正720p下的坐标轴字符映射位置
1080p → 720p 缩放比例：0.67

Y轴标度（左侧，显示百分比）：
- 频谱高度：500px (50-550)
- 原1080p: 750px (75-825)
- 100%位置：75  → 50 (顶部)
- 75%位置：262 → 175 (1/4处: 50+125)
- 50%位置：450 → 300 (中点: 50+250)
- 25%位置：637 → 425 (3/4处: 50+375)
- 0%位置：793  → 530 (底部: 50+480，留20px余量)

字符高度：32px → 16px (使用16x16 ROM的前16行)

X轴标度（底部，显示频率/时间）：
- 位置保持不变（已按pixel_x计算）
- 但Y坐标需要调整：SPECTRUM_Y_END (550) 后面
- 字符行范围：550-566 (16px高度)
"""

def calculate_720p_positions():
    # Y轴标度位置计算
    spectrum_start = 50
    spectrum_height = 500
    
    # 关键刻度点的Y位置
    y_100 = spectrum_start  # 100%: 顶部
    y_75 = spectrum_start + int(spectrum_height * 0.25)  # 75%: 1/4处
    y_50 = spectrum_start + int(spectrum_height * 0.50)  # 50%: 中点
    y_25 = spectrum_start + int(spectrum_height * 0.75)  # 25%: 3/4处
    y_0 = spectrum_start + spectrum_height - 20  # 0%: 底部，留余量
    
    print("=== 720p Y轴标度位置修正 ===")
    print(f"频谱区域: Y={spectrum_start}-{spectrum_start+spectrum_height}")
    print(f"100%: Y={y_100}-{y_100+15} (字符16px高)")
    print(f" 75%: Y={y_75}-{y_75+15}")
    print(f" 50%: Y={y_50}-{y_50+15}")
    print(f" 25%: Y={y_25}-{y_25+15}")
    print(f"  0%: Y={y_0}-{y_0+15}")
    
    # X轴标度位置
    x_axis_y_start = 550
    print(f"\n=== X轴标度位置 ===")
    print(f"Y范围: {x_axis_y_start}-{x_axis_y_start+15} (16px高)")
    
    return {
        'y_100': (y_100, y_100+16),
        'y_75': (y_75, y_75+16),
        'y_50': (y_50, y_50+16),
        'y_25': (y_25, y_25+16),
        'y_0': (y_0, y_0+16),
        'x_axis_y': (x_axis_y_start, x_axis_y_start+16)
    }

def fix_axis_labels():
    filepath = r"e:\Odyssey_proj\source\source\hdmi_display_ctrl.v"
    
    positions = calculate_720p_positions()
    
    # 读取文件
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # Y轴标度替换（字符高度32→16）
    replacements = [
        # 100%: 75-107 → 50-66
        ("pixel_y >= 75 && pixel_y < 107", 
         f"pixel_y >= {positions['y_100'][0]} && pixel_y < {positions['y_100'][1]}"),
        ("pixel_y - 12'd75", f"pixel_y - 12'd{positions['y_100'][0]}"),
        
        # 75%: 262-294 → 175-191
        ("pixel_y >= 262 && pixel_y < 294",
         f"pixel_y >= {positions['y_75'][0]} && pixel_y < {positions['y_75'][1]}"),
        ("pixel_y - 12'd262", f"pixel_y - 12'd{positions['y_75'][0]}"),
        
        # 50%: 450-482 → 300-316
        ("pixel_y >= 450 && pixel_y < 482",
         f"pixel_y >= {positions['y_50'][0]} && pixel_y < {positions['y_50'][1]}"),
        ("pixel_y - 12'd450", f"pixel_y - 12'd{positions['y_50'][0]}"),
        
        # 25%: 637-669 → 425-441
        ("pixel_y >= 637 && pixel_y < 669",
         f"pixel_y >= {positions['y_25'][0]} && pixel_y < {positions['y_25'][1]}"),
        ("pixel_y - 12'd637", f"pixel_y - 12'd{positions['y_25'][0]}"),
        
        # 0%: 793-825 → 530-546
        ("pixel_y >= 793 && pixel_y < 825",
         f"pixel_y >= {positions['y_0'][0]} && pixel_y < {positions['y_0'][1]}"),
        ("pixel_y - 12'd793", f"pixel_y - 12'd{positions['y_0'][0]}"),
        
        # X轴标度：SPECTRUM_Y_END后面，字符32px→16px
        ("pixel_y_d1 >= SPECTRUM_Y_END && pixel_y_d1 < SPECTRUM_Y_END + 32",
         "pixel_y_d1 >= SPECTRUM_Y_END && pixel_y_d1 < SPECTRUM_Y_END + 16"),
    ]
    
    # 执行替换
    modified = content
    for old_str, new_str in replacements:
        count = modified.count(old_str)
        if count > 0:
            modified = modified.replace(old_str, new_str)
            print(f"✓ 替换 '{old_str}' → '{new_str}' ({count}次)")
        else:
            print(f"⚠ 未找到: '{old_str}'")
    
    # 写回文件
    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(modified)
    
    print(f"\n✅ 坐标轴字符映射修正完成！")

if __name__ == "__main__":
    fix_axis_labels()
