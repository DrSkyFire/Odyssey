# HDMI字符显示升级指南 - ASCII标准字库方案

## 当前问题
1. 字符ROM (`char_rom_16x32.v`) 字符不全,缺少大小写字母
2. 字符编码混乱,需要手动查表
3. 每次添加新字符都要修改ROM文件
4. 代码可读性差,不易维护

## 解决方案:升级到ASCII标准字库

### 方案优势
✅ **完整字符集**: 支持ASCII 32-126 (95个字符)
✅ **标准编码**: 直接使用ASCII码,无需查表
✅ **易于维护**: 字符串可直接映射,代码更清晰
✅ **资源可控**: 16×32字体仅需 ~15KB BROM

---

## 升级步骤

### 步骤1: 生成完整ASCII字体ROM

我已经为您创建了 `ascii_rom_16x32.v`,但仅包含部分字符。完整字库有两种生成方式:

#### 方式A: 使用Python脚本自动生成 (推荐⭐)

创建文件 `generate_ascii_font.py`:

```python
#!/usr/bin/env python3
"""
ASCII 16×32字体生成器
生成Verilog格式的字符ROM
"""

import os
from PIL import Image, ImageDraw, ImageFont

# 配置
CHAR_WIDTH = 16
CHAR_HEIGHT = 32
ASCII_START = 32   # 空格
ASCII_END = 126    # ~
OUTPUT_FILE = "source/source/ascii_rom_16x32_full.v"

def generate_char_bitmap(char, font):
    """生成单个字符的位图"""
    # 创建图像
    img = Image.new('1', (CHAR_WIDTH, CHAR_HEIGHT), color=0)
    draw = ImageDraw.Draw(img)
    
    # 绘制字符(居中)
    bbox = draw.textbbox((0, 0), char, font=font)
    w, h = bbox[2] - bbox[0], bbox[3] - bbox[1]
    x = (CHAR_WIDTH - w) // 2
    y = (CHAR_HEIGHT - h) // 2 - 4
    draw.text((x, y), char, fill=1, font=font)
    
    # 转换为Verilog格式
    bitmap = []
    for y in range(CHAR_HEIGHT):
        row = 0
        for x in range(CHAR_WIDTH):
            if img.getpixel((x, y)):
                row |= (1 << (15 - x))
        bitmap.append(f"16'b{row:016b}")
    
    return bitmap

def main():
    # 加载字体(使用系统等宽字体)
    try:
        font = ImageFont.truetype("C:/Windows/Fonts/consola.ttf", 24)
    except:
        print("警告: 无法加载Consolas字体,使用默认字体")
        font = ImageFont.load_default()
    
    # 生成Verilog文件
    with open(OUTPUT_FILE, 'w', encoding='utf-8') as f:
        f.write("""//=============================================================================
// 自动生成的ASCII字符ROM - 16×32像素
// 生成时间: 自动生成
// 字符范围: ASCII 32-126 (95个字符)
//=============================================================================

module ascii_rom_16x32_full (
    input        clk,
    input  [7:0] char_code,   // ASCII码
    input  [4:0] char_row,    // 行号 0-31
    output [15:0] char_data   // 16位行数据
);

reg [15:0] rom [0:3039];  // 95字符 × 32行

initial begin
""")
        
        # 生成每个字符
        for ascii_code in range(ASCII_START, ASCII_END + 1):
            char = chr(ascii_code)
            index = ascii_code - ASCII_START
            
            f.write(f"\n    // {repr(char)} (ASCII {ascii_code}, Index {index})\n")
            
            bitmap = generate_char_bitmap(char, font)
            for row_num, row_data in enumerate(bitmap):
                addr = index * 32 + row_num
                f.write(f"    rom[{addr}] = {row_data};\n")
        
        f.write("""}

reg [15:0] char_data_reg;
always @(posedge clk) begin
    if (char_code >= 32 && char_code <= 126)
        char_data_reg <= rom[(char_code - 32) * 32 + char_row];
    else
        char_data_reg <= 16'h0000;
end

assign char_data = char_data_reg;

endmodule
""")
    
    print(f"✅ 字体ROM已生成: {OUTPUT_FILE}")
    print(f"   包含 {ASCII_END - ASCII_START + 1} 个字符")
    print(f"   ROM大小: ~{(ASCII_END - ASCII_START + 1) * 64} 字节")

if __name__ == '__main__':
    main()
```

运行: `python generate_ascii_font.py`

#### 方式B: 手动编辑字符位图

参考 `ascii_rom_16x32.v` 中已有字符的格式,手动添加缺失字符。

---

### 步骤2: 修改hdmi_display_ctrl.v

#### 2.1 更改char_code宽度

```verilog
// 原来 (6位)
reg [5:0]   char_code;

// 改为 (8位,支持ASCII 0-127)
reg [7:0]   char_code;
```

