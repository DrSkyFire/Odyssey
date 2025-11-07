# BCD查找表生成脚本
# 为自动测试参数生成预计算的BCD数值
# 解决HDMI域除法运算导致的时序违例

def freq_to_bcd(freq_hz):
    """将频率(Hz)转换为6位BCD"""
    digits = []
    for i in range(6):
        digits.append(freq_hz % 10)
        freq_hz //= 10
    return digits[::-1]  # 反转为高位在前

def amp_to_bcd(amp_mv):
    """将幅度(mV)转换为4位BCD (显示为X.XXXv)"""
    digits = []
    for i in range(4):
        digits.append(amp_mv % 10)
        amp_mv //= 10
    return digits[::-1]

def duty_to_bcd(duty_x10):
    """将占空比(0-1000 = 0-100.0%)转换为4位BCD"""
    digits = []
    for i in range(4):
        digits.append(duty_x10 % 10)
        duty_x10 //= 10
    return digits[::-1]

def generate_freq_lut():
    """生成频率BCD查找表（100Hz步进，0-500kHz）"""
    print("//=============================================================================")
    print("// 频率BCD查找表 (100Hz步进，覆盖0-500kHz)")
    print("// 输入: freq_in[31:0] (Hz)")
    print("// 输出: freq_bcd[23:0] = {d5[3:0], d4[3:0], d3[3:0], d2[3:0], d1[3:0], d0[3:0]}")
    print("//=============================================================================")
    print("always @(*) begin")
    print("    case (freq_in[31:0])")
    
    # 生成关键点（每100Hz一个条目，但只生成常用范围）
    # 0-1kHz: 每100Hz
    for freq in range(0, 1100, 100):
        bcd = freq_to_bcd(freq)
        bcd_hex = ''.join([f'{d:x}' for d in bcd])
        print(f"        32'd{freq}: freq_bcd = 24'h{bcd_hex};  // {freq} Hz")
    
    # 1kHz-10kHz: 每1kHz
    for freq in range(1000, 11000, 1000):
        if freq % 100 != 0:  # 跳过已生成的
            bcd = freq_to_bcd(freq)
            bcd_hex = ''.join([f'{d:x}' for d in bcd])
            print(f"        32'd{freq}: freq_bcd = 24'h{bcd_hex};  // {freq/1000:.1f} kHz")
    
    # 10kHz-100kHz: 每10kHz
    for freq in range(10000, 110000, 10000):
        if freq % 1000 != 0:
            bcd = freq_to_bcd(freq)
            bcd_hex = ''.join([f'{d:x}' for d in bcd])
            print(f"        32'd{freq}: freq_bcd = 24'h{bcd_hex};  // {freq/1000:.0f} kHz")
    
    # 100kHz-500kHz: 每100kHz
    for freq in range(100000, 510000, 100000):
        if freq % 10000 != 0:
            bcd = freq_to_bcd(freq)
            bcd_hex = ''.join([f'{d:x}' for d in bcd])
            print(f"        32'd{freq}: freq_bcd = 24'h{bcd_hex};  // {freq/1000:.0f} kHz")
    
    print("        default: freq_bcd = 24'h000000;  // 未定义频率，显示0")
    print("    endcase")
    print("end\n")

def generate_amp_lut():
    """生成幅度BCD查找表（10mV步进，0-5V）"""
    print("//=============================================================================")
    print("// 幅度BCD查找表 (10mV步进，覆盖0-5000mV)")
    print("// 输入: amp_in[15:0] (mV)")
    print("// 输出: amp_bcd[15:0] = {d3[3:0], d2[3:0], d1[3:0], d0[3:0]}")
    print("// 显示格式: d3.d2d1d0 V (例如 3.145V)")
    print("//=============================================================================")
    print("always @(*) begin")
    print("    case (amp_in[15:0])")
    
    # 每100mV生成一个条目（精度足够）
    for amp_mv in range(0, 5100, 100):
        bcd = amp_to_bcd(amp_mv)
        bcd_hex = ''.join([f'{d:x}' for d in bcd])
        print(f"        16'd{amp_mv}: amp_bcd = 16'h{bcd_hex};  // {amp_mv/1000:.1f}V")
    
    print("        default: amp_bcd = 16'h0000;")
    print("    endcase")
    print("end\n")

def generate_duty_lut():
    """生成占空比/THD BCD查找表（0.1%步进，0-100%）"""
    print("//=============================================================================")
    print("// 占空比/THD BCD查找表 (0.1%步进，覆盖0-100.0%)")
    print("// 输入: duty_in[15:0] (0-1000 = 0-100.0%)")
    print("// 输出: duty_bcd[15:0] = {d3[3:0], d2[3:0], d1[3:0], d0[3:0]}")
    print("// 显示格式: d2d1.d0 % (例如 50.5%)")
    print("//=============================================================================")
    print("always @(*) begin")
    print("    case (duty_in[15:0])")
    
    # 每10生成一个条目（对应1%）
    for duty_x10 in range(0, 1010, 10):
        bcd = duty_to_bcd(duty_x10)
        bcd_hex = ''.join([f'{d:x}' for d in bcd])
        print(f"        16'd{duty_x10}: duty_bcd = 16'h{bcd_hex};  // {duty_x10/10:.1f}%")
    
    print("        default: duty_bcd = 16'h0000;")
    print("    endcase")
    print("end\n")

if __name__ == "__main__":
    print("// 生成的BCD查找表代码")
    print("// 粘贴到bcd_lut.v模块中\n")
    
    generate_freq_lut()
    generate_amp_lut()
    generate_duty_lut()
    
    # 统计资源使用
    freq_entries = 10 + 10 + 10 + 5  # 粗略估计
    amp_entries = 51
    duty_entries = 101
    
    print(f"// 资源估算:")
    print(f"// 频率LUT: ~{freq_entries}条 × 24位 = {freq_entries * 24} bits")
    print(f"// 幅度LUT: {amp_entries}条 × 16位 = {amp_entries * 16} bits")
    print(f"// 占空比LUT: {duty_entries}条 × 16位 = {duty_entries * 16} bits")
    print(f"// 总计: ~{freq_entries*24 + amp_entries*16 + duty_entries*16} bits = {(freq_entries*24 + amp_entries*16 + duty_entries*16)//8} bytes")
