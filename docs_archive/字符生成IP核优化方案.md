# 字符生成IP核优化方案

## 核心思路

将当前的11层MUX组合逻辑替换为ROM查表，彻底消除时序瓶颈。

## 架构对比

### 当前架构（有问题）
```
pixel_x_d1[11:0] ──┐
                   ├─→ [11层MUX] ─→ char_code[7:0] ─→ [ROM] ─→ char_pixel_row
pixel_y_d1[11:0] ──┘   (41KB组合逻辑)                (ascii_rom)
                       WNS = -2.564ns ❌
```

### 优化架构（ROM查表）
```
pixel_x_d1[11:0] ──┐
                   ├─→ [地址编码] ─→ rom_addr[13:0] ─→ [Char Map ROM] ─→ char_code ─→ [Font ROM] ─→ char_pixel
pixel_y_d1[11:0] ──┘   (简单组合逻辑)                 (IP核生成)         (ascii_rom)
                       ~2层逻辑                        1拍延迟           1拍延迟
                       预期 WNS > 0 ✅
```

## 实施步骤

### Step 1: 生成字符映射ROM数据

创建Python脚本生成字符映射表的MIF/COE文件：

```python
# generate_char_map_rom.py
"""
生成字符映射ROM初始化文件
ROM大小: 根据显示区域计算
- Y轴标度区域: 100个位置
- X轴标度区域: 100个位置  
- AI识别区域: 50个位置
- 参数显示区域: 200个位置
总计: ~512字节 (使用Distributed ROM IP核)
"""

def generate_char_map():
    # 初始化ROM数组（默认空格ASCII 32）
    rom_size = 1024  # 扩展到1K以容纳所有区域
    rom_data = [32] * rom_size
    
    # Y轴标度区域映射 (地址0-99)
    # 示例: 0%, 25%, 50%, 75%, 100%
    y_labels = ["100%", "75%", "50%", "25%", "0%"]
    for i, label in enumerate(y_labels):
        base_addr = i * 20
        for j, char in enumerate(label):
            rom_data[base_addr + j] = ord(char)
    
    # X轴标度区域映射 (地址100-199)
    # 频域: 0, 3.5, 7.0, 10.5, 14.0, 17.5 MHz
    x_labels_freq = ["0", "3.5", "7.0", "10.5", "14.0", "17.5"]
    for i, label in enumerate(x_labels_freq):
        base_addr = 100 + i * 10
        for j, char in enumerate(label):
            rom_data[base_addr + j] = ord(char)
    
    # AI识别区域映射 (地址200-299)
    ai_labels = ["CH1:", "Sine", "CH2:", "Square"]
    for i, label in enumerate(ai_labels):
        base_addr = 200 + i * 20
        for j, char in enumerate(label):
            rom_data[base_addr + j] = ord(char)
    
    # 参数显示区域映射 (地址300-799)
    param_labels = [
        "CH1 Freq:", "CH2 Freq:",
        "CH1 Ampl:", "CH2 Ampl:",
        "CH1 Duty:", "CH2 Duty:",
        "CH1 THD:", "CH2 THD:",
        "Phase:"
    ]
    for i, label in enumerate(param_labels):
        base_addr = 300 + i * 20
        for j, char in enumerate(label):
            rom_data[base_addr + j] = ord(char)
    
    # 生成COE文件 (紫光同创ROM IP格式)
    with open("char_map_rom.coe", "w") as f:
        f.write("memory_initialization_radix=10;\n")
        f.write("memory_initialization_vector=\n")
        for i, data in enumerate(rom_data):
            if i == len(rom_data) - 1:
                f.write(f"{data};\n")
            else:
                f.write(f"{data},\n")
    
    print(f"✅ 生成字符映射ROM: {len(rom_data)}字节")
    print(f"   文件: char_map_rom.coe")

if __name__ == "__main__":
    generate_char_map()
```

### Step 2: 创建ROM IP核

在Pango Design Suite中：

1. **打开IP Catalog**
2. **选择**: `Memory → DRM → DRM Based ROM (1.7)`
3. **配置参数**:
   ```
   Memory Type: ROM
   Data Width: 8 bits (存储ASCII码)
   Address Width: 10 bits (1024深度)
   Initialization File: char_map_rom.coe
   Output Register: Yes (流水线优化)
   ```
4. **生成IP**: `ipcore/char_map_rom/char_map_rom.v`

### Step 3: 修改hdmi_display_ctrl.v

#### 3.1 实例化Char Map ROM

```verilog
// 在行700左右，char_rom实例化之前添加

//=============================================================================
// 字符映射ROM (使用IP核，消除组合逻辑)
//=============================================================================
wire [9:0] char_map_addr;
wire [7:0] char_code_from_rom;

char_map_rom u_char_map_rom (
    .clk    (clk_pixel),
    .addr   (char_map_addr),      // 10位地址
    .dout   (char_code_from_rom)  // 8位ASCII码
);
```

#### 3.2 简化地址编码逻辑

