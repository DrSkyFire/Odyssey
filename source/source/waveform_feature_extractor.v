//=============================================================================
// 文件名: waveform_feature_extractor.v
// 描述: 波形特征提取器 - AI信号识别的特征工程模块
// 功能: 并行计算多个波形特征用于信号分类
//   1. 过零率 (Zero Crossing Rate, ZCR)
//   2. 峰值因子 (Crest Factor)
//   3. 波形因子 (Form Factor)
//   4. 平均值 (Mean)
//   5. 标准差近似 (Variance Approximation)
//   6. 谐波失真度 (THD from FFT)
//   7. 频谱质心 (Spectral Centroid)
//   8. 频谱展宽 (Spectral Spread)
//=============================================================================

module waveform_feature_extractor #(
    parameter DATA_WIDTH = 11,          // 输入数据位宽
    parameter WINDOW_SIZE = 1024,       // 分析窗口大小
    parameter FFT_BINS = 512            // FFT频率点数
)(
    input  wire                         clk,
    input  wire                         rst_n,
    
    // 时域信号输入
    input  wire signed [DATA_WIDTH-1:0] signal_in,
    input  wire                         signal_valid,
    
    // FFT频谱输入（用于频域特征）
    input  wire [15:0]                  fft_magnitude,    // FFT幅度谱
    input  wire [9:0]                   fft_bin_index,    // FFT频点索引
    input  wire                         fft_valid,
    
    // 特征输出
    output reg [15:0]                   zcr,              // 过零率 (0-65535)
    output reg [15:0]                   crest_factor,     // 峰值因子 (定点Q8.8)
    output reg [15:0]                   form_factor,      // 波形因子 (定点Q8.8)
    output reg signed [15:0]            mean_value,       // 平均值
    output reg [15:0]                   std_dev,          // 标准差
    output reg [15:0]                   thd,              // 总谐波失真 (0-100%)
    output reg [15:0]                   spectral_centroid, // 频谱质心 (Hz)
    output reg [15:0]                   spectral_spread,  // 频谱展宽
    output reg                          features_valid    // 特征有效标志
);

//=============================================================================
// 1. 时域特征计算状态机
//=============================================================================
localparam IDLE       = 3'd0;
localparam COLLECTING = 3'd1;
localparam COMPUTE1   = 3'd2;  // 计算阶段1: 准备数据
localparam COMPUTE2   = 3'd3;  // 计算阶段2: 乘法运算 + LUT查询
localparam COMPUTE3   = 3'd4;  // 计算阶段3: 倒数插值 (时序优化:分2拍)
localparam COMPUTE4   = 3'd5;  // 计算阶段4: 最终乘法(替代除法)
localparam OUTPUT     = 3'd6;  // 输出阶段

reg [2:0] state;
reg [10:0] sample_cnt;  // 样本计数器
reg compute3_step;      // ⚠️ 时序优化: COMPUTE3子状态 (0=计算delta, 1=计算插值)

//=============================================================================
// 流水线寄存器 (用于查找表除法优化 - 4级流水线)
//=============================================================================
reg [23:0] thd_mult_result;      // THD 最终结果
reg [15:0] thd_divisor;          // THD 除数
reg [15:0] crest_div_result;     // 峰值因子结果
reg [15:0] form_div_result;      // 波形因子结果
reg [15:0] centroid_div_result;  // 频谱质心结果

// 倒数查找表查询结果 (COMPUTE2 → COMPUTE3 流水线)
reg [15:0] thd_recip_base, thd_recip_next;
reg [7:0]  thd_offset;
reg [23:0] thd_mult_pipe;

reg [15:0] crest_recip_base, crest_recip_next;
reg [7:0]  crest_offset;
reg [23:0] crest_mult_pipe;

reg [15:0] form_recip_base, form_recip_next;
reg [7:0]  form_offset;
reg [23:0] form_mult_pipe;

