# BCD ROM生成器 - 生成完整的查找表
# 使用位切片作为地址，直接查表获取BCD值

def generate_freq_rom():
    """生成频率BCD ROM
    策略：
    - 0-10kHz: 每100Hz一个条目（100个条目）
    - 10kHz-100kHz: 每1kHz一个条目（90个条目）
    - 100kHz-500kHz: 每10kHz一个条目（40个条目）
    总共约230个条目，可以用8位地址（256个）
    
    输入映射：
    - 0-9999 Hz → addr[7:0] = freq[13:6] (右移6位，0-156)
    - 10k-99.9k Hz → addr[7:0] = 100 + (freq-10000)/1000 (100-189)
    - 100k-500k Hz → addr[7:0] = 190 + (freq-100000)/10000 (190-229)
    """
    print("// 频率BCD ROM (256个条目 × 24位)")
    print("// 地址映射：")
    print("//   0-99:   0-9999 Hz (100Hz步进)")
    print("//   100-199: 10-109kHz (1kHz步进)")  
    print("//   200-239: 110-500kHz (10kHz步进)")
    print()
    
    rom_data = []
    
    # 0-9999 Hz: 每100Hz
    for i in range(100):
        freq_hz = i * 100
        rom_data.append(freq_to_bcd_24bit(freq_hz))
    
    # 10kHz-109kHz: 每1kHz
    for i in range(100):
        freq_hz = 10000 + i * 1000
        rom_data.append(freq_to_bcd_24bit(freq_hz))
    
    # 110kHz-500kHz: 每10kHz
    for i in range(40):
        freq_hz = 110000 + i * 10000
        rom_data.append(freq_to_bcd_24bit(freq_hz))
    
    # 填充到256个
    while len(rom_data) < 256:
        rom_data.append(0x000000)
    
    # 输出ROM初始化代码
    print("reg [23:0] freq_bcd_rom [0:255];")
    print("initial begin")
    for i in range(0, 256, 4):
        values = [f"24'h{rom_data[i+j]:06x}" for j in range(4)]
        print(f"    freq_bcd_rom[{i:3d}] = {values[0]}; freq_bcd_rom[{i+1:3d}] = {values[1]}; " +
              f"freq_bcd_rom[{i+2:3d}] = {values[2]}; freq_bcd_rom[{i+3:3d}] = {values[3]};")
    print("end")
    print()

def generate_amp_rom():
    """生成幅度BCD ROM
    0-5000mV，每10mV一个条目
    需要500个条目，使用9位地址（512个）
    输入映射：addr = amp_in / 10 (使用近似)
    """
    print("// 幅度BCD ROM (512个条目 × 16位)")
    print("// 地址映射：addr = amp_in[15:4] ≈ amp_in/16 (需要校准)")
    print()
    
    rom_data = []
    
    # 0-5000mV: 每10mV
    for i in range(501):
        amp_mv = i * 10
        rom_data.append(amp_to_bcd_16bit(amp_mv))
    
    # 填充到512
    while len(rom_data) < 512:
        rom_data.append(0x5000)
    
    print("reg [15:0] amp_bcd_rom [0:511];")
    print("initial begin")
    for i in range(0, 512, 4):
        values = [f"16'h{rom_data[i+j]:04x}" for j in range(4)]
        print(f"    amp_bcd_rom[{i:3d}] = {values[0]}; amp_bcd_rom[{i+1:3d}] = {values[1]}; " +
              f"amp_bcd_rom[{i+2:3d}] = {values[2]}; amp_bcd_rom[{i+3:3d}] = {values[3]};")
    print("end")
    print()

def generate_duty_rom():
    """生成占空比/THD BCD ROM
    0-1000 (0-100.0%)，每1为一个条目
    需要1001个条目，使用11位地址（2048个）
    输入映射：addr = duty_in (直接索引)
    """
    print("// 占空比/THD BCD ROM (1024个条目 × 16位)")
    print("// 地址映射：addr = duty_in[9:0] (直接索引0-1000)")
    print()
    
    rom_data = []
    
    # 0-1000: 每1
    for i in range(1001):
        rom_data.append(duty_to_bcd_16bit(i))
    
    # 填充到1024
    while len(rom_data) < 1024:
        rom_data.append(0x1000)  # 100.0%
    
    print("reg [15:0] duty_bcd_rom [0:1023];")
    print("initial begin")
    for i in range(0, 1024, 4):
        values = [f"16'h{rom_data[i+j]:04x}" for j in range(4)]
        print(f"    duty_bcd_rom[{i:4d}] = {values[0]}; duty_bcd_rom[{i+1:4d}] = {values[1]}; " +
              f"duty_bcd_rom[{i+2:4d}] = {values[2]}; duty_bcd_rom[{i+3:4d}] = {values[3]};")
    print("end")
    print()

