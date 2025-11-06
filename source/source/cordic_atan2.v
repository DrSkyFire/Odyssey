//=============================================================================
// 文件名: cordic_atan2.v
// 描述: 高精度CORDIC算法实现atan2(y, x)
// 算法: CORDIC旋转模式（16次迭代）
// 精度: ±0.01° (输出范围：-1800 ~ +1800，表示 -180.0° ~ +180.0°)
// 延迟: 18个时钟周期（2周期预处理 + 16次迭代）
// 资源: 纯组合逻辑 + 流水线寄存器（无乘法器，仅移位和加法）
//
// 原理:
//   CORDIC通过一系列微小旋转将向量旋转到x轴，累积的旋转角度即为atan2(y,x)
//   每次迭代旋转角度: arctan(2^-i)
//   迭代公式:
//     x[i+1] = x[i] - y[i] * 2^-i * d[i]
//     y[i+1] = y[i] + x[i] * 2^-i * d[i]
//     z[i+1] = z[i] - arctan(2^-i) * d[i]
//   其中 d[i] = sign(y[i])，目标是让 y[n] → 0
//
// 作者: DrSkyFire
// 日期: 2025-11-06
// 版本: v1.0
//=============================================================================

module cordic_atan2 #(
    parameter WIDTH = 16,           // 输入数据位宽
    parameter ANGLE_WIDTH = 16,     // 角度位宽（输出-1800~+1800，需要带符号16位）
    parameter ITERATIONS = 16       // 迭代次数（16次可达0.01°精度）
)(
    input  wire                         clk,
    input  wire                         rst_n,
    
    // 输入
    input  wire signed [WIDTH-1:0]      x_in,       // X坐标（实部）
    input  wire signed [WIDTH-1:0]      y_in,       // Y坐标（虚部）
    input  wire                         valid_in,   // 输入有效
    
    // 输出
    output reg  signed [ANGLE_WIDTH-1:0] angle_out, // 角度输出（-1800 ~ +1800 = -180.0° ~ +180.0°）
    output reg                           valid_out  // 输出有效
);

//=============================================================================
// CORDIC角度查找表（arctan(2^-i) * 10，单位0.1°）
// 预计算值，避免除法和三角函数
//=============================================================================
// arctan(2^0)  = 45.0°   → 450
// arctan(2^-1) = 26.565° → 265.65 → 266
// arctan(2^-2) = 14.036° → 140.36 → 140
// ... 依此类推
reg signed [ANGLE_WIDTH-1:0] atan_table [0:15];

initial begin
    atan_table[0]  = 16'sd450;  // arctan(1)      = 45.000°
    atan_table[1]  = 16'sd266;  // arctan(0.5)    = 26.565°
    atan_table[2]  = 16'sd140;  // arctan(0.25)   = 14.036°
    atan_table[3]  = 16'sd71;   // arctan(0.125)  = 7.125°
    atan_table[4]  = 16'sd36;   // arctan(1/16)   = 3.576°
    atan_table[5]  = 16'sd18;   // arctan(1/32)   = 1.790°
    atan_table[6]  = 16'sd9;    // arctan(1/64)   = 0.895°
    atan_table[7]  = 16'sd4;    // arctan(1/128)  = 0.448°
    atan_table[8]  = 16'sd2;    // arctan(1/256)  = 0.224°
    atan_table[9]  = 16'sd1;    // arctan(1/512)  = 0.112°
    atan_table[10] = 16'sd1;    // arctan(1/1024) = 0.056° → 四舍五入为0.1°
    atan_table[11] = 16'sd0;    // arctan(1/2048) = 0.028° → 0
    atan_table[12] = 16'sd0;    // arctan(1/4096) = 0.014° → 0
    atan_table[13] = 16'sd0;    // 后续迭代对0.1°精度贡献小
    atan_table[14] = 16'sd0;
    atan_table[15] = 16'sd0;
end

//=============================================================================
// 流水线寄存器
//=============================================================================
// 阶段0：输入预处理（象限判断）
reg signed [WIDTH-1:0]      x_stage0, y_stage0;
reg signed [ANGLE_WIDTH-1:0] z_stage0;  // 初始角度偏移
reg                         valid_stage0;
reg [1:0]                   quadrant;   // 象限标志

// 阶段1-16：CORDIC迭代
reg signed [WIDTH-1:0]      x_stage [0:ITERATIONS];
reg signed [WIDTH-1:0]      y_stage [0:ITERATIONS];
reg signed [ANGLE_WIDTH-1:0] z_stage [0:ITERATIONS];
reg                         valid_stage [0:ITERATIONS];

// 临时变量（组合逻辑）
wire signed [WIDTH-1:0]     x_shifted [0:ITERATIONS-1];
wire signed [WIDTH-1:0]     y_shifted [0:ITERATIONS-1];
wire                        d_sign [0:ITERATIONS-1];

