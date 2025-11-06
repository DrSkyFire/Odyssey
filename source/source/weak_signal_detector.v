//=============================================================================
// 文件名: weak_signal_detector.v
// 描述: 微弱信号检测顶层模块
// 功能:
//   1. 多级数字增益控制
//   2. 锁相放大检测
//   3. SNR估计
//   4. 自动频率跟踪
//=============================================================================

module weak_signal_detector #(
    parameter DATA_WIDTH = 16,
    parameter OUTPUT_WIDTH = 24
)(
    input  wire                         clk,
    input  wire                         rst_n,
    
    // 双通道输入
    input  wire signed [DATA_WIDTH-1:0] ch1_data,
    input  wire signed [DATA_WIDTH-1:0] ch2_data,
    input  wire                         data_valid,
    
    // 参考信号配置
    input  wire [1:0]                   ref_mode,         // 0=内部DDS, 1=CH2作参考, 2=外部, 3=自动搜索
    input  wire [31:0]                  ref_frequency,    // 参考频率（Hz）
    input  wire [31:0]                  clk_frequency,    // 时钟频率（Hz）
    
    // 增益和滤波配置
    input  wire [3:0]                   digital_gain,     // 数字增益：0-15 (对应1x-32768x)
    input  wire [3:0]                   lpf_time_constant,// 低通滤波器时间常数（2^n采样点）
    input  wire                         auto_gain_enable, // 自动增益控制使能
    
    // 检测结果 - 通道1
    output wire signed [OUTPUT_WIDTH-1:0] ch1_i_component,
    output wire signed [OUTPUT_WIDTH-1:0] ch1_q_component,
    output wire [OUTPUT_WIDTH-1:0]        ch1_magnitude,
    output wire [15:0]                    ch1_phase,
    output wire                           ch1_locked,
    output wire                           ch1_valid,
    
    // 检测结果 - 通道2（可选：用于相位差测量）
    output wire signed [OUTPUT_WIDTH-1:0] ch2_i_component,
    output wire signed [OUTPUT_WIDTH-1:0] ch2_q_component,
    output wire [OUTPUT_WIDTH-1:0]        ch2_magnitude,
    output wire [15:0]                    ch2_phase,
    output wire                           ch2_locked,
    output wire                           ch2_valid,
    
    // 信噪比估计
    output reg [15:0]                     snr_estimate,    // SNR in dB (8.8定点)
    output reg                            snr_valid,
    
    // 状态输出
    output reg [3:0]                      current_gain,    // 当前增益
    output reg [31:0]                     detected_freq    // 检测到的频率
);

//=============================================================================
// 1. 频率调谐字计算
//=============================================================================
// Tuning_Word = (Fout / Fclk) * 2^32
reg [31:0] freq_tuning_word;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        freq_tuning_word <= 32'd0;
    else begin
        // 简化计算：TW = (Fref << 32) / Fclk
        // 实际使用时需要用除法器IP或查找表
        freq_tuning_word <= (ref_frequency << 16) / (clk_frequency >> 16);
    end
end

//=============================================================================
// 2. 参考信号选择
//=============================================================================
reg                        ref_ext_en;
reg signed [DATA_WIDTH-1:0] ref_signal;

always @(*) begin
    case (ref_mode)
        2'b00: begin  // 内部DDS
            ref_ext_en = 1'b0;
            ref_signal = 16'd0;
        end
        2'b01: begin  // CH2作为参考
            ref_ext_en = 1'b1;
            ref_signal = ch2_data;
        end
        2'b10: begin  // 外部参考（预留）
            ref_ext_en = 1'b1;
            ref_signal = 16'd0;  // 需要外部输入端口
        end
        default: begin  // 自动搜索模式
            ref_ext_en = 1'b0;
            ref_signal = 16'd0;
        end
    endcase
end