reg [15:0] centroid_recip_base, centroid_recip_next;
reg [7:0]  centroid_offset;
reg [31:0] centroid_mult_pipe;

// ⚠️ 时序优化：插值计算中间结果 (COMPUTE3_STEP1 → COMPUTE3_STEP2)
reg [15:0] thd_delta;          // thd_recip_next - thd_recip_base
reg [15:0] crest_delta;
reg [15:0] form_delta;
reg [15:0] centroid_delta;

// 插值结果 (COMPUTE3 → COMPUTE4 流水线)
reg [15:0] thd_recip_interp_reg;
reg [15:0] crest_recip_interp_reg;
reg [15:0] form_recip_interp_reg;
reg [15:0] centroid_recip_interp_reg;

// 被除数传递 (COMPUTE3 → COMPUTE4)
reg [23:0] thd_dividend_pipe;
reg [23:0] crest_dividend_pipe;
reg [23:0] form_dividend_pipe;
reg [31:0] centroid_dividend_pipe;

// 除数保存 (用于零除判断)
reg [15:0] thd_divisor_pipe;
reg [15:0] crest_divisor_pipe;
reg [15:0] form_divisor_pipe;
reg [15:0] centroid_divisor_pipe;

// 中间值寄存器 (COMPUTE1 → COMPUTE2, 用于LUT输入)
reg [15:0] rms_value_reg;
reg [15:0] avg_abs_value_reg;
reg [15:0] fft_sum_mag_reg;

//=============================================================================
// 2. 过零率计算 (Zero Crossing Rate)
//=============================================================================
reg signed [DATA_WIDTH-1:0] signal_prev;
reg [15:0] zero_cross_cnt;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        signal_prev    <= 0;
        zero_cross_cnt <= 0;
    end else if (signal_valid) begin
        signal_prev <= signal_in;
        // 检测符号变化
        if ((signal_prev[DATA_WIDTH-1] != signal_in[DATA_WIDTH-1]) && 
            (state == COLLECTING))
            zero_cross_cnt <= zero_cross_cnt + 1'b1;
        else if (state == IDLE)
            zero_cross_cnt <= 0;
    end
end

//=============================================================================
// 3. 峰值和RMS计算
//=============================================================================
reg signed [DATA_WIDTH-1:0] peak_max;
reg signed [DATA_WIDTH-1:0] peak_min;
reg signed [31:0]           sum_abs;      // 绝对值累加
reg signed [31:0]           sum_square;   // 平方和累加

wire [DATA_WIDTH-1:0] abs_signal;
assign abs_signal = (signal_in[DATA_WIDTH-1]) ? -signal_in : signal_in;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        peak_max   <= {1'b1, {(DATA_WIDTH-1){1'b0}}};  // 最小负数
        peak_min   <= {1'b0, {(DATA_WIDTH-1){1'b1}}};  // 最大正数
        sum_abs    <= 0;
        sum_square <= 0;
    end else if (signal_valid && state == COLLECTING) begin
        // 更新峰值
        if (signal_in > peak_max) peak_max <= signal_in;
        if (signal_in < peak_min) peak_min <= signal_in;
        
        // 累加绝对值
        sum_abs <= sum_abs + abs_signal;
        
        // 累加平方（用于RMS）
        sum_square <= sum_square + (signal_in * signal_in);
    end else if (state == IDLE) begin
        peak_max   <= {1'b1, {(DATA_WIDTH-1){1'b0}}};
        peak_min   <= {1'b0, {(DATA_WIDTH-1){1'b1}}};
        sum_abs    <= 0;
        sum_square <= 0;
    end
end

//=============================================================================
// 4. 平均值计算
//=============================================================================
reg signed [31:0] sum_signal;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        sum_signal <= 0;
    end else if (signal_valid && state == COLLECTING) begin
        sum_signal <= sum_signal + signal_in;
    end else if (state == IDLE) begin
        sum_signal <= 0;
    end