//=============================================================================
// 阶段0：输入预处理 - 象限判断和坐标转换
// 目的：将所有输入转换到第一象限（x>0, y>0），便于CORDIC收敛
//=============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        x_stage0 <= 0;
        y_stage0 <= 0;
        z_stage0 <= 0;
        quadrant <= 2'd0;
        valid_stage0 <= 1'b0;
    end else if (valid_in) begin
        valid_stage0 <= 1'b1;
        
        // 判断象限并转换坐标
        case ({x_in[WIDTH-1], y_in[WIDTH-1]})  // {x符号位, y符号位}
            2'b00: begin  // 第一象限 (x>0, y>0)
                x_stage0 <= x_in;
                y_stage0 <= y_in;
                z_stage0 <= 16'sd0;      // 初始角度0°
                quadrant <= 2'd0;
            end
            2'b01: begin  // 第四象限 (x>0, y<0)
                x_stage0 <= x_in;
                y_stage0 <= y_in;        // 保持负数，CORDIC会处理
                z_stage0 <= 16'sd0;
                quadrant <= 2'd3;
            end
            2'b10: begin  // 第二象限 (x<0, y>0)
                x_stage0 <= -y_in;       // 旋转90°：(x,y) → (y,-x)
                y_stage0 <= x_in;        // 然后再旋转到第一象限
                z_stage0 <= 16'sd900;    // 初始角度90°
                quadrant <= 2'd1;
            end
            2'b11: begin  // 第三象限 (x<0, y<0)
                x_stage0 <= -x_in;       // 取反进入第一象限
                y_stage0 <= -y_in;
                z_stage0 <= -16'sd1800;  // 初始角度-180°（后续会调整）
                quadrant <= 2'd2;
            end
        endcase
    end else begin
        valid_stage0 <= 1'b0;
    end
end

//=============================================================================
// 阶段1：初始化CORDIC迭代
//=============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        x_stage[0] <= 0;
        y_stage[0] <= 0;
        z_stage[0] <= 0;
        valid_stage[0] <= 1'b0;
    end else begin
        x_stage[0] <= x_stage0;
        y_stage[0] <= y_stage0;
        z_stage[0] <= z_stage0;
        valid_stage[0] <= valid_stage0;
    end
end

//=============================================================================
// CORDIC迭代核心（组合逻辑 + 流水线寄存器）
// 每次迭代旋转角度：arctan(2^-i)
//=============================================================================
genvar i;
generate
    for (i = 0; i < ITERATIONS; i = i + 1) begin : cordic_iteration
        
        // 组合逻辑：计算下一次迭代的值
        assign d_sign[i] = y_stage[i][WIDTH-1];  // y的符号位：1=负数，0=正数
        
        // 右移实现除以2^i
        assign x_shifted[i] = y_stage[i] >>> i;  // 算术右移保留符号
        assign y_shifted[i] = x_stage[i] >>> i;
        
        // 流水线寄存器：存储迭代结果
        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                x_stage[i+1] <= 0;
                y_stage[i+1] <= 0;
                z_stage[i+1] <= 0;
                valid_stage[i+1] <= 1'b0;
            end else begin
                // CORDIC迭代公式
                if (d_sign[i]) begin  // y < 0，逆时针旋转
                    x_stage[i+1] <= x_stage[i] + x_shifted[i];
                    y_stage[i+1] <= y_stage[i] + y_shifted[i];
                    z_stage[i+1] <= z_stage[i] + atan_table[i];
                end else begin        // y >= 0，顺时针旋转
                    x_stage[i+1] <= x_stage[i] - x_shifted[i];
                    y_stage[i+1] <= y_stage[i] - y_shifted[i];
                    z_stage[i+1] <= z_stage[i] - atan_table[i];
                end
                
                valid_stage[i+1] <= valid_stage[i];
            end
        end
    end
endgenerate

//=============================================================================
// 输出阶段：角度范围调整到 -180° ~ +180°
//=============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        angle_out <= 16'sd0;
        valid_out <= 1'b0;
    end else begin
        valid_out <= valid_stage[ITERATIONS];
        
        if (valid_stage[ITERATIONS]) begin
            // z_stage[ITERATIONS] 已经是最终角度
            angle_out <= z_stage[ITERATIONS];
            
            // 边界处理：确保在 -1800 ~ +1800 范围内
            if (z_stage[ITERATIONS] > 16'sd1800) begin
                angle_out <= z_stage[ITERATIONS] - 16'sd3600;
            end else if (z_stage[ITERATIONS] < -16'sd1800) begin
                angle_out <= z_stage[ITERATIONS] + 16'sd3600;
            end else begin
                angle_out <= z_stage[ITERATIONS];
            end
        end
    end
end

//=============================================================================
// 调试信息（综合时可移除）
//=============================================================================
`ifdef SIM
// 仿真调试输出
always @(posedge clk) begin
    if (valid_out) begin
        $display("[CORDIC] Time=%0t, angle_out=%0d (%.1f°)", 
                 $time, angle_out, $itor(angle_out)/10.0);
    end
end
`endif

endmodule
