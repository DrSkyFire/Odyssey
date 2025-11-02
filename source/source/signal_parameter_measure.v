//=============================================================================
// 文件�? signal_parameter_measure.v
// 描述: 信号参数测量模块
// 功能: 
//   1. 频率测量 - 基于过零检�?
//   2. 幅度测量 - 峰峰值检�?
//   3. 占空比测�?- 高电平时间比�?
//   4. THD测量 - 基于FFT频谱数据
//=============================================================================

module signal_parameter_measure (
    input  wire         clk,                // 系统时钟 100MHz
    input  wire         rst_n,
    
    // 时域数据输入 (用于频率、幅度、占空比测量)
    input  wire         sample_clk,         // 采样时钟 35MHz
    input  wire [9:0]   sample_data,        // 采样数据 (10位ADC)
    input  wire         sample_valid,       // 采样有效
    
    // 频域数据输入 (用于THD测量)
    input  wire [15:0]  spectrum_data,      // 频谱幅度
    input  wire [12:0]  spectrum_addr,      // 频谱地址�?192点需�?3位）
    input  wire         spectrum_valid,     // 频谱有效
    
    // 参数输出
    output reg  [15:0]  freq_out,           // 频率数�?
    output reg          freq_is_khz,        // 频率单位标志 (0=Hz, 1=kHz)
    output reg  [15:0]  amplitude_out,      // 幅度 (峰峰�?
    output reg  [15:0]  duty_out,           // 占空�?(0~1000 表示0%~100%)
    output reg  [15:0]  thd_out,            // THD (0~1000 表示0%~100%)
    
    // 控制
    input  wire         measure_en          // 测量使能
);

//=============================================================================
// 参数定义
//=============================================================================
localparam SAMPLE_RATE = 35_000_000;        // 采样�?35MHz (实际ADC采样�?
localparam MEASURE_TIME = 35_000_000;       // 测量周期�?5M个sample_valid
localparam TIME_100MS = 10_000_000;         // 【优化�?00ms�?00MHz时钟周期�?(10Hz更新�?

// 【新增】FFT频率测量参数
localparam FFT_POINTS = 8192;               // FFT点数
localparam FREQ_RES = 4272;                 // 频率分辨�? 35MHz/8192 �?4272 Hz/bin

//=============================================================================
// 信号定义
//=============================================================================
// 【新增】固定时间计数器（避免CDC导致的测量周期不稳定�?
reg [31:0]  time_cnt;                       // 基于100MHz的时间计�?
reg         measure_done;                   // 测量周期结束标志

// 【新增】FFT峰值检测（用于频域频率/幅度测量�?
reg [15:0]  fft_max_amp;                    // FFT峰值幅�?
reg [12:0]  fft_peak_bin;                   // 峰值bin位置
reg         fft_scan_active;                // FFT扫描激�?
reg [31:0]  fft_freq_hz;                    // FFT计算的频率（Hz�?
reg         fft_freq_ready;                 // FFT频率就绪
reg         use_fft_freq;                   // 使用FFT频率（频域模式）

// 【新增】FFT谐波检测（用于THD计算�?
reg [15:0]  fft_harmonic_2;                 // 2次谐波幅�?
reg [15:0]  fft_harmonic_3;                 // 3次谐波幅�?
reg [15:0]  fft_harmonic_4;                 // 4次谐波幅�?
reg [15:0]  fft_harmonic_5;                 // 5次谐波幅�?
reg [2:0]   fft_harm_state;                 // 谐波扫描状�?
reg [12:0]  fft_target_bin;                 // 目标谐波bin
reg [15:0]  fft_temp_amp;                   // 临时幅度

// 频率测量
reg [9:0]   data_d1, data_d2;               // 【修改�?0位数据延�?
reg         zero_cross;                     // 过零标志
reg [31:0]  zero_cross_cnt;                 // 过零计数
reg [31:0]  sample_cnt;                     // 采样计数
reg [15:0]  freq_calc;

// 【优化】频率精确计�?- 使用LUT代替除法
reg [7:0]   freq_lut_index;                 // LUT索引
reg [16:0]  freq_reciprocal;                // 倒数�?(17�?
reg [48:0]  freq_product;                   // 乘法结果 (32×17=49�?
reg [15:0]  freq_result;                    // 最终频率�?
reg         freq_unit_flag_int;             // 内部单位标志（流水线使用�?
reg         freq_result_done;               // Stage 4完成标志
reg         freq_unit_d2;                   // 单位标志延迟2�?

// 【优化】频率滑动平均滤�?(4次平�?
reg [15:0]  freq_history[0:3];              // 历史值缓�?
reg [1:0]   freq_hist_ptr;                  // 历史值指�?
reg [17:0]  freq_sum;                       // 累加�?
reg [15:0]  freq_filtered;                  // 滤波后的结果

// 幅度测量 - 【修改�?0位精�?
reg [9:0]   max_val;
reg [9:0]   min_val;
reg [15:0]  amplitude_calc;

// Duty cycle measurement
reg [31:0]  high_cnt;                       // High level counter
reg [31:0]  total_cnt;                      // Total counter
reg [31:0]  high_cnt_latch;                 // Latched high count
reg [31:0]  total_cnt_latch;                // Latched total count
reg         duty_calc_trigger;              // Duty calculation trigger
reg [15:0]  duty_calc;                      // Duty calculation result

