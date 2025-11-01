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
    input  wire         sample_clk,         // 采样时钟 35MHz
    input  wire [7:0]   sample_data,        // 采样数据
    input  wire         sample_valid,       // 采样有效
    
    // 频域数据输入 (用于THD测量)
    input  wire [15:0]  spectrum_data,      // 频谱幅度
    input  wire [12:0]  spectrum_addr,      // 频谱地址（8192点需要13位）
    input  wire         spectrum_valid,     // 频谱有效
    
    // 参数输出
    output reg  [15:0]  freq_out,           // 频率数值
    output reg          freq_is_khz,        // 频率单位标志 (0=Hz, 1=kHz)
    output reg  [15:0]  amplitude_out,      // 幅度 (峰峰值)
    output reg  [15:0]  duty_out,           // 占空比 (0~1000 表示0%~100%)
    output reg  [15:0]  thd_out,            // THD (0~1000 表示0%~100%)
    
    // 控制
    input  wire         measure_en          // 测量使能
);

//=============================================================================
// 参数定义
//=============================================================================
localparam SAMPLE_RATE = 35_000_000;        // 采样率 35MHz (实际ADC采样率)
localparam MEASURE_TIME = 35_000_000;       // 测量周期：35M个sample_valid
localparam TIME_1SEC = 100_000_000;         // 【新增】1秒的100MHz时钟周期数

//=============================================================================
// 信号定义
//=============================================================================
// 【新增】固定时间计数器（避免CDC导致的测量周期不稳定）
reg [31:0]  time_cnt;                       // 基于100MHz的时间计数
reg         measure_done;                   // 测量周期结束标志

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
reg [31:0]  high_cnt_latch;                 // 锁存的高电平计数
reg [31:0]  total_cnt_latch;                // 锁存的总计数
reg         duty_calc_trigger;              // 占空比计算触发
reg [15:0]  duty_calc;                      // 占空比计算结果

// THD测量 - 添加流水线
reg [31:0]  fundamental_power;              // 基波功率
reg [31:0]  harmonic_power;                 // 谐波功率
reg [39:0]  thd_mult_stage1;                // 流水线第1级：乘法
reg [39:0]  thd_mult_stage2;                // 流水线第2级：延迟对齐
reg [15:0]  thd_calc;                       // 流水线第3级：移位除法
reg [3:0]   harmonic_cnt;                   // 谐波计数

// 流水线控制信号
reg         thd_calc_trigger;               // THD计算触发
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
// 1. 固定时间测量周期（避免CDC导致的不稳定）
//=============================================================================
// 使用100MHz时钟作为时间基准，确保每次测量周期都是精确的1秒
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        time_cnt <= 32'd0;
        measure_done <= 1'b0;
    end else if (measure_en) begin
        if (time_cnt >= TIME_1SEC - 1) begin
            time_cnt <= 32'd0;
            measure_done <= 1'b1;  // 脉冲信号
        end else begin
            time_cnt <= time_cnt + 1'b1;
            measure_done <= 1'b0;
        end
    end else begin
        time_cnt <= 32'd0;
        measure_done <= 1'b0;
    end
end

//=============================================================================
// 2. 频率测量 - 过零检测
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
reg [31:0] zero_cross_cnt_latch;  // 【新增】锁存计数值，避免时序竞争

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        zero_cross_cnt <= 32'd0;
        sample_cnt <= 32'd0;
        zero_cross_cnt_latch <= 32'd0;
    end else if (measure_en) begin
        if (measure_done) begin
            // 【修复】测量周期结束：先锁存，再清零
            zero_cross_cnt_latch <= zero_cross_cnt;
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
        zero_cross_cnt_latch <= 32'd0;
    end
end

// 频率计算 - 采样率修正 + 自动量程转换
// 【重要】分为3个流水线阶段，避免时序竞争和组合逻辑过长
reg [31:0] freq_temp;         // Stage 1: ×3计算结果
reg        freq_calc_trigger; // 计算触发信号
reg        freq_unit_flag;    // 单位标志（内部）：0=Hz, 1=kHz