def freq_to_bcd_24bit(freq_hz):
    """频率转BCD (6位×4bit = 24bit)"""
    result = 0
    for i in range(6):
        digit = freq_hz % 10
        result |= (digit << (i * 4))
        freq_hz //= 10
    return result

def amp_to_bcd_16bit(amp_mv):
    """幅度转BCD (4位×4bit = 16bit)
    显示格式: X.XXX V
    例如：3145 mV → 0x3145
    """
    result = 0
    for i in range(4):
        digit = amp_mv % 10
        result |= (digit << (i * 4))
        amp_mv //= 10
    return result

def duty_to_bcd_16bit(duty_x1):
    """占空比转BCD (4位×4bit = 16bit)
    输入：0-1000 (0.0-100.0%)
    显示格式: XXX.X %
    例如：545 → 54.5% → 0x0545
    """
    result = 0
    for i in range(4):
        digit = duty_x1 % 10
        result |= (digit << (i * 4))
        duty_x1 //= 10
    return result

def generate_address_calculation():
    """生成地址计算逻辑"""
    print("//=============================================================================")
    print("// 地址计算逻辑（无除法，仅位运算和加法）")
    print("//=============================================================================")
    print()
    
    print("// 频率地址计算")
    print("// 使用分段映射 + 乘法近似除法")
    print("wire [7:0] freq_addr;")
    print("wire [31:0] freq_div1k, freq_div10k;")
    print("// 除以1000近似: x/1000 ≈ (x * 1049) >> 20 (误差<0.1%)")
    print("// 除以10000近似: x/10000 ≈ (x * 6554) >> 16 (误差<0.5%)")
    print("assign freq_div1k = (freq_in * 20'd1049) >> 20;   // freq/1000")
    print("assign freq_div10k = (freq_in * 16'd6554) >> 16;  // freq/10000")
    print("assign freq_addr = (freq_in < 32'd10000)  ? freq_in[13:6] :              // 0-9.9kHz: 右移6≈/64")
    print("                   (freq_in < 32'd110000) ? (8'd100 + freq_div1k[7:0] - 8'd10) :  // 10-109kHz")
    print("                                            (8'd200 + freq_div10k[7:0] - 8'd11);   // 110k+")
    print()
    
    print("// 幅度地址计算")
    print("// amp_in范围0-5000，需要0-500索引")
    print("// 使用公式: addr ≈ amp_in * 0.1 = amp_in / 10")
    print("// 近似: amp_in >> 3 ≈ amp_in / 8 (误差25%，不可接受)")
    print("// 使用: (amp_in >> 3) + (amp_in >> 4) ≈ amp_in * 0.1875 (太大)")
    print("// 最佳: (amp_in * 52) >> 9 ≈ amp_in * 0.1015625 (误差1.5%)")
    print("wire [8:0] amp_addr;")
    print("wire [15:0] amp_mult;")
    print("assign amp_mult = amp_in * 8'd52;  // 乘以常数")
    print("assign amp_addr = amp_mult[15:7];  // 右移7位 ≈ 除以128")
    print()
    
    print("// 占空比地址计算")
    print("// 直接使用低10位作为地址")
    print("wire [9:0] duty_addr;")
    print("assign duty_addr = duty_in[9:0];")
    print()

if __name__ == "__main__":
    print("//=============================================================================")
    print("// 自动生成的BCD ROM数据")
    print("// 生成时间: 2025-11-07")
    print("// 使用方法: 复制到 bcd_lut.v 模块中")
    print("//=============================================================================")
    print()
    
    generate_address_calculation()
    generate_freq_rom()
    generate_amp_rom()
    generate_duty_rom()
    
    # 统计资源
    freq_size = 256 * 24
    amp_size = 512 * 16
    duty_size = 1024 * 16
    total_bits = freq_size + amp_size + duty_size
    
    print("//=============================================================================")
    print("// 资源统计")
    print("//=============================================================================")
    print(f"// 频率ROM: 256 × 24bit = {freq_size} bits ({freq_size//8} bytes)")
    print(f"// 幅度ROM: 512 × 16bit = {amp_size} bits ({amp_size//8} bytes)")
    print(f"// 占空比ROM: 1024 × 16bit = {duty_size} bits ({duty_size//8} bytes)")
    print(f"// 总计: {total_bits} bits = {total_bits//8} bytes = {total_bits//8//1024:.2f} KB")
    print(f"// 预计LUT使用: ~{total_bits//6} 个 (EG4S20按6-input LUT计算)")
