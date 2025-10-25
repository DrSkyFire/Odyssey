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
    input  wire [12:0]  spectrum_addr,      // 频谱地址（8192点需要13位）
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

// 占空比测量 - 添加流水线
reg [31:0]  high_cnt;                       // 高电平计数
reg [31:0]  total_cnt;                      // 总计数
reg [39:0]  duty_mult_stage1;               // 流水线第1级：乘法
reg [39:0]  duty_mult_stage2;               // 流水线第2级：延迟对齐
reg [15:0]  duty_calc;                      // 流水线第3级：移位除法

// THD测量 - 添加流水线
reg [31:0]  fundamental_power;              // 基波功率
reg [31:0]  harmonic_power;                 // 谐波功率
reg [39:0]  thd_mult_stage1;                // 流水线第1级：乘法
reg [39:0]  thd_mult_stage2;                // 流水线第2级：延迟对齐
reg [15:0]  thd_calc;                       // 流水线第3级：移位除法
reg [3:0]   harmonic_cnt;                   // 谐波计数

// 流水线控制信号
reg         duty_calc_trigger;              // 占空比计算触发
reg         thd_calc_trigger;               // THD计算触发
reg [2:0]   duty_pipe_valid;                // 占空比流水线有效标志
reg [2:0]   thd_pipe_valid;                 // THD流水线有效标志

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
// 3. 占空比测量 - 流水线优化版本
//=============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        high_cnt <= 32'd0;
        total_cnt <= 32'd0;
        duty_calc_trigger <= 1'b0;
    end else if (measure_en) begin
        if (sample_cnt >= MEASURE_TIME) begin
            // 测量周期结束，触发计算
            duty_calc_trigger <= 1'b1;
        end else begin
            duty_calc_trigger <= 1'b0;
            if (sample_valid) begin
                total_cnt <= total_cnt + 1'b1;
                if (sample_data >= 8'd128)
                    high_cnt <= high_cnt + 1'b1;
            end
        end
    end else begin
        high_cnt <= 32'd0;
        total_cnt <= 32'd0;
        duty_calc_trigger <= 1'b0;
    end
end

// 占空比计算 - 3级流水线
// 使用移位近似代替除法：duty = (high * 1024) >> 10 ≈ (high * 1000) / total
// 修正系数：1024/1000 = 1.024，需要补偿
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        duty_mult_stage1 <= 40'd0;
        duty_mult_stage2 <= 40'd0;
        duty_calc <= 16'd0;
        duty_pipe_valid <= 3'd0;
    end else begin
        // 流水线第1级：乘法 (high_cnt * 1024)
        if (duty_calc_trigger && total_cnt != 0) begin
            duty_mult_stage1 <= high_cnt << 10;  // 乘以1024
            duty_pipe_valid[0] <= 1'b1;
        end else begin
            duty_pipe_valid[0] <= 1'b0;
        end
        
        // 流水线第2级：保存乘法结果，准备除法
        duty_mult_stage2 <= duty_mult_stage1;
        duty_pipe_valid[1] <= duty_pipe_valid[0];
        
        // 流水线第3级：近似除法（使用移位）
        // duty ≈ (high * 1024) / total_cnt
        // 为了接近1000倍，再乘以1000/1024 ≈ 0.9765625
        // 简化：直接用 (high * 1024) / total 然后调整
        duty_pipe_valid[2] <= duty_pipe_valid[1];
        if (duty_pipe_valid[1]) begin
            // 使用多级移位近似除法
            if (total_cnt >= (1 << 20))
                duty_calc <= duty_mult_stage2[39:24];      // 除以 2^24
            else if (total_cnt >= (1 << 19))
                duty_calc <= duty_mult_stage2[38:23];      // 除以 2^23
            else if (total_cnt >= (1 << 18))
                duty_calc <= duty_mult_stage2[37:22];      // 除以 2^22
            else if (total_cnt >= (1 << 17))
                duty_calc <= duty_mult_stage2[36:21];      // 除以 2^21
            else if (total_cnt >= (1 << 16))
                duty_calc <= duty_mult_stage2[35:20];      // 除以 2^20
            else if (total_cnt >= (1 << 15))
                duty_calc <= duty_mult_stage2[34:19];      // 除以 2^19
            else if (total_cnt >= (1 << 14))
                duty_calc <= duty_mult_stage2[33:18];      // 除以 2^18
            else if (total_cnt >= (1 << 13))
                duty_calc <= duty_mult_stage2[32:17];      // 除以 2^17
            else if (total_cnt >= (1 << 12))
                duty_calc <= duty_mult_stage2[31:16];      // 除以 2^16
            else if (total_cnt >= (1 << 11))
                duty_calc <= duty_mult_stage2[30:15];      // 除以 2^15
            else
                duty_calc <= duty_mult_stage2[29:14];      // 除以 2^14
        end
    end
end

//=============================================================================
// 4. THD测量 - 基于FFT频谱，流水线优化版本
// THD = sqrt(P2^2 + P3^2 + ... + Pn^2) / P1
// 简化计算: THD ≈ (P2 + P3 + ... + Pn) / P1
//=============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        fundamental_power <= 32'd0;
        harmonic_power <= 32'd0;
        harmonic_cnt <= 4'd0;
        thd_calc_trigger <= 1'b0;
    end else if (spectrum_valid && measure_en) begin
        // 假设基波在第10个频点（可根据实际调整）
        if (spectrum_addr == 10'd10) begin
            fundamental_power <= {16'd0, spectrum_data};
            harmonic_power <= 32'd0;
            harmonic_cnt <= 4'd0;
            thd_calc_trigger <= 1'b0;
        end
        // 收集2~10次谐波（频点20, 30, 40, ..., 100）
        else if (spectrum_addr == 10'd20 || spectrum_addr == 10'd30 ||
                 spectrum_addr == 10'd40 || spectrum_addr == 10'd50 ||
                 spectrum_addr == 10'd60 || spectrum_addr == 10'd70 ||
                 spectrum_addr == 10'd80 || spectrum_addr == 10'd90 ||
                 spectrum_addr == 10'd100) begin
            harmonic_power <= harmonic_power + {16'd0, spectrum_data};
            harmonic_cnt <= harmonic_cnt + 1'b1;
            if (harmonic_cnt == 4'd8)  // 即将收集完
                thd_calc_trigger <= 1'b1;
            else
                thd_calc_trigger <= 1'b0;
        end else begin
            thd_calc_trigger <= 1'b0;
        end
    end else begin
        thd_calc_trigger <= 1'b0;
    end
end

// THD计算 - 3级流水线，使用移位近似除法
// THD = (harmonic * 1024) / fundamental，然后调整到1000倍
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        thd_mult_stage1 <= 40'd0;
        thd_mult_stage2 <= 40'd0;
        thd_calc <= 16'd0;
        thd_pipe_valid <= 3'd0;
    end else begin
        // 流水线第1级：乘法 (harmonic_power * 1024)
        if (thd_calc_trigger && fundamental_power != 0) begin
            thd_mult_stage1 <= harmonic_power << 10;  // 乘以1024
            thd_pipe_valid[0] <= 1'b1;
        end else begin
            thd_pipe_valid[0] <= 1'b0;
        end
        
        // 流水线第2级：保存乘法结果
        thd_mult_stage2 <= thd_mult_stage1;
        thd_pipe_valid[1] <= thd_pipe_valid[0];
        
        // 流水线第3级：近似除法（使用移位）
        thd_pipe_valid[2] <= thd_pipe_valid[1];
        if (thd_pipe_valid[1]) begin
            // 根据fundamental_power的大小选择合适的移位量
            if (fundamental_power >= (1 << 20))
                thd_calc <= thd_mult_stage2[39:24];
            else if (fundamental_power >= (1 << 19))
                thd_calc <= thd_mult_stage2[38:23];
            else if (fundamental_power >= (1 << 18))
                thd_calc <= thd_mult_stage2[37:22];
            else if (fundamental_power >= (1 << 17))
                thd_calc <= thd_mult_stage2[36:21];
            else if (fundamental_power >= (1 << 16))
                thd_calc <= thd_mult_stage2[35:20];
            else if (fundamental_power >= (1 << 15))
                thd_calc <= thd_mult_stage2[34:19];
            else if (fundamental_power >= (1 << 14))
                thd_calc <= thd_mult_stage2[33:18];
            else if (fundamental_power >= (1 << 13))
                thd_calc <= thd_mult_stage2[32:17];
            else if (fundamental_power >= (1 << 12))
                thd_calc <= thd_mult_stage2[31:16];
            else if (fundamental_power >= (1 << 11))
                thd_calc <= thd_mult_stage2[30:15];
            else
                thd_calc <= thd_mult_stage2[29:14];
        end
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