//=============================================================================
// 3. 自动增益控制（AGC）
//=============================================================================
reg [3:0] agc_gain;
reg [7:0] agc_update_cnt;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        agc_gain        <= 4'd4;  // 默认16x增益
        agc_update_cnt  <= 8'd0;
        current_gain    <= 4'd4;
    end else if (auto_gain_enable && ch1_valid) begin
        // 每256个样本更新一次
        if (agc_update_cnt == 8'd255) begin
            agc_update_cnt <= 8'd0;
            
            // 根据输出幅度调整增益
            if (ch1_magnitude < 24'h010000 && agc_gain < 4'd15)  // 太小，增加增益
                agc_gain <= agc_gain + 1'b1;
            else if (ch1_magnitude > 24'h700000 && agc_gain > 4'd0)  // 太大，减小增益
                agc_gain <= agc_gain - 1'b1;
            
            current_gain <= agc_gain;
        end else begin
            agc_update_cnt <= agc_update_cnt + 1'b1;
        end
    end else begin
        current_gain <= digital_gain;
    end
end

wire [3:0] final_gain = auto_gain_enable ? agc_gain : digital_gain;

//=============================================================================
// 4. 通道1锁相放大器实例化
//=============================================================================
// 注意：LPF_ORDER统一为8（256点滤波），保证双通道一致性
lock_in_amplifier #(
    .DATA_WIDTH     (DATA_WIDTH),
    .PHASE_WIDTH    (32),
    .LPF_ORDER      (8),  // 统一为8（256点滤波），与CH2一致
    .OUTPUT_WIDTH   (OUTPUT_WIDTH)
) u_lia_ch1 (
    .clk                (clk),
    .rst_n              (rst_n),
    .signal_in          (ch1_data),
    .signal_valid       (data_valid),
    .ref_freq_tuning    (freq_tuning_word),
    .ref_ext_enable     (ref_ext_en),
    .ref_ext_signal     (ref_signal),
    .gain_shift         (final_gain),
    .i_channel          (ch1_i_component),
    .q_channel          (ch1_q_component),
    .magnitude          (ch1_magnitude),
    .phase              (ch1_phase),
    .result_valid       (ch1_valid),
    .locked             (ch1_locked)
);

//=============================================================================
// 5. 通道2锁相放大器实例化（用于相位差测量）
//=============================================================================
lock_in_amplifier #(
    .DATA_WIDTH     (DATA_WIDTH),
    .PHASE_WIDTH    (32),
    .LPF_ORDER      (8),  // 固定为8（256点滤波）
    .OUTPUT_WIDTH   (OUTPUT_WIDTH)
) u_lia_ch2 (
    .clk                (clk),
    .rst_n              (rst_n),
    .signal_in          (ch2_data),
    .signal_valid       (data_valid),
    .ref_freq_tuning    (freq_tuning_word),
    .ref_ext_enable     (1'b0),  // CH2始终使用内部DDS
    .ref_ext_signal     (16'd0),
    .gain_shift         (final_gain),
    .i_channel          (ch2_i_component),
    .q_channel          (ch2_q_component),
    .magnitude          (ch2_magnitude),
    .phase              (ch2_phase),
    .result_valid       (ch2_valid),
    .locked             (ch2_locked)
);

//=============================================================================
// 6. SNR估计（信号功率/噪声功率）
//=============================================================================
reg [OUTPUT_WIDTH-1:0] signal_power;
reg [OUTPUT_WIDTH-1:0] noise_power;
reg [15:0]             snr_counter;

// 简化SNR估计：使用锁定时的幅度作为信号，波动作为噪声
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        signal_power <= 0;
        noise_power  <= 1;
        snr_estimate <= 0;
        snr_valid    <= 1'b0;
        snr_counter  <= 0;
    end else if (ch1_valid) begin
        if (snr_counter == 16'd1000) begin  // 每1000个样本更新一次
            snr_counter  <= 0;
            
            // 信号功率 = 平均幅度
            signal_power <= ch1_magnitude;
            
            // 噪声功率估计（当前实现简化）
            if (ch1_locked)
                noise_power <= 1;  // 锁定时噪声很小
            else
                noise_power <= signal_power >> 2;  // 未锁定时假设25%是噪声
            
            // SNR计算（简化：使用对数近似）
            // SNR_dB ≈ 20*log10(Signal/Noise)
            // 这里简化为比值的位移近似
            if (noise_power > 0) begin
                snr_estimate <= (signal_power / noise_power) << 4;  // 粗略估计
            end
            
            snr_valid <= 1'b1;
        end else begin
            snr_counter <= snr_counter + 1'b1;
            snr_valid   <= 1'b0;
        end
    end
end

//=============================================================================
// 7. 频率跟踪（峰值检测）
//=============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        detected_freq <= 32'd0;
    else if (ch1_locked)
        detected_freq <= ref_frequency;  // 锁定时输出设定频率
    else
        detected_freq <= 32'd0;
end

endmodule
