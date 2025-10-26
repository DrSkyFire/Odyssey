#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
CORDIC结果解析工具
用于解析FPGA通过UART发送的CORDIC计算结果

使用方法:
1. 连接FPGA的UART到电脑（COM端口）
2. 运行脚本: python cordic_uart_parser.py COM3
3. 实时查看解析后的CORDIC计算结果

作者: AI Assistant
日期: 2025-10-26
"""

import serial
import sys
import re
import time

def parse_hex_to_fixed_point(hex_str, sign_char):
    """
    将十六进制字符串和符号转换为定点数
    
    参数:
        hex_str: 8位十六进制字符串 (例如 "00009C40")
        sign_char: 符号字符 ('+' 或 '-')
    
    返回:
        浮点数值
    """
    try:
        # 去除可能的空格
        hex_str = hex_str.strip()
        # 转换为32位整数
        int_value = int(hex_str, 16)
        
        # 应用符号
        if sign_char == '-':
            # 处理负数（二进制补码）
            if int_value > 0x7FFFFFFF:
                int_value = int_value - 0x100000000
        
        # 转换为定点数（16位小数）
        float_value = int_value / 65536.0
        
        return float_value
    except ValueError:
        return None

def parse_cordic_line(line):
    """
    解析包含CORDIC信息的状态行
    
    参数:
        line: UART接收到的状态行字符串
    
    返回:
        字典，包含解析后的CORDIC信息
    """
    result = {
        'mode': None,
        'mode_name': None,
        'result1': None,
        'result2': None,
        'raw_line': line
    }
    
    # 使用正则表达式匹配CORDIC信息
    # 格式: CORDIC:M R1:±XXXXXXXX R2:±XXXXXXXX
    cordic_pattern = r'CORDIC:([DSHELA])\s+R1:([+-])([0-9A-Fa-f]{8})\s+R2:([+-])([0-9A-Fa-f]{8})'
    match = re.search(cordic_pattern, line)
    
    if match:
        mode_char = match.group(1)
        r1_sign = match.group(2)
        r1_hex = match.group(3)
        r2_sign = match.group(4)
        r2_hex = match.group(5)
        
        # 解析模式
        mode_map = {
            'D': ('Disabled', 0),
            'S': ('Sin/Cos', 1),
            'H': ('Sinh/Cosh', 2),
            'E': ('Exp', 3),
            'L': ('Ln', 4),
            'A': ('Arctanh', 5)
        }
        
        if mode_char in mode_map:
            result['mode_name'], result['mode'] = mode_map[mode_char]
        
        # 解析结果值
        result['result1'] = parse_hex_to_fixed_point(r1_hex, r1_sign)
        result['result2'] = parse_hex_to_fixed_point(r2_hex, r2_sign)
    
    return result

def format_cordic_output(data):
    """
    格式化CORDIC数据输出
    
    参数:
        data: 解析后的CORDIC数据字典
    
    返回:
        格式化的字符串
    """
    if data['mode'] is None:
        return "无CORDIC数据"
    
    output = f"\n{'='*60}\n"
    output += f"CORDIC模式: {data['mode_name']} (模式{data['mode']})\n"
    output += f"{'-'*60}\n"
    
    if data['mode'] == 0:  # Disabled
        output += "CORDIC功能已禁用\n"
    elif data['mode'] == 1:  # Sin/Cos
        output += f"sin(θ) = {data['result1']:+.6f}\n"
        output += f"cos(θ) = {data['result2']:+.6f}\n"
        # 验证：sin²+cos² 应该约等于1
        if data['result1'] is not None and data['result2'] is not None:
            magnitude = data['result1']**2 + data['result2']**2
            output += f"验证: sin²+cos² = {magnitude:.6f} (应≈1.0)\n"
    elif data['mode'] == 2:  # Sinh/Cosh
        output += f"sinh(x) = {data['result1']:+.6f}\n"
        output += f"cosh(x) = {data['result2']:+.6f}\n"
        # 验证：cosh²-sinh² 应该约等于1
        if data['result1'] is not None and data['result2'] is not None:
            identity = data['result2']**2 - data['result1']**2
            output += f"验证: cosh²-sinh² = {identity:.6f} (应≈1.0)\n"
    elif data['mode'] == 3:  # Exp
        output += f"e^x = {data['result1']:+.6f}\n"
        if data['result1'] is not None and data['result1'] > 0:
            output += f"ln(e^x) = {data['result1']:.6f} 的自然对数约为 {abs(data['result1']):.6f}\n"
    elif data['mode'] == 4:  # Ln
        output += f"ln(x) = {data['result1']:+.6f}\n"
        if data['result1'] is not None:
            output += f"e^(ln(x)) 应约等于原始输入值\n"
    elif data['mode'] == 5:  # Arctanh
        output += f"arctanh(x) = {data['result1']:+.6f}\n"
    
    output += f"{'='*60}\n"
    return output

def main():
    """主函数"""
    # 检查命令行参数
    if len(sys.argv) < 2:
        print("使用方法: python cordic_uart_parser.py <COM端口>")
        print("例如: python cordic_uart_parser.py COM3")
        sys.exit(1)
    
    port = sys.argv[1]
    baudrate = 115200
    
    print(f"正在连接到 {port}，波特率 {baudrate}...")
    
    try:
        # 打开串口
        ser = serial.Serial(
            port=port,
            baudrate=baudrate,
            bytesize=serial.EIGHTBITS,
            parity=serial.PARITY_NONE,
            stopbits=serial.STOPBITS_ONE,
            timeout=1
        )
        
        print(f"成功连接到 {port}")
        print("等待CORDIC数据...\n")
        
        buffer = ""
        
        while True:
            # 读取数据
            if ser.in_waiting > 0:
                data = ser.read(ser.in_waiting).decode('utf-8', errors='ignore')
                buffer += data
                
                # 按行处理
                while '\n' in buffer:
                    line, buffer = buffer.split('\n', 1)
                    line = line.strip()
                    
                    # 检查是否包含CORDIC信息
                    if 'CORDIC:' in line:
                        # 解析并显示
                        cordic_data = parse_cordic_line(line)
                        print(format_cordic_output(cordic_data))
                        print(f"原始数据: {line}\n")
            
            time.sleep(0.01)  # 小延迟，避免CPU占用过高
    
    except serial.SerialException as e:
        print(f"串口错误: {e}")
        sys.exit(1)
    except KeyboardInterrupt:
        print("\n\n程序已终止")
        if 'ser' in locals() and ser.is_open:
            ser.close()
        sys.exit(0)

if __name__ == "__main__":
    main()