// LUT-based division using reciprocal multiplication
// Instead of a/b, compute a * (1/b) where 1/b is from LUT
reg [39:0]  duty_numerator;                 // high_cnt * 1000
reg [31:0]  duty_denominator;               // total_cnt
reg [7:0]   duty_denom_index;               // LUT index
reg [1:0]   duty_scale_shift;               // Not used (for future)
reg [15:0]  duty_reciprocal;                // 1/denominator from LUT (Q16 format)
reg [63:0]  duty_product;                   // numerator[31:0] * reciprocal (32×32=64 bits)
reg [15:0]  duty_result;                    // Final result

// 【优化】占空比滑动平均滤波 (8次平均，减少跳动)
reg [15:0]  duty_history[0:7];              // 历史值缓�?
reg [2:0]   duty_hist_ptr;                  // 历史值指�?
reg [18:0]  duty_sum;                       // 累加�?(16位�?需�?9�?
reg [15:0]  duty_filtered;                  // 滤波后的结果

// THD测量 - 添加流水�?
reg [31:0]  fundamental_power;              // 基波功率
reg [31:0]  harmonic_power;                 // 谐波功率
reg [39:0]  thd_mult_stage1;                // 流水线第1级：乘法
reg [39:0]  thd_mult_stage2;                // 流水线第2级：延迟对齐
reg [15:0]  thd_calc;                       // 流水线第3级：移位除法
reg [3:0]   harmonic_cnt;                   // 谐波计数

// 流水线控制信�?
reg         thd_calc_trigger;               // THD计算触发
reg [2:0]   thd_pipe_valid;                 // THD流水线有效标�?

//=============================================================================
// 采样数据同步到系统时钟域
//=============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        data_d1 <= 10'd0;
        data_d2 <= 10'd0;
    end else if (sample_valid) begin
        data_d1 <= sample_data;
        data_d2 <= data_d1;
    end
end

//=============================================================================
// 1. 快速测量周期（100ms更新�?0Hz刷新率）
//=============================================================================
// 使用100MHz时钟作为时间基准，确保每次测量周期都是精确的100ms
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        time_cnt <= 32'd0;
        measure_done <= 1'b0;
    end else if (measure_en) begin
        if (time_cnt >= TIME_100MS - 1) begin
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
// 2. 频率测量 - 过零检�?
//=============================================================================
// 检测过零点（从低到高）- 【修改�?0位中间�?12
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        zero_cross <= 1'b0;
    else if (sample_valid)
        zero_cross <= (data_d2 < 10'd512) && (data_d1 >= 10'd512);
    else
        zero_cross <= 1'b0;
end

// 过零计数和采样计�?
reg [31:0] zero_cross_cnt_latch;  // 【新增】锁存计数值，避免时序竞争

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        zero_cross_cnt <= 32'd0;
        sample_cnt <= 32'd0;
        zero_cross_cnt_latch <= 32'd0;
    end else if (measure_en) begin
        if (measure_done) begin
            // 【修复】测量周期结束：先锁存，再清�?
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

// 【优化】频率LUT：精确�?00（用于kHz转换�?
// 100ms测量周期，freq_temp�?00ms内的过零次数
// 实际频率 = freq_temp * 10 (Hz)
// kHz显示 = freq_temp * 10 / 1000 = freq_temp / 100
// 使用LUT实现：freq / 100 = freq * (65536/100) / 65536
function [16:0] freq_reciprocal_lut;
    input [7:0] index;
    begin
        case (index)
            8'd0:   freq_reciprocal_lut = 17'd65536;  // 避免�?
            8'd1:   freq_reciprocal_lut = 17'd65536;  // 100/1
            8'd2:   freq_reciprocal_lut = 17'd32768;  // 100/2
            8'd4:   freq_reciprocal_lut = 17'd16384;  // 100/4
            8'd5:   freq_reciprocal_lut = 17'd13107;  // 100/5
            8'd10:  freq_reciprocal_lut = 17'd6553;   // 100/10
            8'd16:  freq_reciprocal_lut = 17'd4096;   // 100/16
            8'd20:  freq_reciprocal_lut = 17'd3276;   // 100/20
            8'd25:  freq_reciprocal_lut = 17'd2621;   // 100/25
            8'd32:  freq_reciprocal_lut = 17'd2048;   // 100/32
            8'd40:  freq_reciprocal_lut = 17'd1638;   // 100/40
            8'd50:  freq_reciprocal_lut = 17'd1310;   // 100/50
            8'd64:  freq_reciprocal_lut = 17'd1024;   // 100/64
            8'd80:  freq_reciprocal_lut = 17'd819;    // 100/80
            8'd100: freq_reciprocal_lut = 17'd655;    // 100/100
            8'd128: freq_reciprocal_lut = 17'd512;    // 100/128
            8'd160: freq_reciprocal_lut = 17'd409;    // 100/160
            8'd200: freq_reciprocal_lut = 17'd327;    // 100/200
            8'd255: freq_reciprocal_lut = 17'd257;    // 100/255
            default: begin
                // 线性插值近�?
                if (index < 4)        freq_reciprocal_lut = 17'd16384;
                else if (index < 10)  freq_reciprocal_lut = 17'd8192;
                else if (index < 20)  freq_reciprocal_lut = 17'd4096;
                else if (index < 40)  freq_reciprocal_lut = 17'd2048;
                else if (index < 80)  freq_reciprocal_lut = 17'd1024;
                else if (index < 160) freq_reciprocal_lut = 17'd512;
                else                  freq_reciprocal_lut = 17'd256;
            end
        endcase
    end
endfunction