end

//=============================================================================
// 5. 频域特征计算（FFT后处理）
//=============================================================================
reg [31:0] fft_sum_mag;          // 总能量
reg [31:0] fft_weighted_sum;     // 加权求和（质心）
reg [15:0] fft_fundamental;      // 基波幅度
reg [31:0] fft_harmonic_sum;     // 谐波能量和
reg [9:0]  fundamental_bin;      // 基波频点
reg [9:0]  fundamental_bin_reg;  // 基波频点寄存器（延迟一拍用于谐波检测）

// 寻找基波（最大幅度）
reg [15:0] max_magnitude;
reg [9:0]  max_bin_index;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        fft_sum_mag         <= 0;
        fft_weighted_sum    <= 0;
        fft_fundamental     <= 0;
        fft_harmonic_sum    <= 0;
        max_magnitude       <= 0;
        max_bin_index       <= 0;
        fundamental_bin     <= 0;
        fundamental_bin_reg <= 0;
    end else if (fft_valid) begin
        // 累加总能量
        fft_sum_mag <= fft_sum_mag + fft_magnitude;
        
        // 加权求和（频率×幅度）
        fft_weighted_sum <= fft_weighted_sum + (fft_bin_index * fft_magnitude);
        
        // 寻找最大值（基波）
        if (fft_magnitude > max_magnitude && fft_bin_index > 0) begin  // 排除直流分量
            max_magnitude <= fft_magnitude;
            max_bin_index <= fft_bin_index;
        end
        
        // FFT结束时保存基波信息
        if (fft_bin_index == FFT_BINS - 1) begin
            fft_fundamental     <= max_magnitude;
            fundamental_bin     <= max_bin_index;
            fundamental_bin_reg <= max_bin_index;  // 保存用于下一轮谐波检测
            max_magnitude       <= 0;  // 重置
        end
        
        // 谐波检测（基波的整数倍频率）- 使用上一轮的fundamental_bin_reg
        if (fundamental_bin_reg != 0) begin
            // 检测2-5次谐波
            if ((fft_bin_index >= (fundamental_bin_reg << 1) - 2) && 
                (fft_bin_index <= (fundamental_bin_reg << 1) + 2))  // 2次谐波±2
                fft_harmonic_sum <= fft_harmonic_sum + fft_magnitude;
            else if ((fft_bin_index >= (fundamental_bin_reg * 3) - 2) && 
                     (fft_bin_index <= (fundamental_bin_reg * 3) + 2))  // 3次谐波
                fft_harmonic_sum <= fft_harmonic_sum + fft_magnitude;
            else if ((fft_bin_index >= (fundamental_bin_reg << 2) - 2) && 
                     (fft_bin_index <= (fundamental_bin_reg << 2) + 2))  // 4次谐波
                fft_harmonic_sum <= fft_harmonic_sum + fft_magnitude;
            else if ((fft_bin_index >= (fundamental_bin_reg * 5) - 2) && 
                     (fft_bin_index <= (fundamental_bin_reg * 5) + 2))  // 5次谐波
                fft_harmonic_sum <= fft_harmonic_sum + fft_magnitude;
        end
    end else if (state == IDLE) begin
        fft_sum_mag         <= 0;
        fft_weighted_sum    <= 0;
        fft_harmonic_sum    <= 0;
        max_magnitude       <= 0;
        fundamental_bin_reg <= 0;
    end
end

//=============================================================================
// 倒数查找表模块实例化 (用于高精度除法近似)
//=============================================================================
// THD 除法查表
wire [15:0] thd_recip_base_wire, thd_recip_next_wire;
reciprocal_lut u_thd_recip_lut (
    .divisor    (thd_divisor),
    .recip_base (thd_recip_base_wire),
    .recip_next (thd_recip_next_wire)
);