#### 2.2 更改ROM实例化

```verilog
// 原来
char_rom_16x32 u_char_rom (
    .char_code  (char_code),
    .row        (char_row),
    .pixel_row  (char_pixel_row)
);

// 改为
ascii_rom_16x32_full u_char_rom (
    .clk        (clk_pixel),
    .char_code  (char_code),
    .char_row   (char_row[4:0]),
    .char_data  (char_pixel_row)
);
```

#### 2.3 添加ASCII转换函数

```verilog
// BCD数字 (0-9) 转 ASCII码 ('0'-'9')
function [7:0] digit_to_ascii;
    input [3:0] digit;
    begin
        digit_to_ascii = 8'd48 + {4'd0, digit};  // '0' = ASCII 48
    end
endfunction
```

#### 2.4 简化字符显示逻辑

**旧代码** (需要查表):
```verilog
if (pixel_x_d1 >= 40 && pixel_x_d1 < 56) begin
    char_code = 6'd16;  // 'F' (谁知道16是什么?)
    char_col = pixel_x_d1 - 12'd40;
    in_char_area = 1'b1;
end
```

**新代码** (直接使用ASCII):
```verilog
if (pixel_x_d1 >= 40 && pixel_x_d1 < 56) begin
    char_code = 8'd70;   // 'F' (ASCII 70)
    // 或者更清晰: char_code = "F";  // Verilog支持字符常量
    char_col = pixel_x_d1 - 12'd40;
    in_char_area = 1'b1;
end
```

**数字显示**:
```verilog
// 旧代码
char_code = {2'b00, freq_d4};  // 假设freq_d4是BCD

// 新代码
char_code = digit_to_ascii(freq_d4);  // 自动转ASCII
// 或直接: char_code = 8'd48 + freq_d4;
```

---

### 步骤3: 重新设计参数显示布局

使用完整字符集后,可以显示更清晰的标签:

```verilog
// 第1行: "Freq: 05000Hz" (而不是 "F:05000Hz")
if (pixel_y_d1 >= PARAM_Y_START && pixel_y_d1 < PARAM_Y_START + 32) begin
    char_row = pixel_y_d1 - PARAM_Y_START;
    
    // "Freq:"
    if (pixel_x_d1 >= 40 && pixel_x_d1 < 56) char_code = "F";
    else if (pixel_x_d1 >= 56 && pixel_x_d1 < 72) char_code = "r";
    else if (pixel_x_d1 >= 72 && pixel_x_d1 < 88) char_code = "e";
    else if (pixel_x_d1 >= 88 && pixel_x_d1 < 104) char_code = "q";
    else if (pixel_x_d1 >= 104 && pixel_x_d1 < 120) char_code = ":";
    else if (pixel_x_d1 >= 120 && pixel_x_d1 < 136) char_code = " ";
    
    // 数值部分...
end

// 第2行: "Ampl: 0051"
// 第3行: "Duty: 50.0%"
// 第4行: "THD : 1.23%"
// 第5行: "Phase:180.0"
// 第6行: "CH1:Sine 95%  CH2:Square 88%"
```

---

## 资源消耗对比

| 方案 | ROM大小 | 字符数 | BRAM使用 | 优缺点 |
|------|---------|--------|---------|--------|
| 旧char_rom | ~3KB | 45个 | <1块 | ❌字符少,不规范 |
| ascii_rom | ~15KB | 95个 | ~1块 | ✅标准,易用 |
| 8×16小字体 | ~4KB | 95个 | <1块 | ✅省资源,字较小 |

---

## 下一步行动

### 选项A: 快速修复 (30分钟)
1. 使用我提供的 `ascii_rom_16x32.v` (已包含常用字符)
2. 仅修改 `hdmi_display_ctrl.v` 中的实例化和char_code宽度
3. 保持现有显示内容,仅修复编码错误

### 选项B: 完整升级 (2小时)
1. 运行Python脚本生成完整字库
2. 重写所有参数显示逻辑
3. 优化布局,显示完整单词标签

### 选项C: 我来帮您 (5分钟)
告诉我您选择哪个方案,我直接为您修改所有文件!

---

## 常见问题

**Q: ASCII ROM会占用很多资源吗?**  
A: 16×32字体95个字符约15KB,现代FPGA的BRAM通常有几百KB,占用<1%。

**Q: 能否支持中文?**  
A: 可以,但需要更大ROM。建议使用外部SPI Flash存储GB2312字库(~200KB)。

**Q: 显示速度会变慢吗?**  
A: 不会。ROM访问速度与原来相同,都是1-2个时钟周期。

**Q: 我想要不同字体怎么办?**  
A: 修改Python脚本中的字体文件路径和大小即可。

---

**准备好升级了吗?告诉我您的选择,我来帮您完成!** 🚀
