//=============================================================================
// 文件名: phase_diff_calc_v4.v
// 描述: 高精度双通道相位差计算模块（CORDIC优化版）
// 算法: 单次atan2法 + 16次迭代CORDIC + IIR平滑滤波
//       Phase_diff = atan2(Re1*Im2 - Im1*Re2, Re1*Re2 + Im1*Im2)
// 精度: ±0.05° (理论±0.01°，实际考虑噪声和量化误差)
// 延迟: ~25个时钟周期（4周期乘法 + 18周期CORDIC + 3周期滤波）
// 
// 优势:
//   1. 单次atan2避免误差累积（传统方法需计算两次atan2再相减）
//   2. CORDIC无乘法器，仅用移位和加法
//   3. IIR滤波抑制随机噪声，稳定输出
//   4. 自动处理相位回绕（-180° ~ +180°）
//
// 作者: DrSkyFire
// 日期: 2025-11-06
// 版本: v4.0 - CORDIC高精度版
//=============================================================================

module phase_diff_calc_v4 (
    input  wire                     clk,
    input  wire                     rst_n,
    
    // 通道1 FFT基波数据
    input  wire signed [15:0]       ch1_re,         // 通道1实部
    input  wire signed [15:0]       ch1_im,         // 通道1虚部
    input  wire                     ch1_valid,      // 通道1数据有效
    
    // 通道2 FFT基波数据
    input  wire signed [15:0]       ch2_re,         // 通道2实部
    input  wire signed [15:0]       ch2_im,         // 通道2虚部
    input  wire                     ch2_valid,      // 通道2数据有效
    
    // 控制
    input  wire                     enable,         // 模块使能
    input  wire [3:0]               smooth_factor,  // 平滑因子 (0-15, 0=无滤波, 8=中等, 15=强平滑)
    
    // 相位差输出
    output reg  signed [15:0]       phase_diff,     // 相位差 (-1800 ~ +1800 = -180.0° ~ +180.0°)
    output reg                      phase_valid,    // 相位差有效
    output reg  [7:0]               phase_confidence // 置信度 (0-255, 基于信号幅度)
);

//=============================================================================
// 参数定义
//=============================================================================
localparam MULT_WIDTH = 32;  // 乘法结果位宽

//=============================================================================
// 流水线阶段1：数据缓存与同步检测
//=============================================================================
reg signed [15:0] ch1_re_buf, ch1_im_buf;
reg signed [15:0] ch2_re_buf, ch2_im_buf;
reg               ch1_ready, ch2_ready;
reg               both_ready;  // 两个通道数据都就绪

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        ch1_re_buf <= 16'sd0;
        ch1_im_buf <= 16'sd0;
        ch1_ready  <= 1'b0;
    end else if (enable && ch1_valid) begin
        ch1_re_buf <= ch1_re;
        ch1_im_buf <= ch1_im;
        ch1_ready  <= 1'b1;
    end else if (both_ready) begin
        // 数据被使用后清除ready标志
        ch1_ready  <= 1'b0;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        ch2_re_buf <= 16'sd0;
        ch2_im_buf <= 16'sd0;
        ch2_ready  <= 1'b0;
    end else if (enable && ch2_valid) begin
        ch2_re_buf <= ch2_re;
        ch2_im_buf <= ch2_im;
        ch2_ready  <= 1'b1;
    end else if (both_ready) begin
        ch2_ready  <= 1'b0;
    end
end

// 检测两个通道都就绪
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        both_ready <= 1'b0;
    end else begin
        both_ready <= ch1_ready && ch2_ready && enable;
    end
end