// Crest Factor 除法查表
wire [15:0] crest_recip_base_wire, crest_recip_next_wire;
reciprocal_lut u_crest_recip_lut (
    .divisor    (rms_value_reg),
    .recip_base (crest_recip_base_wire),
    .recip_next (crest_recip_next_wire)
);

// Form Factor 除法查表
wire [15:0] form_recip_base_wire, form_recip_next_wire;
reciprocal_lut u_form_recip_lut (
    .divisor    (avg_abs_value_reg),
    .recip_base (form_recip_base_wire),
    .recip_next (form_recip_next_wire)
);

// Spectral Centroid 除法查表
wire [15:0] centroid_recip_base_wire, centroid_recip_next_wire;
reciprocal_lut u_centroid_recip_lut (
    .divisor    (fft_sum_mag_reg),
    .recip_base (centroid_recip_base_wire),
    .recip_next (centroid_recip_next_wire)
);

//=============================================================================
// 6. 状态机 - 控制特征计算流程（流水线化）
//=============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state       <= IDLE;
        sample_cnt  <= 0;
    end else begin
        case (state)
            IDLE: begin
                if (signal_valid) begin
                    state      <= COLLECTING;
                    sample_cnt <= 1;
                end
            end
            
            COLLECTING: begin
                if (signal_valid) begin
                    if (sample_cnt >= WINDOW_SIZE - 1) begin
                        state      <= COMPUTE1;  // 进入流水线第1阶段
                        sample_cnt <= 0;
                    end else begin
                        sample_cnt <= sample_cnt + 1'b1;
                    end
                end
            end
            
            COMPUTE1: begin
                // 第1阶段: 准备中间变量，简单运算
                state <= COMPUTE2;
            end
            
            COMPUTE2: begin
                // 第2阶段: 乘法运算 + LUT查询
                state <= COMPUTE3;
            end
            
            COMPUTE3: begin
                // 第3阶段: 倒数插值
                state <= COMPUTE4;
            end
            
            COMPUTE4: begin
                // 第4阶段: 最终乘法(替代除法)
                state <= OUTPUT;
            end
            
            OUTPUT: begin
                // 输出特征
                state <= IDLE;
            end
            
            default: state <= IDLE;
        endcase
    end
end

//=============================================================================
// 7. 特征值计算和输出（流水线化优化）
//=============================================================================
wire [15:0] peak_to_peak;
wire [31:0] rms_value;
wire [31:0] avg_abs_value;

assign peak_to_peak  = peak_max - peak_min;
assign rms_value     = sum_square >> 10;  // 除以1024（近似）
assign avg_abs_value = sum_abs >> 10;

// 流水线阶段1: 准备中间变量
reg [15:0] peak_to_peak_reg;
// 注：rms_value_reg, avg_abs_value_reg, fft_sum_mag_reg 已在前面声明（用于LUT输入）
reg [15:0] fft_fundamental_reg;
reg [15:0] fft_harmonic_sum_reg;
reg [31:0] fft_weighted_sum_reg;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        peak_to_peak_reg    <= 0;
        rms_value_reg       <= 0;
        avg_abs_value_reg   <= 0;
        fft_sum_mag_reg     <= 0;
        fft_fundamental_reg <= 0;
        fft_harmonic_sum_reg <= 0;
        fft_weighted_sum_reg <= 0;
    end else if (state == COMPUTE1) begin
        // 保存中间结果到寄存器
        peak_to_peak_reg    <= peak_to_peak;
        rms_value_reg       <= rms_value[15:0];
        avg_abs_value_reg   <= avg_abs_value[15:0];
        fft_sum_mag_reg     <= fft_sum_mag[15:0];
        fft_fundamental_reg <= fft_fundamental;
        fft_harmonic_sum_reg <= fft_harmonic_sum[15:0];
        fft_weighted_sum_reg <= fft_weighted_sum;
    end
end

