//=============================================================================
// 文件名: lock_in_amplifier.v
// 描述: 数字锁相放大器 - 微弱信号检测
// 功能: 
//   1. 数字混频（正交解调）
//   2. 低通滤波（移动平均/CIC）
//   3. 幅度和相位提取
//   4. 可编程参考频率
// 原理: 将输入信号与参考信号相乘，经低通滤波后提取特定频率分量
//=============================================================================

module lock_in_amplifier #(
    parameter DATA_WIDTH = 16,      // 输入数据位宽
    parameter PHASE_WIDTH = 32,     // 相位累加器位宽（DDS）
    parameter LPF_ORDER = 8,        // 低通滤波器阶数（移动平均窗口大小：2^LPF_ORDER）
    parameter OUTPUT_WIDTH = 24     // 输出数据位宽
)(
    input  wire                         clk,
    input  wire                         rst_n,
    
    // 输入信号
    input  wire signed [DATA_WIDTH-1:0] signal_in,
    input  wire                         signal_valid,
    
    // 参考频率控制（频率调谐字：Fout = Fclk * freq_tuning / 2^32）
    input  wire [PHASE_WIDTH-1:0]       ref_freq_tuning,  // 参考频率设置
    input  wire                         ref_ext_enable,   // 外部参考使能
    input  wire signed [DATA_WIDTH-1:0] ref_ext_signal,   // 外部参考信号
    
    // 增益控制
    input  wire [3:0]                   gain_shift,       // 数字增益：0-15 (2^n增益)
    
    // I/Q输出
    output reg signed [OUTPUT_WIDTH-1:0] i_channel,       // 同相分量
    output reg signed [OUTPUT_WIDTH-1:0] q_channel,       // 正交分量
    output reg [OUTPUT_WIDTH-1:0]        magnitude,       // 幅度
    output reg [15:0]                    phase,           // 相位（0-65535对应0-360度）
    output reg                           result_valid,
    
    // 状态输出
    output wire                          locked            // 锁定指示
);

//=============================================================================
// 1. DDS参考信号生成器（正弦/余弦查找表）
//=============================================================================
reg [PHASE_WIDTH-1:0]   phase_acc;      // 相位累加器
wire [9:0]              sin_addr;       // 正弦表地址（1024点）

// 相位累加器
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        phase_acc <= 32'd0;
    else if (signal_valid)
        phase_acc <= phase_acc + ref_freq_tuning;
end

// 地址映射：使用高10位作为查找表索引
assign sin_addr = phase_acc[PHASE_WIDTH-1:PHASE_WIDTH-10];

// 正弦/余弦查找表（1024点，16位精度）
// 为了综合，使用ROM IP核或预定义的参数数组
// 这里使用简化方案：64点查找表 + 线性插值（节省资源）
// 或者使用CORDIC算法替代

