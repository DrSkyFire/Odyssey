//=============================================================================
// 文件名: phase_diff_calc.v
// 描述: 双通道相位差计算模块
// 算法: 基于FFT输出的实部和虚部计算相位
//       Phase = atan2(Im, Re)
//       Phase_diff = Phase_CH2 - Phase_CH1
// 精度: 0.1度 (0-3599 表示 0-359.9度)
//=============================================================================

module phase_diff_calc (
    input  wire         clk,
    input  wire         rst_n,
    
    // 通道1 FFT输出（基波频点数据）
    input  wire signed [15:0]  ch1_re,          // 实部
    input  wire signed [15:0]  ch1_im,          // 虚部
    input  wire         ch1_valid,              // 数据有效
    
    // 通道2 FFT输出（基波频点数据）
    input  wire signed [15:0]  ch2_re,          // 实部
    input  wire signed [15:0]  ch2_im,          // 虚部
    input  wire         ch2_valid,              // 数据有效
    
    // 相位差输出
    output reg  [15:0]  phase_diff,             // 0-3599 表示 0-359.9度
    output reg          phase_valid,            // 相位差有效标志
    
    // 控制
    input  wire         enable                  // 使能计算
);

//=============================================================================
// 参数定义
//=============================================================================
localparam PI = 16'd3142;  // π * 1000 (用于角度计算)

//=============================================================================
// 内部信号
//=============================================================================
reg signed [15:0] ch1_re_buf, ch1_im_buf;
reg signed [15:0] ch2_re_buf, ch2_im_buf;
reg        ch1_data_ready, ch2_data_ready;

wire signed [15:0] phase_ch1, phase_ch2;
wire        phase_ch1_valid, phase_ch2_valid;

reg  [15:0] phase_diff_calc;

//=============================================================================
// 通道1数据缓存
//=============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        ch1_re_buf <= 16'd0;
        ch1_im_buf <= 16'd0;
        ch1_data_ready <= 1'b0;
    end else if (ch1_valid && enable) begin
        ch1_re_buf <= ch1_re;
        ch1_im_buf <= ch1_im;
        ch1_data_ready <= 1'b1;
    end else if (!enable) begin
        ch1_data_ready <= 1'b0;
    end
end

//=============================================================================
// 通道2数据缓存
//=============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        ch2_re_buf <= 16'd0;
        ch2_im_buf <= 16'd0;
        ch2_data_ready <= 1'b0;
    end else if (ch2_valid && enable) begin
        ch2_re_buf <= ch2_re;
        ch2_im_buf <= ch2_im;
        ch2_data_ready <= 1'b1;
    end else if (!enable) begin
        ch2_data_ready <= 1'b0;
    end
end

//=============================================================================
// 通道1相位计算（atan2查找表方法）
//=============================================================================
atan2_lut u_atan2_ch1 (
    .clk        (clk),
    .rst_n      (rst_n),
    .x          (ch1_re_buf),       // 实部 (X)
    .y          (ch1_im_buf),       // 虚部 (Y)
    .valid_in   (ch1_data_ready),
    .angle      (phase_ch1),        // 输出角度 (0-3599 = 0-359.9度)
    .valid_out  (phase_ch1_valid)
);

//=============================================================================
// 通道2相位计算
//=============================================================================
atan2_lut u_atan2_ch2 (
    .clk        (clk),
    .rst_n      (rst_n),
    .x          (ch2_re_buf),
    .y          (ch2_im_buf),
    .valid_in   (ch2_data_ready),
    .angle      (phase_ch2),
    .valid_out  (phase_ch2_valid)
);

