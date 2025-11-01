# HDMI时序违例修复方案

## 问题诊断

### 当前状态
- **时钟**: clk_hdmi_pixel @ 148.5MHz (周期 6.734ns)
- **违例**: WNS = -2.564ns
- **关键路径**: pixel_x_d1[6] →  (11层MUX) → char_code[1]
  - 数据到达: 13.951ns
  - 数据要求: 11.376ns
  - 逻辑延迟: 3.648ns (40.98%)
  - 布线延迟: 5.254ns (59.02%)

### 根因分析
字符生成逻辑(行738-1710)包含约200行嵌套if-else，综合器优化为11层MUX级联组合逻辑：
```
pixel_x_d1[6] → N1159_mux2 → N1490[0] → N1548_77[1] → 
N1548_87[1] → N1548_94[1]_muxf6 → N1548_95[1] → 
N7197_212[1]_muxf6 → N7197_215[1] → N7197_217[1] → 
N7195_111[1]_muxf7 → N7189_31[1]_muxf6 → char_code[1]
```

## 方案对比

### 方案A: 降低像素时钟频率（最简单）
- **720p@60Hz**: 74.25MHz → WNS改善 ~6ns ✅
- **1080p@30Hz**: 74.25MHz → WNS改善 ~6ns ✅
- **优点**: 无需改代码，仅修改PLL配置
- **缺点**: 降低显示质量

### 方案B: 插入流水线寄存器（中等难度）
- **目标**: 将11层MUX分为2段(5+6层)
- **方法**: 添加中间寄存器 `char_region_reg`
- **预期改善**: WNS +3~5ns ✅
- **优点**: 保持1080p@60Hz，硬件性能不变
- **缺点**: 引入1拍延迟，需调整后续流水线

### 方案C: 完全重构为LUT架构（高难度）
- **目标**: 使用BRAM作为字符查找表
- **预期改善**: WNS +5~8ns ✅
- **优点**: 最优时序性能
- **缺点**: 大量代码重写，功能风险高

## 推荐方案B实施细节

### Step 1: 添加流水线寄存器 (插入在pixel_x/y_d1之后)

```verilog
// 在变量声明区添加(约行164)
reg [3:0] char_region;  // 字符区域编码 (Y轴=1, X轴=2, AI=3, 参数=4)

// 在Stage 2添加区域判断(替换原always块开头)
always @(posedge clk_pixel or negedge rst_n) begin
    if (!rst_n) begin
        char_region <= 4'd0;
    end else begin
        // 区域优先级判断(组合逻辑简化)
        if (y_axis_char_valid)
            char_region <= 4'd1;
        else if (pixel_y_d1 >= SPECTRUM_Y_END && pixel_y_d1 < SPECTRUM_Y_END + 32)
            char_region <= 4'd2;
        else if (pixel_y_d1 >= 830 && pixel_y_d1 < 862)
            char_region <= 4'd3;
        else if (pixel_y_d1 >= PARAM_Y_START && pixel_y_d1 < PARAM_Y_END)
            char_region <= 4'd4;
        else
            char_region <= 4'd0;
    end
end

// 在Stage 3使用char_region简化判断
always @(posedge clk_pixel or negedge rst_n) begin
    if (!rst_n) begin
        char_code <= 8'd32;
        //...
    end else begin
        case (char_region)
            4'd1: begin // Y轴标度
                char_code <= y_axis_char_code;
                // ...
            end
            4'd2: begin // X轴标度
                if (pixel_x_d2 >= 80 && pixel_x_d2 < 96)
                    char_code <= 8'd48;
                // ...
            end
            // ...
        endcase
    end
end
```

### Step 2: 调整延迟链
- 将pixel_x_d2, pixel_y_d2用于char_code生成
- 将video_active_d4 → d5 (匹配新延迟)
- 调整RGB生成always块使用d5信号

### Step 3: 综合验证
1. 重新编译项目
2. 检查时序报告：
   - 期望WNS: -2.564ns → +0.5ns ~ +2.0ns
   - 检查是否出现新的违例路径
3. 功能仿真：验证字符显示延迟是否正确

## 实施风险评估
- **时序风险**: 低（寄存器插入是标准优化手段）
- **功能风险**: 中（需要仔细调整延迟链对齐）
- **调试难度**: 中（需要时序仿真验证）

## 回退方案
如果方案B效果不佳：
1. Git回退到commit a42ca71
2. 采用方案A降频到720p@60Hz
3. 或组合方案A+B，降至1080p@45Hz + 流水线优化

## 预期时间线
- 代码修改: 30分钟
- 综合编译: 10分钟
- 时序验证: 10分钟
- 功能测试: 20分钟
- **总计**: ~70分钟