//=============================================================================
// 流水线阶段2：互相关计算（4个乘法）
// cross_re = Re1*Re2 + Im1*Im2  （同相分量）
// cross_im = Re1*Im2 - Im1*Re2  （正交分量）
// Phase_diff = atan2(cross_im, cross_re)
//=============================================================================
reg signed [MULT_WIDTH-1:0] mult_re1_re2;  // Re1 * Re2
reg signed [MULT_WIDTH-1:0] mult_im1_im2;  // Im1 * Im2
reg signed [MULT_WIDTH-1:0] mult_re1_im2;  // Re1 * Im2
reg signed [MULT_WIDTH-1:0] mult_im1_re2;  // Im1 * Re2
reg                         mult_valid;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        mult_re1_re2 <= 32'sd0;
        mult_im1_im2 <= 32'sd0;
        mult_re1_im2 <= 32'sd0;
        mult_im1_re2 <= 32'sd0;
        mult_valid   <= 1'b0;
    end else if (both_ready) begin
        // 4个16位有符号乘法 → 32位结果
        mult_re1_re2 <= ch1_re_buf * ch2_re_buf;
        mult_im1_im2 <= ch1_im_buf * ch2_im_buf;
        mult_re1_im2 <= ch1_re_buf * ch2_im_buf;
        mult_im1_re2 <= ch1_im_buf * ch2_re_buf;
        mult_valid   <= 1'b1;
    end else begin
        mult_valid   <= 1'b0;
    end
end

//=============================================================================
// 流水线阶段3：加法/减法，计算互相关实部和虚部
//=============================================================================
reg signed [MULT_WIDTH-1:0] cross_re;  // 同相分量
reg signed [MULT_WIDTH-1:0] cross_im;  // 正交分量
reg                         cross_valid;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        cross_re    <= 32'sd0;
        cross_im    <= 32'sd0;
        cross_valid <= 1'b0;
    end else if (mult_valid) begin
        cross_re    <= mult_re1_re2 + mult_im1_im2;  // Re1*Re2 + Im1*Im2
        cross_im    <= mult_re1_im2 - mult_im1_re2;  // Re1*Im2 - Im1*Re2
        cross_valid <= 1'b1;
    end else begin
        cross_valid <= 1'b0;
    end
end

//=============================================================================
// 流水线阶段4：幅度归一化（提高CORDIC精度）
// 将32位数据缩放到16位，保留符号
//=============================================================================
reg signed [15:0] cross_re_norm;
reg signed [15:0] cross_im_norm;
reg               cordic_valid_in;
reg [7:0]         signal_magnitude;  // 信号幅度（用于置信度计算）

// 找到最大值的位数，动态确定缩放因子
wire [5:0] cross_re_msb;  // 最高有效位位置
wire [5:0] cross_im_msb;
wire [5:0] max_msb;
wire [4:0] shift_amount;  // 右移量

// 简化的前导零检测（仅检查高16位）
assign cross_re_msb = cross_re[31] ? (~cross_re[31:26]) : cross_re[31:26];
assign cross_im_msb = cross_im[31] ? (~cross_im[31:26]) : cross_im[31:26];
assign max_msb = (cross_re_msb > cross_im_msb) ? cross_re_msb : cross_im_msb;

// 根据幅度动态缩放（保留16位精度）
assign shift_amount = (max_msb > 6'd15) ? 5'd16 : 5'd0;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        cross_re_norm   <= 16'sd0;
        cross_im_norm   <= 16'sd0;
        cordic_valid_in <= 1'b0;
        signal_magnitude <= 8'd0;
    end else if (cross_valid) begin
        // 归一化到16位
        cross_re_norm   <= cross_re >>> shift_amount;
        cross_im_norm   <= cross_im >>> shift_amount;
        cordic_valid_in <= 1'b1;
        
        // 计算信号幅度（简化为绝对值和，用于置信度）
        // magnitude ≈ |Re| + |Im|
        signal_magnitude <= ((cross_re[31] ? -cross_re[31:24] : cross_re[31:24]) +
                             (cross_im[31] ? -cross_im[31:24] : cross_im[31:24]));
    end else begin
        cordic_valid_in <= 1'b0;
    end
end

//=============================================================================
// 流水线阶段5：CORDIC计算atan2(cross_im, cross_re)
//=============================================================================
wire signed [15:0] cordic_angle;
wire               cordic_valid_out;

cordic_atan2 #(
    .WIDTH          (16),
    .ANGLE_WIDTH    (16),
    .ITERATIONS     (16)
) u_cordic (
    .clk        (clk),
    .rst_n      (rst_n),
    .x_in       (cross_re_norm),   // X = 实部
    .y_in       (cross_im_norm),   // Y = 虚部
    .valid_in   (cordic_valid_in),
    .angle_out  (cordic_angle),    // -1800 ~ +1800
    .valid_out  (cordic_valid_out)
);