//=============================================================================
// 相位差计算
// Phase_diff = Phase_CH2 - Phase_CH1
// 处理角度回绕 (wrap around)
//=============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        phase_diff_calc <= 16'd0;
    end else if (phase_ch1_valid && phase_ch2_valid) begin
        // 计算差值
        if (phase_ch2 >= phase_ch1) begin
            phase_diff_calc <= phase_ch2 - phase_ch1;
        end else begin
            // 处理跨越360度的情况
            phase_diff_calc <= phase_ch2 + 16'd3600 - phase_ch1;
        end
        
        // 限制在 -180° ~ +180° 范围
        if (phase_diff_calc > 16'd1800) begin
            phase_diff_calc <= phase_diff_calc - 16'd3600;
        end
    end
end

//=============================================================================
// 输出寄存器
//=============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        phase_diff <= 16'd0;
        phase_valid <= 1'b0;
    end else begin
        phase_diff <= phase_diff_calc;
        phase_valid <= phase_ch1_valid && phase_ch2_valid;
    end
end

endmodule


//=============================================================================
// 子模块: atan2查找表模块
// 功能: 计算 atan2(y, x) 返回角度 (0-3599 表示 0-359.9度)
// 方法: 象限判断 + 分段线性近似
//=============================================================================
module atan2_lut (
    input  wire         clk,
    input  wire         rst_n,
    input  wire signed [15:0]  x,           // 实部
    input  wire signed [15:0]  y,           // 虚部
    input  wire         valid_in,
    output reg  [15:0]  angle,              // 角度输出 (0-3599)
    output reg          valid_out
);

//=============================================================================
// 内部信号
//=============================================================================
reg signed [15:0] x_abs, y_abs;
reg [1:0]  quadrant;        // 象限 (0-3)
reg [15:0] angle_base;      // 基础角度
reg [15:0] angle_offset;    // 偏移角度
reg [2:0]  state;

// 查找表：atan(y/x) 当 0 <= y/x <= 1 时的值
// 存储 16个点，线性插值
reg [15:0] atan_table [0:15];

initial begin
    // atan(i/16) * 180/π * 10, i = 0..15
    atan_table[0]  = 16'd0;      // atan(0/16) = 0.0°
    atan_table[1]  = 16'd36;     // atan(1/16) ≈ 3.6°
    atan_table[2]  = 16'd71;     // atan(2/16) ≈ 7.1°
    atan_table[3]  = 16'd107;    // atan(3/16) ≈ 10.7°
    atan_table[4]  = 16'd143;    // atan(4/16) ≈ 14.3°
    atan_table[5]  = 16'd178;    // atan(5/16) ≈ 17.8°
    atan_table[6]  = 16'd213;    // atan(6/16) ≈ 21.3°
    atan_table[7]  = 16'd248;    // atan(7/16) ≈ 24.8°
    atan_table[8]  = 16'd282;    // atan(8/16) ≈ 28.2°
    atan_table[9]  = 16'd316;    // atan(9/16) ≈ 31.6°
    atan_table[10] = 16'd349;    // atan(10/16) ≈ 34.9°
    atan_table[11] = 16'd382;    // atan(11/16) ≈ 38.2°
    atan_table[12] = 16'd414;    // atan(12/16) ≈ 41.4°
    atan_table[13] = 16'd446;    // atan(13/16) ≈ 44.6°
    atan_table[14] = 16'd477;    // atan(14/16) ≈ 47.7°
    atan_table[15] = 16'd507;    // atan(15/16) ≈ 50.7°
end

//=============================================================================
// 状态机
//=============================================================================
localparam IDLE         = 3'd0;
localparam CALC_ABS     = 3'd1;
localparam CALC_QUAD    = 3'd2;
localparam CALC_ATAN    = 3'd3;
localparam CALC_ANGLE   = 3'd4;
localparam OUTPUT       = 3'd5;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state <= IDLE;
        x_abs <= 16'd0;
        y_abs <= 16'd0;
        quadrant <= 2'd0;
        angle <= 16'd0;
        angle_base <= 16'd0;
        angle_offset <= 16'd0;
        valid_out <= 1'b0;
    end else begin
        case (state)
            IDLE: begin
                valid_out <= 1'b0;
                if (valid_in) begin
                    state <= CALC_ABS;
                end
            end
            
            CALC_ABS: begin
                // 计算绝对值
                x_abs <= (x[15]) ? (~x + 1'b1) : x;
                y_abs <= (y[15]) ? (~y + 1'b1) : y;
                state <= CALC_QUAD;
            end
            
            CALC_QUAD: begin
                // 判断象限
                if (!x[15] && !y[15])       quadrant <= 2'd0;  // 第一象限
                else if (x[15] && !y[15])   quadrant <= 2'd1;  // 第二象限
                else if (x[15] && y[15])    quadrant <= 2'd2;  // 第三象限
                else                        quadrant <= 2'd3;  // 第四象限
                state <= CALC_ATAN;
            end
            
            CALC_ATAN: begin
                // 计算atan角度（第一象限）- 避免除法
                if (x_abs == 0) begin
                    angle_offset <= 16'd900;  // 90度
                end else if (y_abs == 0) begin
                    angle_offset <= 16'd0;    // 0度
                end else if (y_abs <= x_abs) begin
                    // y/x <= 1, 使用比较法查表
                    if (y_abs <= (x_abs >> 4))      // y/x < 1/16
                        angle_offset <= atan_table[0];
                    else if (y_abs <= (x_abs >> 3)) // y/x < 1/8
                        angle_offset <= atan_table[1];
                    else if (y_abs <= (x_abs >> 2)) // y/x < 1/4
                        angle_offset <= atan_table[3];
                    else if (y_abs <= (x_abs >> 1)) // y/x < 1/2
                        angle_offset <= atan_table[7];
                    else if ((y_abs + y_abs + y_abs) <= (x_abs + x_abs + x_abs + x_abs))  // y/x < 3/4
                        angle_offset <= atan_table[11];
                    else
                        angle_offset <= atan_table[15];
                end else begin
                    // y/x > 1, 使用互补角: 90° - atan(x/y)
                    if (x_abs <= (y_abs >> 4))      // x/y < 1/16
                        angle_offset <= 16'd900 - atan_table[0];
                    else if (x_abs <= (y_abs >> 3)) // x/y < 1/8
                        angle_offset <= 16'd900 - atan_table[1];
                    else if (x_abs <= (y_abs >> 2)) // x/y < 1/4
                        angle_offset <= 16'd900 - atan_table[3];
                    else if (x_abs <= (y_abs >> 1)) // x/y < 1/2
                        angle_offset <= 16'd900 - atan_table[7];
                    else if ((x_abs + x_abs + x_abs) <= (y_abs + y_abs + y_abs + y_abs))  // x/y < 3/4
                        angle_offset <= 16'd900 - atan_table[11];
                    else
                        angle_offset <= 16'd900 - atan_table[15];
                end
                state <= CALC_ANGLE;
            end
            
            CALC_ANGLE: begin
                // 根据象限调整角度
                case (quadrant)
                    2'd0: angle <= angle_offset;                    // 第一象限: 0-90°
                    2'd1: angle <= 16'd1800 - angle_offset;        // 第二象限: 90-180°
                    2'd2: angle <= 16'd1800 + angle_offset;        // 第三象限: 180-270°
                    2'd3: angle <= 16'd3600 - angle_offset;        // 第四象限: 270-360°
                endcase
                state <= OUTPUT;
            end
            
            OUTPUT: begin
                valid_out <= 1'b1;
                state <= IDLE;
            end
            
            default: state <= IDLE;
        endcase
    end
end

endmodule