// 方案1：使用简化的64点查找表（推荐用于FPGA综合）
function signed [15:0] sin_lut_func;
    input [9:0] addr;
    reg [5:0] base_addr;
    reg signed [15:0] lut_val;
    begin
        // 使用64点基础表 + 对称性
        base_addr = addr[5:0];  // 0-63
        
        // 第一象限的64个点（0-90度的1/4）
        case (base_addr)
            6'd0:  lut_val = 16'd0;
            6'd1:  lut_val = 16'd804;
            6'd2:  lut_val = 16'd1608;
            6'd3:  lut_val = 16'd2410;
            6'd4:  lut_val = 16'd3212;
            6'd5:  lut_val = 16'd4011;
            6'd6:  lut_val = 16'd4808;
            6'd7:  lut_val = 16'd5602;
            6'd8:  lut_val = 16'd6393;
            6'd9:  lut_val = 16'd7179;
            6'd10: lut_val = 16'd7962;
            6'd11: lut_val = 16'd8740;
            6'd12: lut_val = 16'd9512;
            6'd13: lut_val = 16'd10279;
            6'd14: lut_val = 16'd11039;
            6'd15: lut_val = 16'd11793;
            6'd16: lut_val = 16'd12540;
            6'd17: lut_val = 16'd13279;
            6'd18: lut_val = 16'd14010;
            6'd19: lut_val = 16'd14733;
            6'd20: lut_val = 16'd15447;
            6'd21: lut_val = 16'd16151;
            6'd22: lut_val = 16'd16846;
            6'd23: lut_val = 16'd17530;
            6'd24: lut_val = 16'd18205;
            6'd25: lut_val = 16'd18868;
            6'd26: lut_val = 16'd19520;
            6'd27: lut_val = 16'd20160;
            6'd28: lut_val = 16'd20788;
            6'd29: lut_val = 16'd21403;
            6'd30: lut_val = 16'd22006;
            6'd31: lut_val = 16'd22595;
            6'd32: lut_val = 16'd23170;
            6'd33: lut_val = 16'd23732;
            6'd34: lut_val = 16'd24279;
            6'd35: lut_val = 16'd24812;
            6'd36: lut_val = 16'd25330;
            6'd37: lut_val = 16'd25833;
            6'd38: lut_val = 16'd26320;
            6'd39: lut_val = 16'd26791;
            6'd40: lut_val = 16'd27246;
            6'd41: lut_val = 16'd27684;
            6'd42: lut_val = 16'd28106;
            6'd43: lut_val = 16'd28511;
            6'd44: lut_val = 16'd28899;
            6'd45: lut_val = 16'd29269;
            6'd46: lut_val = 16'd29622;
            6'd47: lut_val = 16'd29957;
            6'd48: lut_val = 16'd30274;
            6'd49: lut_val = 16'd30572;
            6'd50: lut_val = 16'd30853;
            6'd51: lut_val = 16'd31114;
            6'd52: lut_val = 16'd31357;
            6'd53: lut_val = 16'd31581;
            6'd54: lut_val = 16'd31786;
            6'd55: lut_val = 16'd31972;
            6'd56: lut_val = 16'd32138;
            6'd57: lut_val = 16'd32285;
            6'd58: lut_val = 16'd32413;
            6'd59: lut_val = 16'd32522;
            6'd60: lut_val = 16'd32610;
            6'd61: lut_val = 16'd32679;
            6'd62: lut_val = 16'd32729;
            6'd63: lut_val = 16'd32758;
            default: lut_val = 16'd0;
        endcase
        
        // 应用对称性
        case (addr[9:6])  // 象限判断
            4'b0000, 4'b0001: sin_lut_func = lut_val;                    // 0-90度
            4'b0010, 4'b0011: sin_lut_func = lut_val;                    // 90-180度 (使用镜像)
            4'b0100, 4'b0101: sin_lut_func = -lut_val;                   // 180-270度
            4'b0110, 4'b0111: sin_lut_func = -lut_val;                   // 270-360度
            4'b1000, 4'b1001: sin_lut_func = lut_val;                    
            4'b1010, 4'b1011: sin_lut_func = lut_val;
            4'b1100, 4'b1101: sin_lut_func = -lut_val;
            4'b1110, 4'b1111: sin_lut_func = -lut_val;
            default: sin_lut_func = 16'd0;
        endcase
    end
endfunction