// Stage 1: 触发并计算×3
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        freq_temp <= 32'd0;
        freq_calc_trigger <= 1'b0;
    end else if (measure_done) begin
        // 使用锁存的计数值计算
        freq_temp <= (zero_cross_cnt_latch << 1) + zero_cross_cnt_latch;  // ×3
        freq_calc_trigger <= 1'b1;
    end else begin
        freq_calc_trigger <= 1'b0;
    end
end

// Stage 2: 量程转换和单位判断
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        freq_calc <= 16'd0;
        freq_unit_flag <= 1'b0;
    end else if (freq_calc_trigger) begin
        // 量程转换（使用前一周期计算的freq_temp）
        if (freq_temp >= 32'd65535) begin
            // 高频：>=65.5kHz，转换为kHz显示（右移10位≈÷1024）
            freq_calc <= freq_temp[31:10];
            freq_unit_flag <= 1'b1;  // kHz单位
        end else begin
            // 低频：<65.5kHz，直接显示Hz
            freq_calc <= freq_temp[15:0];
            freq_unit_flag <= 1'b0;  // Hz单位
        end
    end
end

//=============================================================================
// 3. 幅度测量 - 峰峰值检测
//=============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        max_val <= 8'd0;
        min_val <= 8'd255;
    end else if (measure_en) begin
        if (measure_done) begin
            // 【修复】测量周期结束（1秒固定时间），重新开始
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
    else if (measure_done)
        amplitude_calc <= {8'd0, max_val} - {8'd0, min_val};
end

//=============================================================================
// 4. 占空比测量 - 流水线优化版本
//=============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        high_cnt <= 32'd0;
        total_cnt <= 32'd0;
        high_cnt_latch <= 32'd0;
        total_cnt_latch <= 32'd0;
        duty_calc_trigger <= 1'b0;
    end else if (measure_en) begin
        if (measure_done) begin
            // 【修复】测量周期结束（1秒固定时间），锁存并清零
            high_cnt_latch <= high_cnt;
            total_cnt_latch <= total_cnt;
            high_cnt <= 32'd0;
            total_cnt <= 32'd0;
            duty_calc_trigger <= 1'b1;
        end else begin
            duty_calc_trigger <= 1'b0;
            if (sample_valid) begin
                total_cnt <= total_cnt + 1'b1;
                // 【修复】改用 > 127 使高低电平判断更对称
                // 0-127: 低电平 (128个值)
                // 128-255: 高电平 (128个值)
                if (sample_data > 8'd127)
                    high_cnt <= high_cnt + 1'b1;
            end
        end
    end else begin
        high_cnt <= 32'd0;
        total_cnt <= 32'd0;
        high_cnt_latch <= 32'd0;
        total_cnt_latch <= 32'd0;
        duty_calc_trigger <= 1'b0;
    end
end

// 占空比计算 - 动态除法（适应可变的total_cnt）
// duty = (high_cnt * 1000) / total_cnt
// 
// 【修复】由于改用固定1秒测量周期，total_cnt不再固定：
// - 之前：sample_cnt达到35M时结束 → total_cnt ≈ 35M
// - 现在：固定1秒结束 → total_cnt ≈ 12M (sample_valid有效率35%)
// 
// 【重要】分离为两个流水线阶段，避免组合逻辑错误
reg [39:0] duty_numerator;    // high_cnt × 1000 (Stage 1)
reg [31:0] duty_denominator;  // total_cnt (Stage 1)

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        duty_numerator <= 40'd0;
        duty_denominator <= 32'd0;
    end else if (duty_calc_trigger && total_cnt_latch != 0) begin
        // Stage 1: 锁存并计算分子
        duty_numerator <= high_cnt_latch * 16'd1000;
        duty_denominator <= total_cnt_latch;
    end
end

// Stage 2: 除法计算（独立的always块，使用Stage 1的寄存器值）
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        duty_calc <= 16'd0;
    end else if (duty_denominator != 0) begin
        duty_calc <= duty_numerator / duty_denominator;
    end
end

//=============================================================================
// 5. THD测量 - 改进算法：基于频率测量动态计算基波和谐波位置
// THD = sqrt(P2^2 + P3^2 + ... + Pn^2) / P1
// 简化计算: THD ≈ (P2 + P3 + ... + Pn) / P1
// 
// 频率分辨率 = 采样率 / FFT点数 = 35MHz / 8192 ≈ 4.27kHz
// bin_index = 频率 / 频率分辨率
//=============================================================================
reg [12:0]  fundamental_bin;                // 基波bin（根据频率动态计算）
reg [12:0]  current_harmonic_bin;          // 当前检测的谐波bin
reg [3:0]   harmonic_order;                 // 当前谐波次数(2-10)
reg [31:0]  total_spectrum_power;          // 总频谱能量（用于改进THD算法）
reg         thd_scan_active;               // THD扫描激活

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        fundamental_power <= 32'd0;
        harmonic_power <= 32'd0;
        total_spectrum_power <= 32'd0;
        harmonic_cnt <= 4'd0;
        thd_calc_trigger <= 1'b0;
        fundamental_bin <= 13'd0;
        current_harmonic_bin <= 13'd0;
        harmonic_order <= 4'd0;
        thd_scan_active <= 1'b0;
    end else if (spectrum_valid && measure_en) begin
        // 频谱扫描开始时，根据测得的频率计算基波bin
        if (spectrum_addr == 13'd0) begin
            // 计算基波bin: bin = freq / (35MHz / 8192) = freq / 4272.46 ≈ freq * 192 / 1000000
            // 简化: bin ≈ (freq * 192) >> 20
            fundamental_bin <= (freq_calc < 16'd100) ? 13'd1 : 
                              ((freq_calc * 13'd192) >> 10);  // 近似：freq / 4272
            harmonic_power <= 32'd0;
            total_spectrum_power <= 32'd0;
            harmonic_cnt <= 4'd0;
            harmonic_order <= 4'd2;  // 从2次谐波开始
            thd_calc_trigger <= 1'b0;
            thd_scan_active <= 1'b1;
        end
        
        // 检测基波（允许±2 bin的范围）
        else if (thd_scan_active && 
                 spectrum_addr >= (fundamental_bin - 13'd2) && 
                 spectrum_addr <= (fundamental_bin + 13'd2)) begin
            // 找到基波峰值
            if ({16'd0, spectrum_data} > fundamental_power) begin
                fundamental_power <= {16'd0, spectrum_data};
            end
        end
        
        // 检测2-10次谐波（每次谐波搜索±2 bin范围）
        else if (thd_scan_active && harmonic_order <= 4'd10) begin
            current_harmonic_bin <= fundamental_bin * harmonic_order;
            if (spectrum_addr >= (fundamental_bin * harmonic_order - 13'd2) && 
                spectrum_addr <= (fundamental_bin * harmonic_order + 13'd2)) begin
                // 累加谐波能量
                harmonic_power <= harmonic_power + {16'd0, spectrum_data};
            end
            // 当前谐波扫描完成，移动到下一个
            else if (spectrum_addr == (fundamental_bin * harmonic_order + 13'd3)) begin
                harmonic_cnt <= harmonic_cnt + 1'b1;
                harmonic_order <= harmonic_order + 1'b1;
            end
        end
        
        // 扫描结束，触发THD计算
        else if (spectrum_addr == 13'd1023 && thd_scan_active) begin
            thd_calc_trigger <= 1'b1;
            thd_scan_active <= 1'b0;
        end else begin
            thd_calc_trigger <= 1'b0;
        end
        
        // 累加总能量（用于归一化）
        if (spectrum_addr < 13'd1024) begin
            total_spectrum_power <= total_spectrum_power + {16'd0, spectrum_data};
        end
    end else begin
        thd_calc_trigger <= 1'b0;
        thd_scan_active <= 1'b0;
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
        freq_is_khz <= 1'b0;
        amplitude_out <= 16'd0;
        duty_out <= 16'd0;
        thd_out <= 16'd0;
    end else if (measure_done && measure_en) begin
        // 【修复】仅在测量周期结束时更新输出，避免显示中间值
        freq_out <= freq_calc;
        freq_is_khz <= freq_unit_flag;
        amplitude_out <= amplitude_calc;
        duty_out <= duty_calc;
        thd_out <= thd_calc;
    end
end

endmodule