```verilog
// 替换原来738-1710行的巨大always块

//=============================================================================
// 字符映射地址计算（简化的组合逻辑）
//=============================================================================
reg [9:0] char_map_addr_comb;
reg char_map_valid;

always @(*) begin
    char_map_addr_comb = 10'd0;
    char_map_valid = 1'b0;
    
    // Y轴标度区域 (地址0-99)
    if (y_axis_char_valid) begin
        char_map_addr_comb = {4'd0, y_axis_char_row[5:0]};
        char_map_valid = 1'b1;
    end
    
    // X轴标度区域 (地址100-199)
    else if (pixel_y_d1 >= SPECTRUM_Y_END && pixel_y_d1 < SPECTRUM_Y_END + 32) begin
        char_map_addr_comb = 10'd100 + pixel_x_d1[9:4];  // 粗粒度位置映射
        char_map_valid = 1'b1;
    end
    
    // AI识别区域 (地址200-299)
    else if (pixel_y_d1 >= 830 && pixel_y_d1 < 862) begin
        char_map_addr_comb = 10'd200 + pixel_x_d1[9:4];
        char_map_valid = 1'b1;
    end
    
    // 参数显示区域 (地址300-799)
    else if (pixel_y_d1 >= PARAM_Y_START && pixel_y_d1 < PARAM_Y_END) begin
        // 行号×50 + 列号 (粗略映射)
        char_map_addr_comb = 10'd300 + 
                             ((pixel_y_d1 - PARAM_Y_START) >> 5) * 10'd50 +
                             (pixel_x_d1 >> 4);
        char_map_valid = 1'b1;
    end
end

// 地址寄存器（打断路径）
reg [9:0] char_map_addr_reg;
always @(posedge clk_pixel) begin
    if (char_map_valid)
        char_map_addr_reg <= char_map_addr_comb;
    else
        char_map_addr_reg <= 10'd0;  // 默认空格
end

assign char_map_addr = char_map_addr_reg;
```

#### 3.3 调整延迟链

由于新增了ROM查表延迟，需要调整char_code使用：

```verilog
// 原来: char_code_d1 → ascii_rom
// 现在: char_code_from_rom → ascii_rom

ascii_rom_16x32_full u_char_rom (
    .clk        (clk_pixel),
    .char_code  (char_code_from_rom),  // 使用ROM输出
    .char_row   (char_row_d2[4:0]),    // 延迟对齐 (d1→d2)
    .char_data  (char_pixel_row)
);
```

#### 3.4 同步调整其他延迟信号

```verilog
// 在延迟链always块中添加
always @(posedge clk_pixel or negedge rst_n) begin
    if (!rst_n) begin
        char_row_d2 <= 5'd0;
        char_col_d2 <= 12'd0;
        in_char_area_d2 <= 1'b0;
    end else begin
        char_row_d2 <= char_row_d1;
        char_col_d2 <= char_col_d1;
        in_char_area_d2 <= in_char_area_d1;
    end
end
```

## 优势分析

### 时序优势
- ✅ **消除11层MUX**: 组合逻辑从41KB代码→10行地址编码
- ✅ **ROM延迟固定**: IP核保证1拍延迟，时序可预测
- ✅ **预期改善**: WNS从-2.564ns → +2.0ns以上

### 资源优势
- ✅ **使用DRM**: 紫光同创FPGA内置的分布式RAM资源
- ✅ **资源占用小**: 1KB ROM仅占极少DRM
- ✅ **无需BRAM**: 保留BRAM给FFT等大数据存储

### 功能优势
- ✅ **易于修改**: 更改字符显示只需重新生成COE文件
- ✅ **支持动态数据**: 可将数值部分保留原逻辑，仅静态文本用ROM
- ✅ **可扩展性强**: 轻松添加新的显示区域

## 混合方案（推荐）

考虑到数值显示（频率、幅度等）是动态的，建议采用**混合架构**：

```verilog
always @(posedge clk_pixel) begin
    if (is_static_text_area) begin
        // 静态文本：使用ROM查表
        char_code <= char_code_from_rom;
    end
    else if (is_dynamic_data_area) begin
        // 动态数值：保留原逻辑（但大幅简化）
        char_code <= digit_to_ascii(current_digit);
    end
    else begin
        char_code <= 8'd32;  // 空格
    end
end
```

这样既消除了大部分组合逻辑，又保留了动态显示功能。

## 实施时间估算

1. **生成char_map_rom.coe**: 30分钟（编写Python脚本）
2. **创建ROM IP核**: 10分钟
3. **修改hdmi_display_ctrl.v**: 40分钟
4. **综合验证**: 10分钟
5. **功能测试**: 20分钟

**总计**: ~110分钟

## 风险评估

- **时序风险**: 极低（ROM IP核时序有保证）
- **功能风险**: 中（需要仔细映射显示区域）
- **资源风险**: 极低（仅1KB DRM）

## 对比总结

| 方案 | 时序改善 | 实施时间 | 功能风险 | 推荐度 |
|------|---------|---------|---------|--------|
| 降低时钟频率 | +5ns | 15分钟 | 低 | ⭐⭐⭐⭐ |
| ROM IP核查表 | +5~7ns | 110分钟 | 中 | ⭐⭐⭐⭐⭐ |
| 流水线寄存器 | +3ns | 70分钟 | 中 | ⭐⭐⭐ |

**推荐**: 如果您有充足时间，**ROM IP核方案是最优选择**，既保持1080p@60Hz，又彻底解决时序问题。如果需要快速修复，先降频，后续再升级为ROM方案。