// 流水线阶段2: 乘法运算 + 查表准备
reg [23:0] thd_mult;
reg [23:0] crest_mult;
reg [23:0] form_mult;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        thd_mult   <= 0;
        crest_mult <= 0;
        form_mult  <= 0;
        thd_divisor <= 0;
        
        // 倒数查表结果寄存
        thd_recip_base <= 0;
        thd_recip_next <= 0;
        thd_offset <= 0;
        thd_mult_pipe <= 0;
        
        crest_recip_base <= 0;
        crest_recip_next <= 0;
        crest_offset <= 0;
        crest_mult_pipe <= 0;
        
        form_recip_base <= 0;
        form_recip_next <= 0;
        form_offset <= 0;
        form_mult_pipe <= 0;
        
        centroid_recip_base <= 0;
        centroid_recip_next <= 0;
        centroid_offset <= 0;
        centroid_mult_pipe <= 0;
    end else if (state == COMPUTE2) begin
        // THD 乘法: (谐波能量 × 100)
        thd_mult    <= fft_harmonic_sum_reg * 8'd100;
        thd_divisor <= fft_fundamental_reg;
        
        // THD 倒数查表 + 保存插值参数
        thd_recip_base <= thd_recip_base_wire;
        thd_recip_next <= thd_recip_next_wire;
        thd_offset     <= fft_fundamental_reg[7:0];
        thd_mult_pipe  <= fft_harmonic_sum_reg * 8'd100; // 流水线传递被除数
        
        // 峰值因子乘法: (Peak × 256)
        crest_mult  <= peak_to_peak_reg << 8;
        
        // Crest 倒数查表
        crest_recip_base <= crest_recip_base_wire;
        crest_recip_next <= crest_recip_next_wire;
        crest_offset     <= rms_value_reg[7:0];
        crest_mult_pipe  <= peak_to_peak_reg << 8;
        
        // 波形因子乘法: (RMS × 256)
        form_mult   <= rms_value_reg << 8;
        
        // Form 倒数查表
        form_recip_base <= form_recip_base_wire;
        form_recip_next <= form_recip_next_wire;
        form_offset     <= avg_abs_value_reg[7:0];
        form_mult_pipe  <= rms_value_reg << 8;
        
        // Centroid 倒数查表
        centroid_recip_base <= centroid_recip_base_wire;
        centroid_recip_next <= centroid_recip_next_wire;
        centroid_offset     <= fft_sum_mag_reg[7:0];
        centroid_mult_pipe  <= fft_weighted_sum_reg;
    end
end

// 流水线阶段3: 倒数插值计算 (时序优化:分2拍执行，打断组合逻辑链)
// Step 1: 计算差值 delta = recip_next - recip_base
// Step 2: 插值计算 result = base + (delta * offset) >>> 8

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        thd_delta <= 0;
        crest_delta <= 0;
        form_delta <= 0;
        centroid_delta <= 0;
        
        thd_recip_interp_reg <= 0;
        crest_recip_interp_reg <= 0;
        form_recip_interp_reg <= 0;
        centroid_recip_interp_reg <= 0;
        
        thd_dividend_pipe <= 0;
        crest_dividend_pipe <= 0;
        form_dividend_pipe <= 0;
        centroid_dividend_pipe <= 0;
        
        thd_divisor_pipe <= 0;
        crest_divisor_pipe <= 0;
        form_divisor_pipe <= 0;
        centroid_divisor_pipe <= 0;
        
        compute3_step <= 0;
    end else if (state == COMPUTE3) begin
        if (!compute3_step) begin
            // Step 1: 计算差值 (减法，约3-4层逻辑)
            thd_delta <= thd_recip_next - thd_recip_base;
            crest_delta <= crest_recip_next - crest_recip_base;
            form_delta <= form_recip_next - form_recip_base;
            centroid_delta <= centroid_recip_next - centroid_recip_base;
            compute3_step <= 1;  // 下一拍进入Step 2
        end else begin
            // Step 2: 插值计算 (乘法+移位+加法，约6-7层逻辑)
            thd_recip_interp_reg <= thd_recip_base + ((thd_delta * thd_offset) >>> 8);
            crest_recip_interp_reg <= crest_recip_base + ((crest_delta * crest_offset) >>> 8);
            form_recip_interp_reg <= form_recip_base + ((form_delta * form_offset) >>> 8);
            centroid_recip_interp_reg <= centroid_recip_base + ((centroid_delta * centroid_offset) >>> 8);
            
            // 传递被除数和除数到下一级
            thd_dividend_pipe <= thd_mult_pipe;
            thd_divisor_pipe <= thd_divisor;
            crest_dividend_pipe <= crest_mult_pipe;
            crest_divisor_pipe <= rms_value_reg;
            form_dividend_pipe <= form_mult_pipe;
            form_divisor_pipe <= avg_abs_value_reg;
            centroid_dividend_pipe <= centroid_mult_pipe;
            centroid_divisor_pipe <= fft_sum_mag_reg;
            
            compute3_step <= 0;  // 复位子状态
        end
    end else begin
        compute3_step <= 0;
    end