// 余弦 = sin(x + 90度)
function signed [15:0] cos_lut_func;
    input [9:0] addr;
    begin
        cos_lut_func = sin_lut_func(addr + 10'd256);  // 相位偏移90度
    end
endfunction

reg signed [15:0] ref_sin;
reg signed [15:0] ref_cos;
reg               ref_valid;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        ref_sin   <= 16'd0;
        ref_cos   <= 16'd0;
        ref_valid <= 1'b0;
    end else begin
        // 使用函数查表
        ref_sin   <= ref_ext_enable ? ref_ext_signal : sin_lut_func(sin_addr);
        ref_cos   <= ref_ext_enable ? ref_ext_signal : cos_lut_func(sin_addr);  // cos = sin + 90度
        ref_valid <= signal_valid;
    end
end

//=============================================================================
// 2. 数字增益控制
//=============================================================================
reg signed [DATA_WIDTH+15:0] signal_gain;
reg                          gain_valid;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        signal_gain <= 0;
        gain_valid  <= 1'b0;
    end else begin
        // 可编程增益：signal * 2^gain_shift
        signal_gain <= signal_in <<< gain_shift;
        gain_valid  <= signal_valid;
    end
end

//=============================================================================
// 3. 混频器（相乘器）
//=============================================================================
reg signed [DATA_WIDTH+30:0] mixer_i;  // I通道混频结果
reg signed [DATA_WIDTH+30:0] mixer_q;  // Q通道混频结果
reg                          mixer_valid;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        mixer_i     <= 0;
        mixer_q     <= 0;
        mixer_valid <= 1'b0;
    end else if (gain_valid && ref_valid) begin
        // I = signal * cos(ωt)
        mixer_i     <= signal_gain * ref_cos;
        // Q = signal * sin(ωt)
        mixer_q     <= signal_gain * ref_sin;
        mixer_valid <= 1'b1;
    end else begin
        mixer_valid <= 1'b0;
    end
end

//=============================================================================
// 4. 低通滤波器（移动平均 - CIC风格）
//=============================================================================
localparam FILTER_SIZE = 1 << LPF_ORDER;  // 滤波器窗口大小

// I通道积分器
reg signed [OUTPUT_WIDTH+LPF_ORDER-1:0] i_integrator;
reg signed [OUTPUT_WIDTH+LPF_ORDER-1:0] i_comb;
reg signed [OUTPUT_WIDTH+LPF_ORDER-1:0] i_delay [0:FILTER_SIZE-1];

// Q通道积分器
reg signed [OUTPUT_WIDTH+LPF_ORDER-1:0] q_integrator;
reg signed [OUTPUT_WIDTH+LPF_ORDER-1:0] q_comb;
reg signed [OUTPUT_WIDTH+LPF_ORDER-1:0] q_delay [0:FILTER_SIZE-1];

reg [LPF_ORDER:0] filter_cnt;
reg               filter_valid;

// 移位寄存器索引
integer j;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        i_integrator <= 0;
        q_integrator <= 0;
        i_comb       <= 0;
        q_comb       <= 0;
        filter_cnt   <= 0;
        filter_valid <= 1'b0;
        
        for (j = 0; j < FILTER_SIZE; j = j + 1) begin
            i_delay[j] <= 0;
            q_delay[j] <= 0;
        end
    end else if (mixer_valid) begin
        // 积分级（累加）
        i_integrator <= i_integrator + mixer_i[DATA_WIDTH+30:DATA_WIDTH+30-OUTPUT_WIDTH-LPF_ORDER+1];
        q_integrator <= q_integrator + mixer_q[DATA_WIDTH+30:DATA_WIDTH+30-OUTPUT_WIDTH-LPF_ORDER+1];
        
        // 延迟链更新
        i_delay[0] <= i_integrator;
        q_delay[0] <= q_integrator;
        for (j = 1; j < FILTER_SIZE; j = j + 1) begin
            i_delay[j] <= i_delay[j-1];
            q_delay[j] <= q_delay[j-1];
        end
        
        // 梳状滤波器（差分）
        i_comb <= i_integrator - i_delay[FILTER_SIZE-1];
        q_comb <= q_integrator - q_delay[FILTER_SIZE-1];
        
        // 滤波计数
        if (filter_cnt < FILTER_SIZE)
            filter_cnt <= filter_cnt + 1'b1;
        
        // 滤波器稳定后输出有效
        filter_valid <= (filter_cnt >= FILTER_SIZE);
    end
end

//=============================================================================
// 5. 抽取和缩放
//=============================================================================
reg [7:0] decimation_cnt;
localparam DECIMATION_FACTOR = 8;  // 抽取因子

reg signed [OUTPUT_WIDTH-1:0] i_filtered;
reg signed [OUTPUT_WIDTH-1:0] q_filtered;
reg                           lpf_output_valid;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        decimation_cnt   <= 0;
        i_filtered       <= 0;
        q_filtered       <= 0;
        lpf_output_valid <= 1'b0;
    end else if (filter_valid) begin
        if (decimation_cnt == DECIMATION_FACTOR - 1) begin
            decimation_cnt   <= 0;
            // 缩放并截取输出
            i_filtered       <= i_comb >>> LPF_ORDER;
            q_filtered       <= q_comb >>> LPF_ORDER;
            lpf_output_valid <= 1'b1;
        end else begin
            decimation_cnt   <= decimation_cnt + 1'b1;
            lpf_output_valid <= 1'b0;
        end
    end else begin
        lpf_output_valid <= 1'b0;
    end
end

//=============================================================================
// 6. 幅度和相位计算
//=============================================================================
// 使用CORDIC算法或查找表，这里使用简化的近似方法

reg [OUTPUT_WIDTH-1:0] i_abs;
reg [OUTPUT_WIDTH-1:0] q_abs;
reg [OUTPUT_WIDTH-1:0] mag_calc;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        i_channel    <= 0;
        q_channel    <= 0;
        magnitude    <= 0;
        phase        <= 0;
        result_valid <= 1'b0;
    end else if (lpf_output_valid) begin
        i_channel <= i_filtered;
        q_channel <= q_filtered;
        
        // 计算绝对值
        i_abs <= (i_filtered[OUTPUT_WIDTH-1]) ? -i_filtered : i_filtered;
        q_abs <= (q_filtered[OUTPUT_WIDTH-1]) ? -q_filtered : q_filtered;
        
        // 幅度近似：mag ≈ max(|I|, |Q|) + 0.5*min(|I|, |Q|)
        if (i_abs > q_abs)
            mag_calc <= i_abs + (q_abs >> 1);
        else
            mag_calc <= q_abs + (i_abs >> 1);
        
        magnitude <= mag_calc;
        
        // 相位计算（简化版：使用ATAN2查找表）
        // 这里使用简单的象限判断
        if (i_filtered >= 0 && q_filtered >= 0)
            phase <= {2'b00, q_abs[OUTPUT_WIDTH-1:OUTPUT_WIDTH-14]};  // 第一象限
        else if (i_filtered < 0 && q_filtered >= 0)
            phase <= 16'h4000 - {2'b00, i_abs[OUTPUT_WIDTH-1:OUTPUT_WIDTH-14]};  // 第二象限
        else if (i_filtered < 0 && q_filtered < 0)
            phase <= 16'h8000 + {2'b00, q_abs[OUTPUT_WIDTH-1:OUTPUT_WIDTH-14]};  // 第三象限
        else
            phase <= 16'hC000 - {2'b00, i_abs[OUTPUT_WIDTH-1:OUTPUT_WIDTH-14]};  // 第四象限
        
        result_valid <= 1'b1;
    end else begin
        result_valid <= 1'b0;
    end
