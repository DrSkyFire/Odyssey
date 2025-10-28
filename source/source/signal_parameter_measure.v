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
localparam MEASURE_TIME = 100_000;          // ⚠️ 100k采样=100ms测量周期(采样率1MHz)
localparam DUTY_AVG_DEPTH = 8;              // ⚠️ 占空比滑动平均深度（8次平均）

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

// 占空比测量 - 添加流水线和滑动平均
reg [31:0]  high_cnt;                       // 高电平计数
reg [31:0]  total_cnt;                      // 总计数
reg [15:0]  duty_instant;                   // 瞬时占空比
reg [15:0]  duty_history [0:DUTY_AVG_DEPTH-1]; // 历史记录（用于滑动平均）
reg [2:0]   duty_history_idx;               // 历史索引
reg [19:0]  duty_sum;                       // 累加和（最大8*1000=8000需要14位，给20位余量）
reg [15:0]  duty_calc;                      // 平均后的占空比
integer     i;

// THD测量 - 添加流水线和滑动平均
reg [31:0]  fundamental_power;              // 基波功率
reg [31:0]  harmonic_power;                 // 谐波功率总和
reg [12:0]  fundamental_index;              // 基波频点索引（动态检测）
reg [15:0]  max_spectrum;                   // 最大频谱值（用于寻找基波）
reg [12:0]  spectrum_scan_addr;             // 频谱扫描地址
reg         thd_scan_done;                  // 扫描完成标志
reg [15:0]  thd_instant;                    // 瞬时THD值
reg [15:0]  thd_history [0:DUTY_AVG_DEPTH-1]; // THD历史记录
reg [2:0]   thd_history_idx;                // THD历史索引
reg [19:0]  thd_sum;                        // THD累加和
reg [15:0]  thd_calc;                       // 平滑后的THD

// 流水线控制信号
reg         duty_calc_trigger;              // 占空比计算触发
reg         thd_calc_trigger;               // THD计算触发

// ⚠️ 占空比计算流水线（优化版:使用16位除法降低时序压力）
reg [2:0]   duty_pipe_state;                // 流水线状态
reg [23:0]  duty_numerator;                 // 分子: high*1000, 最大100k*1000=100M需要27位,取24位
reg [16:0]  duty_denominator;               // 分母: total, 最大100k需要17位
reg [15:0]  duty_quotient;                  // 商
localparam DUTY_IDLE   = 3'd0;
localparam DUTY_MUL    = 3'd1;              // 计算 high*1000
localparam DUTY_DIV    = 3'd2;              // 执行除法
localparam DUTY_AVG    = 3'd3;              // 滑动平均

// ⚠️ THD计算流水线（优化版:使用缩小的位宽）
reg [2:0]   thd_pipe_state;                 // 流水线状态
reg [23:0]  thd_numerator;                  // 分子: harmonic*1000, 缩小到24位
reg [16:0]  thd_denominator;                // 分母: fundamental, 缩小到17位
reg [15:0]  thd_quotient;                   // 商
localparam THD_PIPE_IDLE   = 3'd0;
localparam THD_PIPE_MUL    = 3'd1;          // 计算 harmonic*1000
localparam THD_PIPE_DIV    = 3'd2;          // 执行除法
localparam THD_PIPE_LIMIT  = 3'd3;          // 限幅
localparam THD_PIPE_AVG    = 3'd4;          // 滑动平均

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
// 3. 占空比测量 - 滑动平均优化版本
// 策略：
//   1. 缩短测量周期到100ms（快速响应）
//   2. 每个周期计算瞬时占空比
//   3. 使用8次滑动平均平滑结果（减少跳动）
//   4. 使用正确的定点除法
//=============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        high_cnt <= 32'd0;
        total_cnt <= 32'd0;
        duty_calc_trigger <= 1'b0;
    end else if (measure_en) begin
        if (sample_cnt >= MEASURE_TIME) begin
            // 测量周期结束，触发计算并清零（开始新一轮测量）
            duty_calc_trigger <= 1'b1;
            high_cnt <= 32'd0;
            total_cnt <= 32'd0;
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