// 频率计算 - 精确÷1000 + 滑动平均滤波
reg [31:0] freq_temp;         // 原始计数�?
reg        freq_calc_trigger; // 计算触发信号

// Stage 1: 触发并锁存计数�?
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        freq_temp <= 32'd0;
        freq_calc_trigger <= 1'b0;
    end else if (measure_done) begin
        freq_temp <= zero_cross_cnt_latch;
        freq_calc_trigger <= 1'b1;
    end else begin
        freq_calc_trigger <= 1'b0;
    end
end

// Stage 2: 判断单位（Hz或kHz�?
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        freq_unit_flag_int <= 1'b0;
    end else if (freq_calc_trigger) begin
        // 100ms测量周期：freq_temp = 实际频率 / 10
        // 如果 freq_temp >= 10000，则实际频率 >= 100kHz，使用kHz显示
        freq_unit_flag_int <= (freq_temp >= 32'd10000);
    end
end

// Stage 3: 计算频率�?
reg freq_mult_done;
reg [31:0] freq_temp_d1;  // 延迟一拍对齐流水线
reg        freq_unit_d1;  // 单位标志延迟
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        freq_product <= 49'd0;
        freq_mult_done <= 1'b0;
        freq_temp_d1 <= 32'd0;
        freq_unit_d1 <= 1'b0;
    end else begin
        freq_mult_done <= freq_calc_trigger;  // 延迟一周期
        freq_temp_d1 <= freq_temp;            // 对齐流水�?
        freq_unit_d1 <= freq_unit_flag_int;   // 对齐单位标志
        
        if (freq_calc_trigger) begin
            if (freq_unit_flag_int) begin
                // kHz模式：显示�?= freq_temp（保�?位小数，单位0.01kHz�?
                // 例如：freq_temp=50000表示500.00kHz
                freq_product <= {17'd0, freq_temp};
            end else begin
                // Hz模式：显示�?= freq_temp * 10
                // 例如：freq_temp=50表示500Hz
                freq_product <= {17'd0, freq_temp * 32'd10};
            end
        end
    end
end

// Stage 4: 提取结果（直接取�?6位）
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        freq_result <= 16'd0;
        freq_result_done <= 1'b0;
        freq_unit_d2 <= 1'b0;
    end else begin
        freq_result_done <= freq_mult_done;
        freq_unit_d2 <= freq_unit_d1;
        
        if (freq_mult_done) begin
            // 直接取低16位作为结�?
            freq_result <= freq_product[15:0];
        end
    end
end

// Stage 5: 滑动平均滤波器（4次平均，减少抖动�?
integer j;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        freq_sum <= 18'd0;
        freq_hist_ptr <= 2'd0;
        freq_filtered <= 16'd0;
        for (j = 0; j < 4; j = j + 1) begin
            freq_history[j] <= 16'd0;
        end
    end else if (freq_result_done && freq_result != freq_history[freq_hist_ptr]) begin
        // 更新滑动平均（当新值与历史不同时）
        freq_sum <= freq_sum - freq_history[freq_hist_ptr] + freq_result;
        freq_history[freq_hist_ptr] <= freq_result;
        freq_hist_ptr <= freq_hist_ptr + 1'b1;
        freq_filtered <= freq_sum[17:2];  // ÷4
    end
end

// Stage 6: 输出频率计算结果（freq_is_khz在输出寄存器处统一赋值）
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        freq_calc <= 16'd0;
    end else begin
        freq_calc <= freq_filtered;        // 使用滤波后的�?
    end
end

//=============================================================================
// 2B. 【新增】FFT频谱峰值频率测量（频域模式，精度更高）
//=============================================================================
// 实时流式峰值搜�?- 在FFT输出数据流中找最大�?
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        fft_max_amp <= 16'd0;
        fft_peak_bin <= 13'd0;
        fft_scan_active <= 1'b0;
        fft_freq_hz <= 32'd0;
        fft_freq_ready <= 1'b0;
        use_fft_freq <= 1'b0;
    end else if (measure_en && spectrum_valid) begin
        // 检测FFT扫描开�?
        if (spectrum_addr == 13'd0) begin
            fft_scan_active <= 1'b1;
            fft_max_amp <= 16'd0;
            fft_peak_bin <= 13'd0;
            fft_freq_ready <= 1'b0;
            use_fft_freq <= 1'b1;  // 标记使用FFT频率
        end
        // 峰值搜索（跳过DC分量，只扫描前半部分避免镜像�?
        else if (fft_scan_active && spectrum_addr >= 13'd10 && spectrum_addr < (FFT_POINTS/2)) begin
            if (spectrum_data > fft_max_amp) begin
                fft_max_amp <= spectrum_data;
                fft_peak_bin <= spectrum_addr;
            end
        end
        // 扫描结束，计算频�?
        else if (spectrum_addr == (FFT_POINTS/2)) begin
            fft_scan_active <= 1'b0;
            // 频率 = peak_bin * 频率分辨�?(4272 Hz)
            fft_freq_hz <= fft_peak_bin * FREQ_RES;
            fft_freq_ready <= 1'b1;
        end
    end else begin
        fft_freq_ready <= 1'b0;
    end
end

//=============================================================================
// 2C. 【新增】FFT谐波检测状态机（用于THD计算�?
//=============================================================================
localparam HARM_IDLE  = 3'd0;
localparam HARM_SCAN2 = 3'd1;
localparam HARM_SCAN3 = 3'd2;
localparam HARM_SCAN4 = 3'd3;
localparam HARM_SCAN5 = 3'd4;
localparam HARM_DONE  = 3'd5;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        fft_harm_state <= HARM_IDLE;
        fft_harmonic_2 <= 16'd0;
        fft_harmonic_3 <= 16'd0;
        fft_harmonic_4 <= 16'd0;
        fft_harmonic_5 <= 16'd0;
        fft_target_bin <= 13'd0;
        fft_temp_amp <= 16'd0;
    end else begin
        case (fft_harm_state)
            HARM_IDLE: begin
                if (fft_freq_ready) begin
                    // FFT扫描完成，开始谐波检�?
                    fft_harm_state <= HARM_SCAN2;
                    fft_target_bin <= fft_peak_bin << 1;  // 2次谐�?= 基波*2
                    fft_temp_amp <= 16'd0;
                end
            end
            
            HARM_SCAN2: begin
                if (spectrum_valid) begin
                    // 在目标bin附近±3范围搜索最大�?
                    if (spectrum_addr >= (fft_target_bin - 13'd3) && 
                        spectrum_addr <= (fft_target_bin + 13'd3)) begin
                        if (spectrum_data > fft_temp_amp) begin
                            fft_temp_amp <= spectrum_data;
                        end
                    end
                    else if (spectrum_addr > (fft_target_bin + 13'd3)) begin
                        fft_harmonic_2 <= fft_temp_amp;
                        fft_harm_state <= HARM_SCAN3;
                        fft_target_bin <= fft_peak_bin + (fft_peak_bin << 1);  // 3次谐�?
                        fft_temp_amp <= 16'd0;
                    end
                end
            end
            
            HARM_SCAN3: begin
                if (spectrum_valid) begin
                    if (spectrum_addr >= (fft_target_bin - 13'd3) && 
                        spectrum_addr <= (fft_target_bin + 13'd3)) begin
                        if (spectrum_data > fft_temp_amp) begin
                            fft_temp_amp <= spectrum_data;
                        end
                    end
                    else if (spectrum_addr > (fft_target_bin + 13'd3)) begin
                        fft_harmonic_3 <= fft_temp_amp;
                        fft_harm_state <= HARM_SCAN4;
                        fft_target_bin <= fft_peak_bin << 2;  // 4次谐�?
                        fft_temp_amp <= 16'd0;
                    end
                end
            end
            
            HARM_SCAN4: begin
                if (spectrum_valid) begin
                    if (spectrum_addr >= (fft_target_bin - 13'd3) && 
                        spectrum_addr <= (fft_target_bin + 13'd3)) begin
                        if (spectrum_data > fft_temp_amp) begin
                            fft_temp_amp <= spectrum_data;
                        end
                    end
                    else if (spectrum_addr > (fft_target_bin + 13'd3)) begin
                        fft_harmonic_4 <= fft_temp_amp;
                        fft_harm_state <= HARM_SCAN5;
                        fft_target_bin <= fft_peak_bin + (fft_peak_bin << 2);  // 5次谐�?
                        fft_temp_amp <= 16'd0;
                    end
                end
            end
            
            HARM_SCAN5: begin
                if (spectrum_valid) begin
                    if (spectrum_addr >= (fft_target_bin - 13'd3) && 
                        spectrum_addr <= (fft_target_bin + 13'd3)) begin
                        if (spectrum_data > fft_temp_amp) begin
                            fft_temp_amp <= spectrum_data;
                        end
                    end
                    else if (spectrum_addr > (fft_target_bin + 13'd3)) begin
                        fft_harmonic_5 <= fft_temp_amp;
                        fft_harm_state <= HARM_DONE;
                    end
                end
            end
            
            HARM_DONE: begin
                fft_harm_state <= HARM_IDLE;
            end
            
            default: fft_harm_state <= HARM_IDLE;
        endcase
    end
end

//=============================================================================
// 3. 幅度测量 - 峰峰值检�?(10位精�?
//=============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        max_val <= 10'd0;
        min_val <= 10'd1023;
    end else if (measure_en) begin
        if (measure_done) begin
            // 【修复】测量周期结束（100ms固定时间），重新开�?
            max_val <= 10'd0;
            min_val <= 10'd1023;
        end else if (sample_valid) begin
            if (sample_data > max_val)
                max_val <= sample_data;
            if (sample_data < min_val)
                min_val <= sample_data;
        end
    end else begin
        max_val <= 10'd0;
        min_val <= 10'd1023;
    end
end

// 幅度计算（峰峰值）- 【修改】扩展到10�?
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        amplitude_calc <= 16'd0;
    else if (measure_done)
        amplitude_calc <= {6'd0, max_val} - {6'd0, min_val};
end

//=============================================================================
// 4. 占空比测�?- 流水线优化版�?
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
            // 【修复】测量周期结束（100ms固定时间），锁存并清�?
            high_cnt_latch <= high_cnt;
            total_cnt_latch <= total_cnt;
            high_cnt <= 32'd0;
            total_cnt <= 32'd0;
            duty_calc_trigger <= 1'b1;
        end else begin
            duty_calc_trigger <= 1'b0;
            if (sample_valid) begin
                total_cnt <= total_cnt + 1'b1;
                // 【修改�?0位中间值：511 (0-511低电�? 512-1023高电�?
                // 使用 > 511 使高低电平判断对�?
                if (sample_data > 10'd511)
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

//=============================================================================
// 4. Duty Cycle Calculation - LUT-based Reciprocal Multiplication
// Replace division with LUT lookup + multiplication to eliminate timing violation
// duty% = (high_cnt * 1000) / total_cnt
//       = (high_cnt * 1000) * (1 / total_cnt)
//       = numerator * reciprocal_LUT[index]
//
// LUT stores 256 reciprocal values in Q16 fixed-point format
// Index = denominator[31:24] (upper 8 bits)
// Timing: 3-stage pipeline, each stage <3ns
//=============================================================================

// Reciprocal LUT: stores 1/x in Q16 format (65536 / x)
// Index range: 1-255 (0 reserved for divide-by-zero protection)
// 【优化】使用完�?56项LUT，每项都精确预计�?
function [15:0] reciprocal_lut;
    input [7:0] index;
    begin
        case (index)
            8'd0:   reciprocal_lut = 16'd65535;
            8'd1:   reciprocal_lut = 16'd65535;
            8'd2:   reciprocal_lut = 16'd32768;
            8'd3:   reciprocal_lut = 16'd21845;
            8'd4:   reciprocal_lut = 16'd16384;
            8'd5:   reciprocal_lut = 16'd13107;
            8'd6:   reciprocal_lut = 16'd10922;
            8'd7:   reciprocal_lut = 16'd9362;
            8'd8:   reciprocal_lut = 16'd8192;
            8'd9:   reciprocal_lut = 16'd7281;
            8'd10:  reciprocal_lut = 16'd6553;
            8'd11:  reciprocal_lut = 16'd5957;
            8'd12:  reciprocal_lut = 16'd5461;
            8'd13:  reciprocal_lut = 16'd5041;
            8'd14:  reciprocal_lut = 16'd4681;
            8'd15:  reciprocal_lut = 16'd4369;
            8'd16:  reciprocal_lut = 16'd4096;
            8'd17:  reciprocal_lut = 16'd3855;
            8'd18:  reciprocal_lut = 16'd3640;
            8'd19:  reciprocal_lut = 16'd3449;
            8'd20:  reciprocal_lut = 16'd3276;
            8'd21:  reciprocal_lut = 16'd3120;
            8'd22:  reciprocal_lut = 16'd2978;
            8'd23:  reciprocal_lut = 16'd2849;
            8'd24:  reciprocal_lut = 16'd2730;
            8'd25:  reciprocal_lut = 16'd2621;
            8'd26:  reciprocal_lut = 16'd2520;
            8'd27:  reciprocal_lut = 16'd2427;
            8'd28:  reciprocal_lut = 16'd2340;
            8'd29:  reciprocal_lut = 16'd2259;
            8'd30:  reciprocal_lut = 16'd2184;
            8'd31:  reciprocal_lut = 16'd2114;
            8'd32:  reciprocal_lut = 16'd2048;
            8'd33:  reciprocal_lut = 16'd1985;
            8'd34:  reciprocal_lut = 16'd1927;
            8'd35:  reciprocal_lut = 16'd1872;
            8'd36:  reciprocal_lut = 16'd1820;
            8'd37:  reciprocal_lut = 16'd1771;
            8'd38:  reciprocal_lut = 16'd1724;
            8'd39:  reciprocal_lut = 16'd1680;
            8'd40:  reciprocal_lut = 16'd1638;
            8'd41:  reciprocal_lut = 16'd1598;
            8'd42:  reciprocal_lut = 16'd1560;
            8'd43:  reciprocal_lut = 16'd1524;
            8'd44:  reciprocal_lut = 16'd1489;
            8'd45:  reciprocal_lut = 16'd1456;
            8'd46:  reciprocal_lut = 16'd1424;
            8'd47:  reciprocal_lut = 16'd1394;
            8'd48:  reciprocal_lut = 16'd1365;
            8'd49:  reciprocal_lut = 16'd1337;
            8'd50:  reciprocal_lut = 16'd1310;
            8'd51:  reciprocal_lut = 16'd1285;
            8'd52:  reciprocal_lut = 16'd1260;
            8'd53:  reciprocal_lut = 16'd1236;
            8'd54:  reciprocal_lut = 16'd1213;
            8'd55:  reciprocal_lut = 16'd1191;
            8'd56:  reciprocal_lut = 16'd1170;
            8'd57:  reciprocal_lut = 16'd1149;
            8'd58:  reciprocal_lut = 16'd1129;
            8'd59:  reciprocal_lut = 16'd1110;
            8'd60:  reciprocal_lut = 16'd1092;
            8'd61:  reciprocal_lut = 16'd1074;
            8'd62:  reciprocal_lut = 16'd1057;
            8'd63:  reciprocal_lut = 16'd1040;
            8'd64:  reciprocal_lut = 16'd1024;
            8'd65:  reciprocal_lut = 16'd1008;
            8'd66:  reciprocal_lut = 16'd993;
            8'd67:  reciprocal_lut = 16'd978;
            8'd68:  reciprocal_lut = 16'd963;
            8'd69:  reciprocal_lut = 16'd949;
            8'd70:  reciprocal_lut = 16'd936;
            8'd71:  reciprocal_lut = 16'd922;
            8'd72:  reciprocal_lut = 16'd910;
            8'd73:  reciprocal_lut = 16'd897;
            8'd74:  reciprocal_lut = 16'd885;
            8'd75:  reciprocal_lut = 16'd873;
            8'd76:  reciprocal_lut = 16'd862;
            8'd77:  reciprocal_lut = 16'd851;
            8'd78:  reciprocal_lut = 16'd840;
            8'd79:  reciprocal_lut = 16'd829;
            8'd80:  reciprocal_lut = 16'd819;
            8'd81:  reciprocal_lut = 16'd809;
            8'd82:  reciprocal_lut = 16'd799;
            8'd83:  reciprocal_lut = 16'd789;
            8'd84:  reciprocal_lut = 16'd780;
            8'd85:  reciprocal_lut = 16'd771;
            8'd86:  reciprocal_lut = 16'd762;
            8'd87:  reciprocal_lut = 16'd753;
            8'd88:  reciprocal_lut = 16'd744;
            8'd89:  reciprocal_lut = 16'd736;
            8'd90:  reciprocal_lut = 16'd728;
            8'd91:  reciprocal_lut = 16'd720;
            8'd92:  reciprocal_lut = 16'd712;
            8'd93:  reciprocal_lut = 16'd704;
            8'd94:  reciprocal_lut = 16'd697;
            8'd95:  reciprocal_lut = 16'd690;
            8'd96:  reciprocal_lut = 16'd682;
            8'd97:  reciprocal_lut = 16'd675;
            8'd98:  reciprocal_lut = 16'd668;
            8'd99:  reciprocal_lut = 16'd662;
            8'd100: reciprocal_lut = 16'd655;
            8'd101: reciprocal_lut = 16'd649;
            8'd102: reciprocal_lut = 16'd642;
            8'd103: reciprocal_lut = 16'd636;
            8'd104: reciprocal_lut = 16'd630;
            8'd105: reciprocal_lut = 16'd624;
            8'd106: reciprocal_lut = 16'd618;
            8'd107: reciprocal_lut = 16'd612;
            8'd108: reciprocal_lut = 16'd606;
            8'd109: reciprocal_lut = 16'd601;
            8'd110: reciprocal_lut = 16'd595;
            8'd111: reciprocal_lut = 16'd590;
            8'd112: reciprocal_lut = 16'd585;
            8'd113: reciprocal_lut = 16'd580;
            8'd114: reciprocal_lut = 16'd575;
            8'd115: reciprocal_lut = 16'd569;
            8'd116: reciprocal_lut = 16'd565;
            8'd117: reciprocal_lut = 16'd560;
            8'd118: reciprocal_lut = 16'd555;
            8'd119: reciprocal_lut = 16'd550;
            8'd120: reciprocal_lut = 16'd546;
            8'd121: reciprocal_lut = 16'd541;
            8'd122: reciprocal_lut = 16'd537;
            8'd123: reciprocal_lut = 16'd532;
            8'd124: reciprocal_lut = 16'd528;
            8'd125: reciprocal_lut = 16'd524;
            8'd126: reciprocal_lut = 16'd520;
            8'd127: reciprocal_lut = 16'd516;
            8'd128: reciprocal_lut = 16'd512;
            8'd129: reciprocal_lut = 16'd508;
            8'd130: reciprocal_lut = 16'd504;
            8'd131: reciprocal_lut = 16'd500;
            8'd132: reciprocal_lut = 16'd496;
            8'd133: reciprocal_lut = 16'd492;
            8'd134: reciprocal_lut = 16'd489;
            8'd135: reciprocal_lut = 16'd485;
            8'd136: reciprocal_lut = 16'd482;
            8'd137: reciprocal_lut = 16'd478;
            8'd138: reciprocal_lut = 16'd475;
            8'd139: reciprocal_lut = 16'd471;
            8'd140: reciprocal_lut = 16'd468;
            8'd141: reciprocal_lut = 16'd464;
            8'd142: reciprocal_lut = 16'd461;
            8'd143: reciprocal_lut = 16'd458;
            8'd144: reciprocal_lut = 16'd455;
            8'd145: reciprocal_lut = 16'd452;
            8'd146: reciprocal_lut = 16'd448;
            8'd147: reciprocal_lut = 16'd445;
            8'd148: reciprocal_lut = 16'd442;
            8'd149: reciprocal_lut = 16'd439;
            8'd150: reciprocal_lut = 16'd436;
            8'd151: reciprocal_lut = 16'd434;
            8'd152: reciprocal_lut = 16'd431;
            8'd153: reciprocal_lut = 16'd428;
            8'd154: reciprocal_lut = 16'd425;
            8'd155: reciprocal_lut = 16'd422;
            8'd156: reciprocal_lut = 16'd420;
            8'd157: reciprocal_lut = 16'd417;
            8'd158: reciprocal_lut = 16'd414;
            8'd159: reciprocal_lut = 16'd412;
            8'd160: reciprocal_lut = 16'd409;
            8'd161: reciprocal_lut = 16'd407;
            8'd162: reciprocal_lut = 16'd404;
            8'd163: reciprocal_lut = 16'd402;
            8'd164: reciprocal_lut = 16'd399;
            8'd165: reciprocal_lut = 16'd397;
            8'd166: reciprocal_lut = 16'd394;
            8'd167: reciprocal_lut = 16'd392;
            8'd168: reciprocal_lut = 16'd390;
            8'd169: reciprocal_lut = 16'd387;
            8'd170: reciprocal_lut = 16'd385;
            8'd171: reciprocal_lut = 16'd383;
            8'd172: reciprocal_lut = 16'd381;
            8'd173: reciprocal_lut = 16'd378;
            8'd174: reciprocal_lut = 16'd376;
            8'd175: reciprocal_lut = 16'd374;
            8'd176: reciprocal_lut = 16'd372;
            8'd177: reciprocal_lut = 16'd370;
            8'd178: reciprocal_lut = 16'd368;
            8'd179: reciprocal_lut = 16'd366;
            8'd180: reciprocal_lut = 16'd364;
            8'd181: reciprocal_lut = 16'd362;
            8'd182: reciprocal_lut = 16'd360;
            8'd183: reciprocal_lut = 16'd358;
            8'd184: reciprocal_lut = 16'd356;
            8'd185: reciprocal_lut = 16'd354;
            8'd186: reciprocal_lut = 16'd352;
            8'd187: reciprocal_lut = 16'd350;
            8'd188: reciprocal_lut = 16'd348;
            8'd189: reciprocal_lut = 16'd346;
            8'd190: reciprocal_lut = 16'd344;
            8'd191: reciprocal_lut = 16'd343;
            8'd192: reciprocal_lut = 16'd341;
            8'd193: reciprocal_lut = 16'd339;
            8'd194: reciprocal_lut = 16'd337;
            8'd195: reciprocal_lut = 16'd336;
            8'd196: reciprocal_lut = 16'd334;
            8'd197: reciprocal_lut = 16'd332;
            8'd198: reciprocal_lut = 16'd331;
            8'd199: reciprocal_lut = 16'd329;
            8'd200: reciprocal_lut = 16'd327;
            8'd201: reciprocal_lut = 16'd326;
            8'd202: reciprocal_lut = 16'd324;
            8'd203: reciprocal_lut = 16'd322;
            8'd204: reciprocal_lut = 16'd321;
            8'd205: reciprocal_lut = 16'd319;
            8'd206: reciprocal_lut = 16'd318;
            8'd207: reciprocal_lut = 16'd316;
            8'd208: reciprocal_lut = 16'd315;
            8'd209: reciprocal_lut = 16'd313;
            8'd210: reciprocal_lut = 16'd312;
            8'd211: reciprocal_lut = 16'd310;
            8'd212: reciprocal_lut = 16'd309;
            8'd213: reciprocal_lut = 16'd307;
            8'd214: reciprocal_lut = 16'd306;
            8'd215: reciprocal_lut = 16'd304;
            8'd216: reciprocal_lut = 16'd303;
            8'd217: reciprocal_lut = 16'd302;
            8'd218: reciprocal_lut = 16'd300;
            8'd219: reciprocal_lut = 16'd299;
            8'd220: reciprocal_lut = 16'd297;
            8'd221: reciprocal_lut = 16'd296;
            8'd222: reciprocal_lut = 16'd295;
            8'd223: reciprocal_lut = 16'd293;
            8'd224: reciprocal_lut = 16'd292;
            8'd225: reciprocal_lut = 16'd291;
            8'd226: reciprocal_lut = 16'd290;
            8'd227: reciprocal_lut = 16'd288;
            8'd228: reciprocal_lut = 16'd287;
            8'd229: reciprocal_lut = 16'd286;
            8'd230: reciprocal_lut = 16'd284;
            8'd231: reciprocal_lut = 16'd283;
            8'd232: reciprocal_lut = 16'd282;
            8'd233: reciprocal_lut = 16'd281;
            8'd234: reciprocal_lut = 16'd280;
            8'd235: reciprocal_lut = 16'd278;
            8'd236: reciprocal_lut = 16'd277;
            8'd237: reciprocal_lut = 16'd276;
            8'd238: reciprocal_lut = 16'd275;
            8'd239: reciprocal_lut = 16'd274;
            8'd240: reciprocal_lut = 16'd273;
            8'd241: reciprocal_lut = 16'd272;
            8'd242: reciprocal_lut = 16'd270;
            8'd243: reciprocal_lut = 16'd269;
            8'd244: reciprocal_lut = 16'd268;
            8'd245: reciprocal_lut = 16'd267;
            8'd246: reciprocal_lut = 16'd266;
            8'd247: reciprocal_lut = 16'd265;
            8'd248: reciprocal_lut = 16'd264;
            8'd249: reciprocal_lut = 16'd263;
            8'd250: reciprocal_lut = 16'd262;
            8'd251: reciprocal_lut = 16'd261;
            8'd252: reciprocal_lut = 16'd260;
            8'd253: reciprocal_lut = 16'd259;
            8'd254: reciprocal_lut = 16'd258;
            8'd255: reciprocal_lut = 16'd257;
        endcase
    end
endfunction

// Stage 1: Calculate numerator and LUT index based on total_cnt magnitude
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        duty_numerator <= 40'd0;
        duty_denominator <= 32'd0;
        duty_denom_index <= 8'd0;
        duty_scale_shift <= 2'd0;
    end else if (duty_calc_trigger && total_cnt_latch != 0) begin
        duty_numerator <= high_cnt_latch * 16'd1000;
        duty_denominator <= total_cnt_latch;
        
        // Use fixed 12-bit shift for all cases to avoid saturation
        // This maps 10-10M range to 2-2441 index range
        // We'll use upper 8 bits of the 12-bit shifted result
        // shift by 12: divide by 4096
        duty_denom_index <= (total_cnt_latch >> 12);  // This gives 0-2441 for our range
        
        // Saturate to 1-255 range
        if ((total_cnt_latch >> 12) == 0)
            duty_denom_index <= 8'd1;
        else if ((total_cnt_latch >> 12) >= 255)
            duty_denom_index <= 8'd255;
        else
            duty_denom_index <= (total_cnt_latch >> 12);
            
        duty_scale_shift <= 2'd0;  // Fixed shift of 12
    end
end

// Stage 2: Lookup reciprocal from LUT
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        duty_reciprocal <= 16'd0;
    end else begin
        duty_reciprocal <= reciprocal_lut(duty_denom_index);
    end
end

// Stage 3: Multiply numerator by reciprocal and scale
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        duty_product <= 64'd0;
        duty_result <= 16'd0;
        duty_calc <= 16'd0;
    end else begin
        // Multiply: numerator * reciprocal
        duty_product <= duty_numerator[31:0] * {16'd0, duty_reciprocal};
        
        // Fixed scaling: we used >> 12 (divide by 4096)
        // reciprocal = 65536 / index
        // product = numerator * 65536 / (total_cnt >> 12)
        //        = numerator * 65536 * 4096 / total_cnt
        // result = numerator / total_cnt = product / (65536 * 4096)
        //        = product >> (16 + 12) = product >> 28
        
        duty_result <= duty_product[43:28];  // Shift by 28 bits
        duty_calc <= duty_result;
    end
end

//=============================================================================
// 4b. 占空比滑动平均滤�?(8次平均，减少跳动)
//=============================================================================
integer i;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        for (i = 0; i < 8; i = i + 1) begin
            duty_history[i] <= 16'd0;
        end
        duty_hist_ptr <= 3'd0;
        duty_sum <= 19'd0;
        duty_filtered <= 16'd0;
    end else begin
        // 每次新的duty_calc到来时更新滑动窗�?
        if (duty_calc != duty_history[duty_hist_ptr]) begin  // 检测到新�?
            // 减去最老的�?
            duty_sum <= duty_sum - duty_history[duty_hist_ptr] + duty_calc;
            // 更新历史缓存
            duty_history[duty_hist_ptr] <= duty_calc;
            // 移动指针
            duty_hist_ptr <= duty_hist_ptr + 1'b1;
            // 计算平均�?(除以8 = 右移3�?
            duty_filtered <= duty_sum[18:3];
        end
    end
end

//=============================================================================
// 5. THD测量 - 改进算法：基于频率测量动态计算基波和谐波位置
// THD = sqrt(P2^2 + P3^2 + ... + Pn^2) / P1
// 简化计�? THD �?(P2 + P3 + ... + Pn) / P1
// 
// 频率分辨�?= 采样�?/ FFT点数 = 35MHz / 8192 �?4.27kHz
// bin_index = 频率 / 频率分辨�?
//=============================================================================
reg [12:0]  fundamental_bin;                // 基波bin（根据频率动态计算）
reg [12:0]  current_harmonic_bin;          // 当前检测的谐波bin
reg [3:0]   harmonic_order;                 // 当前谐波次数(2-10)
reg [31:0]  total_spectrum_power;          // 总频谱能量（用于改进THD算法�?
reg         thd_scan_active;               // THD扫描激�?

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
            // 计算基波bin: bin = freq / (35MHz / 8192) = freq / 4272.46 �?freq * 192 / 1000000
            // 简�? bin �?(freq * 192) >> 20
            fundamental_bin <= (freq_calc < 16'd100) ? 13'd1 : 
                              ((freq_calc * 13'd192) >> 10);  // 近似：freq / 4272
            harmonic_power <= 32'd0;
            total_spectrum_power <= 32'd0;
            harmonic_cnt <= 4'd0;
            harmonic_order <= 4'd2;  // �?次谐波开�?
            thd_calc_trigger <= 1'b0;
            thd_scan_active <= 1'b1;
        end
        
        // 检测基波（允许±2 bin的范围）
        else if (thd_scan_active && 
                 spectrum_addr >= (fundamental_bin - 13'd2) && 
                 spectrum_addr <= (fundamental_bin + 13'd2)) begin
            // 找到基波峰�?
            if ({16'd0, spectrum_data} > fundamental_power) begin
                fundamental_power <= {16'd0, spectrum_data};
            end
        end
        
        // 检�?-10次谐波（每次谐波搜索±2 bin范围�?
        else if (thd_scan_active && harmonic_order <= 4'd10) begin
            current_harmonic_bin <= fundamental_bin * harmonic_order;
            if (spectrum_addr >= (fundamental_bin * harmonic_order - 13'd2) && 
                spectrum_addr <= (fundamental_bin * harmonic_order + 13'd2)) begin
                // 累加谐波能量
                harmonic_power <= harmonic_power + {16'd0, spectrum_data};
            end
            // 当前谐波扫描完成，移动到下一�?
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

// THD计算 - 3级流水线，使用移位近似除�?
// THD = (harmonic * 1024) / fundamental，然后调整到1000�?
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
            // 根据fundamental_power的大小选择合适的移位�?
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
// 输出寄存�?
//=============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        freq_out <= 16'd0;
        freq_is_khz <= 1'b0;
        amplitude_out <= 16'd0;
        duty_out <= 16'd0;
        thd_out <= 16'd0;
    end else if (measure_en) begin
        // OPTIMIZED
        if (fft_freq_ready && use_fft_freq) begin
            if (fft_freq_hz >= 32'd100000) begin
                freq_is_khz <= 1'b1;
                freq_out <= (fft_freq_hz / 32'd100);
            end else begin
                freq_is_khz <= 1'b0;
                freq_out <= fft_freq_hz[15:0];
            end
            amplitude_out <= fft_max_amp;
        end else if (measure_done) begin
            freq_out <= freq_calc;
            freq_is_khz <= freq_unit_flag_int;
            amplitude_out <= amplitude_calc;
        end
        if (measure_done) begin
            duty_out <= duty_filtered;
            thd_out <= thd_calc;
        end
    endmodule