end

// 流水线阶段4: 最终乘法 (dividend * reciprocal)
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        thd_mult_result      <= 0;
        crest_div_result     <= 0;
        form_div_result      <= 0;
        centroid_div_result  <= 0;
    end else if (state == COMPUTE4) begin
        // THD 除法: dividend / divisor = dividend * reciprocal
        if (thd_divisor_pipe != 0) begin
            thd_mult_result <= (thd_dividend_pipe * thd_recip_interp_reg) >>> 15;
        end else
            thd_mult_result <= 0;
        
        // Crest Factor 除法
        if (crest_divisor_pipe != 0) begin
            crest_div_result <= (crest_dividend_pipe[15:0] * crest_recip_interp_reg) >>> 15;
        end else
            crest_div_result <= 16'hFFFF;
        
        // Form Factor 除法
        if (form_divisor_pipe != 0) begin
            form_div_result <= (form_dividend_pipe[15:0] * form_recip_interp_reg) >>> 15;
        end else
            form_div_result <= 16'h0100;
        
        // Spectral Centroid 除法
        if (centroid_divisor_pipe != 0) begin
            centroid_div_result <= (centroid_dividend_pipe[15:0] * centroid_recip_interp_reg) >>> 15;
        end else
            centroid_div_result <= 0;
    end
end

// 特征输出寄存器（阶段4：OUTPUT）
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        zcr              <= 0;
        crest_factor     <= 0;
        form_factor      <= 0;
        mean_value       <= 0;
        std_dev          <= 0;
        thd              <= 0;
        spectral_centroid <= 0;
        spectral_spread  <= 0;
        features_valid   <= 1'b0;
    end else if (state == OUTPUT) begin
        // 1. 过零率（归一化到0-65535）
        zcr <= (zero_cross_cnt << 6);  // 简单缩放
        
        // 2. 峰值因子 = Peak / RMS (Q8.8定点数) - 使用流水线结果
        crest_factor <= crest_div_result;
        
        // 3. 波形因子 = RMS / Average (Q8.8定点数) - 使用流水线结果
        form_factor <= form_div_result;
        
        // 4. 平均值
        mean_value <= sum_signal[25:10];  // 除以1024
        
        // 5. 标准差（简化版：使用RMS作为近似）
        std_dev <= rms_value_reg;
        
        // 6. THD - 使用流水线结果
        thd <= thd_mult_result[15:0];
        
        // 7. 频谱质心 - 使用流水线结果
        spectral_centroid <= centroid_div_result;
        
        // 8. 频谱展宽（简化版：使用基波位置）
        spectral_spread <= fundamental_bin << 4;  // 简单缩放
        
        features_valid <= 1'b1;
    end else begin
        features_valid <= 1'b0;
    end
end

endmodule
