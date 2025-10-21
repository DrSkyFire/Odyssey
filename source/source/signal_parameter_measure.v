//=============================================================================
// 文件名: signal_parameter_measure.v
// 描述: 信号参数测量模块
// 功能: 
//   1. 频率测量 - 基于过零检测
//   2. 幅度测量 - 峰峰值检测
//   3. 占空比测量 - 高电平时间比例
//   4. THD测量 - 基于FFT频谱数据
//=============================================================================

module signal_parameter_measure (
    input  wire         clk,                // 系统时钟 100MHz
    input  wire         rst_n,
    
    // 时域数据输入 (用于频率、幅度、占空比测量)
    input  wire         sample_clk,         // 采样时钟 1MHz
    input  wire [7:0]   sample_data,        // 采样数据
    input  wire         sample_valid,       // 采样有效
    
    // 频域数据输入 (用于THD测量)
    input  wire [15:0]  spectrum_data,      // 频谱幅度
    input  wire [9:0]   spectrum_addr,      // 频谱地址
    input  wire         spectrum_valid,     // 频谱有效
    
    // 参数输出
    output reg  [15:0]  freq_out,           // 频率 (Hz)
    output reg  [15:0]  amplitude_out,      // 幅度 (峰峰值)
    output reg  [15:0]  duty_out,           // 占空比 (0~1000 表示0%~100%)
    output reg  [15:0]  thd_out,            // THD (0~1000 表示0%~100%)
    
    // 控制
    input  wire         measure_en          // 测量使能
);

//=============================================================================
// 参数定义
//=============================================================================
localparam SAMPLE_RATE = 1_000_000;         // 采样率 1MHz
localparam MEASURE_TIME = 1_000_000;        // 测量周期 1秒

//=============================================================================
// 信号定义
//=============================================================================
// 频率测量
reg [7:0]   data_d1, data_d2;
reg         zero_cross;                     // 过零标志
reg [31:0]  zero_cross_cnt;                 // 过零计数
reg [31:0]  sample_cnt;                     // 采样计数
reg [15:0]  freq_calc;

// 幅度测量
reg [7:0]   max_val;
reg [7:0]   min_val;
reg [15:0]  amplitude_calc;

// 占空比测量
reg [31:0]  high_cnt;                       // 高电平计数
reg [31:0]  total_cnt;                      // 总计数
reg [15:0]  duty_calc;

// THD测量
reg [31:0]  fundamental_power;              // 基波功率
reg [31:0]  harmonic_power;                 // 谐波功率
reg [15:0]  thd_calc;
reg [3:0]   harmonic_cnt;                   // 谐波计数

//=============================================================================
// 采样数据同步到系统时钟域
//=============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        data_d1 <= 8'd0;
        data_d2 <= 8'd0;
    end else if (sample_valid) begin
        data_d1 <= sample_data;
        data_d2 <= data_d1;
    end
end

//=============================================================================
// 1. 频率测量 - 过零检测法
//=============================================================================
// 检测过零点（从低到高）
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        zero_cross <= 1'b0;
    else if (sample_valid)
        zero_cross <= (data_d2 < 8'd128) && (data_d1 >= 8'd128);
    else
        zero_cross <= 1'b0;
end

// 过零计数和采样计数
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        zero_cross_cnt <= 32'd0;
        sample_cnt <= 32'd0;
    end else if (measure_en) begin
        if (sample_cnt >= MEASURE_TIME) begin
            // 测量周期结束，重新开始
            zero_cross_cnt <= 32'd0;
            sample_cnt <= 32'd0;
        end else begin
            if (sample_valid)
                sample_cnt <= sample_cnt + 1'b1;
            if (zero_cross)
                zero_cross_cnt <= zero_cross_cnt + 1'b1;
        end
    end else begin
        zero_cross_cnt <= 32'd0;
        sample_cnt <= 32'd0;
    end
end