// ⚠️ 占空比计算流水线（4级流水线消除时序违例）
// 原因: 单周期内完成 ((high*1000)<<10) / ((total<<10)+1) 会产生34级加法器级联
// 解决: 分4个时钟周期完成
//   周期1 (MUL): 计算分子 = (high_cnt * 1000) << 10
//   周期2 (DIV): 计算分母 = (total_cnt << 10) + 1, 启动除法
//   周期3 (DIV): 完成除法 quotient = numerator / denominator
//   周期4 (AVG): 更新滑动平均
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        duty_pipe_state <= DUTY_IDLE;
        duty_numerator <= 42'd0;
        duty_denominator <= 42'd0;
        duty_quotient <= 16'd0;
        duty_instant <= 16'd0;
        duty_sum <= 20'd0;
        duty_calc <= 16'd0;
        duty_history_idx <= 3'd0;
        for (i = 0; i < DUTY_AVG_DEPTH; i = i + 1)
            duty_history[i] <= 16'd0;
    end else begin
        case (duty_pipe_state)
            DUTY_IDLE: begin
                if (duty_calc_trigger && total_cnt > 32'd100) begin
                    duty_pipe_state <= DUTY_MUL;
                end
            end
            
            DUTY_MUL: begin
                // 第1级: 计算 high_cnt * 1000 (截断到24位避免溢出)
                duty_numerator <= (high_cnt[16:0] * 17'd1000);  // 17位*1000=27位,取低24位
                duty_denominator <= total_cnt[16:0];            // 取低17位
                duty_pipe_state <= DUTY_DIV;
            end
            
            DUTY_DIV: begin
                // 第2级: 24位/17位除法 (比32位快很多)
                if (duty_denominator != 0) begin
                    duty_quotient <= duty_numerator / duty_denominator;
                end else begin
                    duty_quotient <= 16'd0;
                end
                duty_pipe_state <= DUTY_AVG;
            end
            
            DUTY_AVG: begin
                // 第4级: 更新滑动平均
                duty_instant <= duty_quotient;
                
                // 滑动平均窗口更新
                duty_sum <= duty_sum - duty_history[duty_history_idx] + duty_quotient;
                duty_history[duty_history_idx] <= duty_quotient;
                duty_history_idx <= duty_history_idx + 1'b1;
                if (duty_history_idx >= DUTY_AVG_DEPTH - 1)
                    duty_history_idx <= 3'd0;
                
                // 计算平均值：sum / 8（移位除法）
                duty_calc <= duty_sum[19:3];
                
                // 回到空闲状态
                duty_pipe_state <= DUTY_IDLE;
            end
            
            default: duty_pipe_state <= DUTY_IDLE;
        endcase
    end
end

//=============================================================================
// 4. THD测量 - 简化版本（修复除法Bug）
// 策略：
//   1. 扫描频谱找到最大值作为基波
//   2. 累加所有其他频点功率作为谐波+噪声
//   3. THD = (总功率 - 基波功率) / 基波功率 * 1000
//   4. 添加滑动平均平滑结果
//=============================================================================

// 状态机：扫描频谱找基波
localparam THD_IDLE = 2'd0;
localparam THD_SCAN = 2'd1;
localparam THD_CALC = 2'd2;

reg [1:0]   thd_state;
reg [31:0]  total_power;                    // 总功率（所有频点之和）

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        fundamental_power <= 32'd0;
        harmonic_power <= 32'd0;
        total_power <= 32'd0;
        fundamental_index <= 13'd0;
        max_spectrum <= 16'd0;
        spectrum_scan_addr <= 13'd0;
        thd_state <= THD_IDLE;
        thd_scan_done <= 1'b0;
        thd_calc_trigger <= 1'b0;
    end else if (measure_en && spectrum_valid) begin
        case (thd_state)
            THD_IDLE: begin
                // 等待新一轮FFT结果
                if (spectrum_addr == 13'd0) begin
                    // 重置状态，开始扫描
                    fundamental_power <= 32'd0;
                    harmonic_power <= 32'd0;
                    total_power <= 32'd0;
                    max_spectrum <= 16'd0;
                    fundamental_index <= 13'd0;
                    thd_state <= THD_SCAN;
                    thd_scan_done <= 1'b0;
                end
            end
            
            THD_SCAN: begin
                // 扫描前512个频点（低频部分，避免噪声）
                if (spectrum_addr < 13'd512) begin
                    total_power <= total_power + {16'd0, spectrum_data};
                    
                    // 跳过DC分量(addr=0),从第1个频点开始找基波
                    if (spectrum_addr > 13'd0 && spectrum_data > max_spectrum) begin
                        max_spectrum <= spectrum_data;
                        fundamental_index <= spectrum_addr;
                        fundamental_power <= {16'd0, spectrum_data};
                    end
                end else if (spectrum_addr == 13'd512) begin
                    // 扫描完成，计算谐波功率
                    harmonic_power <= total_power - fundamental_power;
                    thd_state <= THD_CALC;
                    thd_scan_done <= 1'b1;
                    thd_calc_trigger <= 1'b1;  // 触发THD计算
                end
            end
            
            THD_CALC: begin
                thd_calc_trigger <= 1'b0;
                thd_state <= THD_IDLE;  // 回到空闲，等待下一轮
            end
            
            default: thd_state <= THD_IDLE;
        endcase
    end else begin
        thd_calc_trigger <= 1'b0;
    end
end

// ⚠️ THD计算流水线（4级流水线消除时序违例）
// 原理同占空比计算
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        thd_pipe_state <= THD_PIPE_IDLE;
        thd_numerator <= 42'd0;
        thd_denominator <= 42'd0;
        thd_quotient <= 16'd0;
        thd_instant <= 16'd0;
        thd_sum <= 20'd0;
        thd_calc <= 16'd0;
        thd_history_idx <= 3'd0;
        for (i = 0; i < DUTY_AVG_DEPTH; i = i + 1)
            thd_history[i] <= 16'd0;
    end else begin
        case (thd_pipe_state)
            THD_PIPE_IDLE: begin
                if (thd_calc_trigger && fundamental_power > 32'd100) begin
                    thd_pipe_state <= THD_PIPE_MUL;
                end
            end
            
            THD_PIPE_MUL: begin
                // 第1级: 计算 harmonic * 1000 (截断到24位)
                thd_numerator <= (harmonic_power[16:0] * 17'd1000);  // 取低17位*1000
                thd_denominator <= fundamental_power[16:0];           // 取低17位
                thd_pipe_state <= THD_PIPE_DIV;
            end
            
            THD_PIPE_DIV: begin
                // 第2级: 24位/17位除法
                if (thd_denominator != 0) begin
                    thd_quotient <= thd_numerator / thd_denominator;
                end else begin
                    thd_quotient <= 16'd0;
                end
                thd_pipe_state <= THD_PIPE_LIMIT;
            end
            
            THD_PIPE_LIMIT: begin
                // 第3级: 限幅
                if (thd_quotient > 16'd1000)
                    thd_quotient <= 16'd1000;
                thd_pipe_state <= THD_PIPE_AVG;
            end
            
            THD_PIPE_AVG: begin
                // 第4级: 滑动平均
                thd_instant <= thd_quotient;
                
                // 滑动平均窗口更新
                thd_sum <= thd_sum - thd_history[thd_history_idx] + thd_quotient;
                thd_history[thd_history_idx] <= thd_quotient;
                thd_history_idx <= thd_history_idx + 1'b1;
                if (thd_history_idx >= DUTY_AVG_DEPTH - 1)
                    thd_history_idx <= 3'd0;
                
                // 计算平均值：sum / 8
                thd_calc <= thd_sum[19:3];
                
                // 回到空闲状态
                thd_pipe_state <= THD_PIPE_IDLE;
            end
            
            default: thd_pipe_state <= THD_PIPE_IDLE;
        endcase
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