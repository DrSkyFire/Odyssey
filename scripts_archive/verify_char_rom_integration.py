#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
极简字符ROM集成验证脚本
验证所有修改是否正确集成
"""

import re
import os

def check_file_exists(filepath):
    """检查文件是否存在"""
    exists = os.path.exists(filepath)
    status = "✓" if exists else "✗"
    print(f"  {status} {os.path.basename(filepath)}")
    return exists

def check_signal_declaration(filepath, signal_name):
    """检查信号声明"""
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
        pattern = rf'\b{signal_name}\b'
        found = re.search(pattern, content) is not None
        status = "✓" if found else "✗"
        print(f"  {status} 信号 '{signal_name}'")
        return found

def check_module_instantiation(filepath, module_name):
    """检查模块例化"""
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
        pattern = rf'{module_name}\s+\w+\s*\('
        matches = re.findall(pattern, content)
        found = len(matches) > 0
        status = "✓" if found else "✗"
        print(f"  {status} 模块例化 '{module_name}' (找到{len(matches)}处)")
        return found

def main():
    print("=" * 80)
    print("极简字符ROM集成验证")
    print("=" * 80)
    
    base_path = r"e:\Odyssey_proj\source\source"
    
    # 检查1: 文件存在性
    print("\n[1] 检查新增文件...")
    char_rom_minimal = os.path.join(base_path, "char_rom_minimal.v")
    files_ok = check_file_exists(char_rom_minimal)
    
    # 检查2: hdmi_display_ctrl.v 信号声明
    print("\n[2] 检查 hdmi_display_ctrl.v 信号声明...")
    hdmi_ctrl = os.path.join(base_path, "hdmi_display_ctrl.v")
    signals_ok = True
    signals_ok &= check_signal_declaration(hdmi_ctrl, "char_index")
    signals_ok &= check_signal_declaration(hdmi_ctrl, "char_valid")
    
    # 检查3: 模块例化
    print("\n[3] 检查模块例化...")
    modules_ok = True
    modules_ok &= check_module_instantiation(hdmi_ctrl, "char_rom_minimal")
    modules_ok &= check_module_instantiation(hdmi_ctrl, "ascii_rom_16x32_full")
    
    # 检查4: ascii_rom_16x32_full.v 新增函数
    print("\n[4] 检查 ascii_rom_16x32_full.v 优化...")
    ascii_rom = os.path.join(base_path, "ascii_rom_16x32_full.v")
    with open(ascii_rom, 'r', encoding='utf-8') as f:
        content = f.read()
        has_function = "compact_to_ascii" in content
        has_actual_ascii = "actual_ascii" in content
        
        status_func = "✓" if has_function else "✗"
        status_var = "✓" if has_actual_ascii else "✗"
        print(f"  {status_func} compact_to_ascii 函数")
        print(f"  {status_var} actual_ascii 变量")
        
        ascii_ok = has_function and has_actual_ascii
    
    # 检查5: char_rom_minimal.v 查找表完整性
    print("\n[5] 检查 char_rom_minimal.v 查找表...")
    with open(char_rom_minimal, 'r', encoding='utf-8') as f:
        content = f.read()
        # 检查关键ASCII码
        critical_chars = [
            (32, ' '), (48, '0'), (57, '9'),  # 空格和数字
            (67, 'C'), (72, 'H'),             # CH标签
            (70, 'F'), (114, 'r'),            # Freq
            (107, 'k'), (122, 'z')            # kHz单位
        ]
        
        all_found = True
        for ascii_val, char in critical_chars:
            pattern = rf"8'd\s*{ascii_val}"
            found = re.search(pattern, content) is not None
            status = "✓" if found else "✗"
            print(f"  {status} ASCII {ascii_val:3d} '{char}'", end='')
            if (ascii_val - 32) % 3 == 2:
                print()
            else:
                print("  ", end='')
            all_found &= found
        print()
        
        mapping_ok = all_found
    
    # 总结
    print("=" * 80)
    print("验证结果:")
    print("=" * 80)
    
    results = [
        ("文件存在性", files_ok),
        ("信号声明", signals_ok),
        ("模块例化", modules_ok),
        ("ROM优化", ascii_ok),
        ("字符映射", mapping_ok)
    ]
    
    all_pass = all(result for _, result in results)
    
    for item, status in results:
        symbol = "✓" if status else "✗"
        print(f"  {symbol} {item}")
    
    print("=" * 80)
    if all_pass:
        print("✓ 集成验证通过！可以进行编译测试")
        print()
        print("下一步操作:")
        print("  1. 在PDS工具中重新编译项目")
        print("  2. 查看 place_route/signal_analyzer_top_timing_summary_*.txt")
        print("  3. 对比 char_code 相关路径的 WNS 改善")
        print()
        print("预期改善: WNS从 -2.360ns 改善到 -1.5ns 左右 (约40%)")
    else:
        print("✗ 集成验证失败！请检查上述错误项")
    
    print("=" * 80)

if __name__ == "__main__":
    main()