// 频率计算
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        freq_calc <= 16'd0;
    else if (sample_cnt >= MEASURE_TIME)
        freq_calc <= zero_cross_cnt[15:0];  // 过零次数 = 频率(Hz)
end

//=============================================================================
// 2. 幅度测量 - 峰峰值检测
//=============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        max_val <= 8'd0;
        min_val <= 8'd255;
    end else if (measure_en) begin
        if (sample_cnt >= MEASURE_TIME) begin
            // 测量周期结束，重新开始
            max_val <= 8'd0;
            min_val <= 8'd255;
        end else if (sample_valid) begin
            if (sample_data > max_val)
                max_val <= sample_data;
            if (sample_data < min_val)
                min_val <= sample_data;
        end
    end else begin
        max_val <= 8'd0;
        min_val <= 8'd255;
    end
end

// 幅度计算（峰峰值）
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        amplitude_calc <= 16'd0;
    else if (sample_cnt >= MEASURE_TIME)
        amplitude_calc <= {8'd0, max_val} - {8'd0, min_val};
end

//=============================================================================
// 3. 占空比测量
//=============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        high_cnt <= 32'd0;
        total_cnt <= 32'd0;
    end else if (measure_en) begin
        if (sample_cnt >= MEASURE_TIME) begin
            // 测量周期结束，重新开始
            high_cnt <= 32'd0;
            total_cnt <= 32'd0;
        end else if (sample_valid) begin
            total_cnt <= total_cnt + 1'b1;
            if (sample_data >= 8'd128)
                high_cnt <= high_cnt + 1'b1;
        end
    end else begin
        high_cnt <= 32'd0;
        total_cnt <= 32'd0;
    end
end

// 占空比计算 (0~1000 表示 0%~100%)
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        duty_calc <= 16'd0;
    else if (sample_cnt >= MEASURE_TIME) begin
        if (total_cnt != 0)
            duty_calc <= (high_cnt * 1000) / total_cnt;
        else
            duty_calc <= 16'd0;
    end
end

//=============================================================================
// 4. THD测量 - 基于FFT频谱
// THD = sqrt(P2^2 + P3^2 + ... + Pn^2) / P1
// 简化计算: THD ≈ (P2 + P3 + ... + Pn) / P1
//=============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        fundamental_power <= 32'd0;
        harmonic_power <= 32'd0;
        harmonic_cnt <= 4'd0;
    end else if (spectrum_valid && measure_en) begin
        // 假设基波在第10个频点（可根据实际调整）
        if (spectrum_addr == 10'd10) begin
            fundamental_power <= {16'd0, spectrum_data};
            harmonic_power <= 32'd0;
            harmonic_cnt <= 4'd0;
        end
        // 收集2~10次谐波（频点20, 30, 40, ..., 100）
        else if (spectrum_addr == 10'd20 || spectrum_addr == 10'd30 ||
                 spectrum_addr == 10'd40 || spectrum_addr == 10'd50 ||
                 spectrum_addr == 10'd60 || spectrum_addr == 10'd70 ||
                 spectrum_addr == 10'd80 || spectrum_addr == 10'd90 ||
                 spectrum_addr == 10'd100) begin
            harmonic_power <= harmonic_power + {16'd0, spectrum_data};
            harmonic_cnt <= harmonic_cnt + 1'b1;
        end
    end
end

// THD计算 (0~1000 表示 0%~100%)
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        thd_calc <= 16'd0;
    else if (harmonic_cnt == 4'd9) begin  // 收集完所有谐波
        if (fundamental_power != 0)
            thd_calc <= (harmonic_power * 1000) / fundamental_power;
        else
            thd_calc <= 16'd0;
    end
end

//=============================================================================
// 输出寄存器
//=============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        freq_out <= 16'd0;
        amplitude_out <= 16'd0;
        duty_out <= 16'd0;
        thd_out <= 16'd0;
    end else if (measure_en) begin
        freq_out <= freq_calc;
        amplitude_out <= amplitude_calc;
        duty_out <= duty_calc;
        thd_out <= thd_calc;
    end
end

endmodule