end

//=============================================================================
// 7. 锁定检测（幅度稳定性判断）
//=============================================================================
reg [OUTPUT_WIDTH-1:0] mag_history [0:15];
reg [3:0]              mag_ptr;
reg [OUTPUT_WIDTH-1:0] mag_max, mag_min;
reg                    lock_status;

integer k;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        mag_ptr     <= 0;
        mag_max     = 0;
        mag_min     = {OUTPUT_WIDTH{1'b1}};
        lock_status <= 1'b0;
        for (k = 0; k < 16; k = k + 1)
            mag_history[k] <= 0;
    end else if (result_valid) begin
        // 更新历史记录
        mag_history[mag_ptr] <= magnitude;
        mag_ptr <= mag_ptr + 1'b1;
        
        // 查找最大最小值
        mag_max = magnitude;
        mag_min = magnitude;
        for (k = 0; k < 16; k = k + 1) begin
            if (mag_history[k] > mag_max) mag_max = mag_history[k];
            if (mag_history[k] < mag_min) mag_min = mag_history[k];
        end
        
        // 锁定判断：波动小于10%
        if ((mag_max - mag_min) < (magnitude >> 3))  // < 12.5%
            lock_status <= 1'b1;
        else
            lock_status <= 1'b0;
    end
end

assign locked = lock_status;

endmodule
