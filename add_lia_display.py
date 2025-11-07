# -*- coding: utf-8 -*-
"""
锁相放大HDMI显示功能添加脚本
自动修改 hdmi_display_ctrl.v 文件
"""

import re
import shutil
from datetime import datetime

def backup_file(filepath):
    """备份原文件"""
    backup_path = filepath + f".bak_{datetime.now().strftime('%Y%m%d_%H%M%S')}"
    shutil.copy2(filepath, backup_path)
    print(f"✓ 已备份原文件到: {backup_path}")
    return backup_path

def add_lia_ports(content):
    """添加锁相放大输入端口"""
    # 查找 thd_max_d3 所在行
    pattern = r'(input\s+wire\s+\[3:0\]\s+thd_max_d0,.*?thd_max_d3,\s*\n)'
    replacement = r'\1' + '''    
    // ✨ 锁相放大显示输入
    input  wire         weak_sig_enable,        // 微弱信号模式使能
    input  wire [31:0]  lia_ref_freq,           // 参考频率 (Hz)
    input  wire [1:0]   lia_ref_mode,           // 参考模式 (0=DDS, 1=CH2, 2=外部)
    input  wire signed [23:0] ch1_lia_magnitude,// CH1幅度 (24-bit)
    input  wire [15:0]  ch1_lia_phase,          // CH1相位 (0-65535 -> 0-360°)
    input  wire         ch1_lia_locked,         // CH1锁定状态
    input  wire [15:0]  lia_snr_estimate,       // SNR估计 (dB, 8.8定点)
    
'''
    content = re.sub(pattern, replacement, content, flags=re.DOTALL)
    print("✓ 已添加锁相放大输入端口")
    return content

def add_lia_parameters(content):
    """添加锁相放大显示区域参数"""
    pattern = r'(localparam\s+AUTO_CHAR_WIDTH\s*=\s*16;.*?\n)'
    replacement = r'\1' + '''
//=============================================================================
// 锁相放大显示区域参数 (屏幕左上角)
//=============================================================================
localparam LIA_X_START = 20;            // 锁相放大区域X起始
localparam LIA_Y_START = 60;            // 锁相放大区域Y起始
localparam LIA_WIDTH   = 360;           // 锁相放大区域宽度
localparam LIA_HEIGHT  = 200;           // 锁相放大区域高度
localparam LIA_LINE_HEIGHT = 28;        // 行高
localparam LIA_CHAR_WIDTH  = 16;        // 字符宽度

'''
    content = re.sub(pattern, replacement, content)
    print("✓ 已添加锁相放大显示区域参数")
    return content

def add_lia_signals(content):
    """添加锁相放大信号定义"""
    pattern = r'(reg\s+auto_test_char_valid;.*?\n)'
    replacement = r'\1' + '''
// 锁相放大显示相关信号
reg         in_lia_area;            // 在锁相放大显示区域内
reg         in_lia_area_d1, in_lia_area_d2, in_lia_area_d3;  // 延迟链
reg [4:0]   lia_char_row;           // 锁相放大字符行号
reg [11:0]  lia_char_col;           // 锁相放大字符列号

// 锁相放大显示数据（预处理）
reg [31:0]  lia_freq_display;       // 参考频率显示值
reg [3:0]   lia_freq_d0, lia_freq_d1, lia_freq_d2, lia_freq_d3, lia_freq_d4, lia_freq_d5;
reg [3:0]   lia_mag_d0, lia_mag_d1, lia_mag_d2, lia_mag_d3;  // 幅度（mV）
reg [3:0]   lia_phase_d0, lia_phase_d1, lia_phase_d2;  // 相位（度）
reg [3:0]   lia_snr_d0, lia_snr_d1, lia_snr_d2;  // SNR（dB）
reg         lia_phase_sign;         // 相位符号（0=正，1=负）

'''
    content = re.sub(pattern, replacement, content)
    print("✓ 已添加锁相放大信号定义")
    return content

def main():
    filepath = "e:/Odyssey_proj/source/source/hdmi_display_ctrl.v"
    
    print("=" * 60)
    print("锁相放大HDMI显示功能自动添加脚本")
    print("=" * 60)
    
    try:
        # 读取原文件
        with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
        print(f"✓ 已读取文件: {filepath}")
        
        # 备份
        backup_file(filepath)
        
        # 逐步添加修改
        content = add_lia_ports(content)
        content = add_lia_parameters(content)
        content = add_lia_signals(content)
        
        # 写入修改后的文件
        with open(filepath, 'w', encoding='utf-8', errors='ignore') as f:
            f.write(content)
        print(f"✓ 已保存修改后的文件")
        
        print("\n" + "=" * 60)
        print("✓ 修改完成！")
        print("=" * 60)
        print("\n请参考《锁相放大HDMI显示补丁.md》完成剩余修改：")
        print("  - 复位逻辑")
        print("  - 延迟链更新")
        print("  - 数据预处理")
        print("  - 字符显示逻辑")
        print("  - 颜色合成")
        print("  - 顶层模块连接")
        
    except Exception as e:
        print(f"✗ 错误: {e}")
        return 1
    
    return 0

if __name__ == "__main__":
    exit(main())