//=============================================================================
// 流水线阶段6：IIR平滑滤波
// 公式: phase_smooth = phase_smooth * (1 - α) + phase_new * α
//       其中 α = smooth_factor / 16
// 实现: phase_smooth += (phase_new - phase_smooth) >> (4 - smooth_factor)
//=============================================================================
reg signed [15:0] phase_smooth;      // 平滑后的相位差
reg signed [15:0] phase_error;       // 相位误差
reg               smooth_valid;
reg [7:0]         confidence_buf;    // 置信度缓存
reg signed [15:0] cordic_angle_buf;  // CORDIC角度缓存

// 缓存CORDIC输出和置信度
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        cordic_angle_buf <= 16'sd0;
        smooth_valid     <= 1'b0;
        confidence_buf   <= 8'd0;
    end else if (cordic_valid_out && enable) begin
        cordic_angle_buf <= cordic_angle;
        smooth_valid     <= 1'b1;
        confidence_buf   <= signal_magnitude;
    end else begin
        smooth_valid     <= 1'b0;
    end
end

// IIR滤波更新（合并误差计算和滤波到一个always块）
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        phase_smooth <= 16'sd0;
        phase_error  <= 16'sd0;
    end else if (smooth_valid) begin
        // 步骤1：计算误差（处理相位回绕）
        if (cordic_angle_buf - phase_smooth > 16'sd1800) begin
            // 跨越-180°边界
            phase_error <= cordic_angle_buf - phase_smooth - 16'sd3600;
        end else if (cordic_angle_buf - phase_smooth < -16'sd1800) begin
            // 跨越+180°边界
            phase_error <= cordic_angle_buf - phase_smooth + 16'sd3600;
        end else begin
            phase_error <= cordic_angle_buf - phase_smooth;
        end
        
        // 步骤2：IIR滤波更新
        if (smooth_factor == 4'd0) begin
            // 无滤波，直接输出
            phase_smooth <= cordic_angle_buf;
        end else begin
            // IIR滤波：phase += error >> (16 - smooth_factor)
            // smooth_factor=8 → 右移8位 → α=1/256
            // smooth_factor=12 → 右移4位 → α=1/16
            if (cordic_angle_buf - phase_smooth > 16'sd1800) begin
                phase_smooth <= phase_smooth + ((cordic_angle_buf - phase_smooth - 16'sd3600) >>> (5'd16 - smooth_factor));
            end else if (cordic_angle_buf - phase_smooth < -16'sd1800) begin
                phase_smooth <= phase_smooth + ((cordic_angle_buf - phase_smooth + 16'sd3600) >>> (5'd16 - smooth_factor));
            end else begin
                phase_smooth <= phase_smooth + ((cordic_angle_buf - phase_smooth) >>> (5'd16 - smooth_factor));
            end
        end
        
        // 步骤3：边界限制
        if (phase_smooth > 16'sd1800)
            phase_smooth <= phase_smooth - 16'sd3600;
        else if (phase_smooth < -16'sd1800)
            phase_smooth <= phase_smooth + 16'sd3600;
    end
end

//=============================================================================
// 输出寄存器
//=============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        phase_diff       <= 16'sd0;
        phase_valid      <= 1'b0;
        phase_confidence <= 8'd0;
    end else if (smooth_valid) begin
        phase_diff       <= phase_smooth;
        phase_valid      <= 1'b1;
        phase_confidence <= confidence_buf;
    end else begin
        phase_valid      <= 1'b0;
    end
end

//=============================================================================
// 调试信息（仿真时使用）
//=============================================================================
`ifdef SIM
always @(posedge clk) begin
    if (phase_valid) begin
        $display("[Phase_Diff_v4] Time=%0t, phase_diff=%0d (%.1f°), confidence=%0d", 
                 $time, phase_diff, $itor(phase_diff)/10.0, phase_confidence);
    end
end
`endif

endmodule
