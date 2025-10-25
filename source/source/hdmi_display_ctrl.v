//=============================================================================
// 文件名: hdmi_display_ctrl.v (美化增强版 - 带参数显示 + 双通道独立控制)
// 描述: 1080p HDMI显示控制器
//       - 上部：双通道频谱/波形显示（带网格线）
//       - 下部：参数信息显示（大字体）
//       - 支持独立通道开关：CH1(绿色) CH2(红色)
//       - 配色：渐变频谱 + 深色背景 + 白色文字
//=============================================================================

module hdmi_display_ctrl (
    input  wire         clk_pixel,
    input  wire         rst_n,
    
    // ✅ 双通道数据接口
    input  wire [15:0]  ch1_data,       // 通道1数据（时域/频域共用）
    input  wire [15:0]  ch2_data,       // 通道2数据（时域/频域共用）
    output reg  [12:0]  spectrum_addr,  // ✓ 改为13位以支持8192点FFT
    
    // 参数输入
    input  wire [15:0]  freq,           // 频率 (Hz)
    input  wire [15:0]  amplitude,      // 幅度
    input  wire [15:0]  duty,           // 占空比 (0-1000 = 0-100%)
    input  wire [15:0]  thd,            // THD (0-1000 = 0-100%)
    input  wire [15:0]  phase_diff,     // 相位差 (0-3599 = 0-359.9°)
    
    // ✅ 双通道独立控制（替代current_channel）
    input  wire         ch1_enable,     // 通道1显示使能
    input  wire         ch2_enable,     // 通道2显示使能
    
    input  wire [1:0]   work_mode,
    
    // HDMI输出
    output wire [23:0]  rgb_out,
    output wire         de_out,
    output wire         hs_out,
    output wire         vs_out
);

//=============================================================================
// 时序参数 - 1080p@60Hz
//=============================================================================
localparam H_ACTIVE     = 1920;
localparam H_FP         = 88;
localparam H_SYNC       = 44;
localparam H_BP         = 148;
localparam H_TOTAL      = 2200;

localparam V_ACTIVE     = 1080;
localparam V_FP         = 4;
localparam V_SYNC       = 5;
localparam V_BP         = 36;
localparam V_TOTAL      = 1125;

//=============================================================================
// 显示区域参数 (1080p)
//=============================================================================
localparam SPECTRUM_Y_START = 75;       // 频谱区域起始Y
localparam SPECTRUM_Y_END   = 825;      // 频谱区域结束Y
localparam PARAM_Y_START    = 870;      // 参数区域起始Y
localparam PARAM_Y_END      = 1065;     // 参数区域结束Y

//=============================================================================
// 信号定义
//=============================================================================
reg [11:0] h_cnt;
reg [11:0] v_cnt;
reg        h_active;
reg        v_active;
wire       video_active;

reg [11:0] pixel_x;
reg [11:0] pixel_y;

reg        hs_internal;
reg        vs_internal;

// 延迟寄存器（匹配RAM和字符ROM延迟）
reg [11:0] pixel_x_d1, pixel_x_d2, pixel_x_d3;
reg [11:0] pixel_y_d1, pixel_y_d2, pixel_y_d3;
reg        video_active_d1, video_active_d2, video_active_d3;
reg [1:0]  work_mode_d1, work_mode_d2, work_mode_d3;

// 网格线标志（预计算，避免取模运算）
reg        grid_x_flag, grid_y_flag;

// ✅ 双通道波形相关信号
reg [15:0] ch1_data_q, ch2_data_q;  // 双通道数据寄存器
reg [11:0] ch1_waveform_height;     // CH1波形高度
reg [11:0] ch2_waveform_height;     // CH2波形高度

// 兼容旧变量名
reg [15:0] time_data_q;             // 时域数据寄存器（兼容）
reg [15:0] spectrum_data_q;         // 频谱数据寄存器（兼容）
reg [11:0] waveform_height;         // 波形高度计算结果（兼容）
wire [11:0] time_sample_x;          // 时域采样点X坐标（1920点对应8192采样点，压缩显示）

// 时域波形参数
localparam WAVEFORM_CENTER_Y = (SPECTRUM_Y_START + SPECTRUM_Y_END) / 2;  // 波形中心线
reg        grid_x_flag_d1, grid_y_flag_d1;
reg        grid_x_flag_d2, grid_y_flag_d2;
reg        grid_x_flag_d3, grid_y_flag_d3;
// ✅ 流水线优化：新增第4级延迟
reg        grid_x_flag_d4, grid_y_flag_d4;
reg [1:0]  work_mode_d4;
reg [11:0] pixel_x_d4, pixel_y_d4;

// 网格计数器（每行重置,避免大数取模）
reg [6:0]  grid_x_cnt;  // 0-99 循环
reg [5:0]  grid_y_cnt;  // 0-49 循环

// (✅ spectrum_data_q已在上面双通道部分声明，删除此处重复声明)

// ✅ 双通道波形绘制辅助信号
reg        ch1_hit, ch2_hit;    // 波形命中标志（Stage 4计算结果）
reg [11:0] ch1_spectrum_height; // CH1频谱高度
reg [11:0] ch2_spectrum_height; // CH2频谱高度

// ✅ 流水线优化：Stage 3输出寄存器
reg [11:0] ch1_waveform_calc_d1, ch2_waveform_calc_d1;  // 波形高度计算结果
reg [11:0] ch1_spectrum_calc_d1, ch2_spectrum_calc_d1;  // 频谱高度计算结果
reg        ch1_enable_d4, ch2_enable_d4;                 // 通道使能同步

// ✅ 方案3优化：频谱命中检测信号（避免在always块内声明）
reg        ch1_spec_hit, ch2_spec_hit;

reg [23:0] rgb_out_reg;
reg        de_out_reg;
reg        hs_out_reg;
reg        vs_out_reg;

reg [23:0] rgb_data;
reg [11:0] spectrum_height_calc;

// 字符显示相关
wire [15:0] char_pixel_row;
reg [5:0]   char_code;
reg [4:0]   char_row;
reg [3:0]   char_col;
reg         in_char_area;
reg [23:0]  char_color;

// 数字分解
reg [3:0]   digit_0, digit_1, digit_2, digit_3, digit_4;

// 预计算的数字（每帧更新一次，避免实时除法）
reg [3:0]   freq_d0, freq_d1, freq_d2, freq_d3, freq_d4;
reg [3:0]   amp_d0, amp_d1, amp_d2, amp_d3;
reg [3:0]   duty_d0, duty_d1, duty_d2;
reg [3:0]   thd_d0, thd_d1, thd_d2;
reg [3:0]   phase_d0, phase_d1, phase_d2, phase_d3;

//=============================================================================
// 行计数器
//=============================================================================
always @(posedge clk_pixel or negedge rst_n) begin
    if (!rst_n)
        h_cnt <= 12'd0;
    else if (h_cnt == H_TOTAL - 1)
        h_cnt <= 12'd0;
    else
        h_cnt <= h_cnt + 1'b1;
end

//=============================================================================
// 场计数器
//=============================================================================
always @(posedge clk_pixel or negedge rst_n) begin
    if (!rst_n)
        v_cnt <= 12'd0;
    else if (h_cnt == H_TOTAL - 1) begin
        if (v_cnt == V_TOTAL - 1)
            v_cnt <= 12'd0;
        else
            v_cnt <= v_cnt + 1'b1;
    end
end

//=============================================================================
// 同步信号 (正极性 - 与MS7210兼容)
// 参考官方例程: hs = (h_cnt < H_SYNC)
//=============================================================================
always @(posedge clk_pixel or negedge rst_n) begin
    if (!rst_n)
        hs_internal <= 1'b0;
    else
        hs_internal <= (h_cnt < H_SYNC);  // 前40个周期为高（正极性）
end

always @(posedge clk_pixel or negedge rst_n) begin
    if (!rst_n)
        vs_internal <= 1'b0;
    else begin
        if (v_cnt == 12'd0)
            vs_internal <= 1'b1;        // 场计数器归0时，VS拉高
        else if (v_cnt == V_SYNC)
            vs_internal <= 1'b0;        // V_SYNC个周期后，VS拉低
        else
            vs_internal <= vs_internal; // 保持当前值（关键！）
    end
end

//=============================================================================
// 有效区域标志 (组合逻辑 - 与官方例程一致)
//=============================================================================
wire h_active_comb = (h_cnt >= (H_SYNC + H_BP)) && (h_cnt <= (H_TOTAL - H_FP - 1));
wire v_active_comb = (v_cnt >= (V_SYNC + V_BP)) && (v_cnt <= (V_TOTAL - V_FP - 1));
assign video_active = h_active_comb && v_active_comb;

// 保留寄存器版本用于其他用途（如果需要）
always @(posedge clk_pixel or negedge rst_n) begin
    if (!rst_n) begin
        h_active <= 1'b0;
        v_active <= 1'b0;
    end else begin
        h_active <= h_active_comb;
        v_active <= v_active_comb;
    end
end

//=============================================================================
// 像素坐标 (相对于有效区域起始位置)
//=============================================================================
always @(posedge clk_pixel or negedge rst_n) begin
    if (!rst_n) begin
        pixel_x <= 12'd0;
        pixel_y <= 12'd0;
    end else begin
        // 坐标从SYNC+BP开始计算
        if (h_cnt >= (H_SYNC + H_BP))
            pixel_x <= h_cnt - (H_SYNC + H_BP);
        else
            pixel_x <= 12'd0;
            
        if (v_cnt >= (V_SYNC + V_BP))
            pixel_y <= v_cnt - (V_SYNC + V_BP);
        else
            pixel_y <= 12'd0;
    end
end

//=============================================================================
// 网格计数器和标志（避免昂贵的取模运算）
//=============================================================================
always @(posedge clk_pixel or negedge rst_n) begin
    if (!rst_n) begin
        grid_x_cnt <= 7'd0;
        grid_x_flag <= 1'b0;
    end else begin
        if (h_cnt == H_TOTAL - 1) begin
            grid_x_cnt <= 7'd0;
            grid_x_flag <= 1'b1;
        end else if (grid_x_cnt == 7'd99) begin
            grid_x_cnt <= 7'd0;
            grid_x_flag <= 1'b1;
        end else begin
            grid_x_cnt <= grid_x_cnt + 1'b1;
            grid_x_flag <= 1'b0;
        end
    end
end

always @(posedge clk_pixel or negedge rst_n) begin
    if (!rst_n) begin
        grid_y_cnt <= 6'd0;
        grid_y_flag <= 1'b0;
    end else begin
        if (h_cnt == H_TOTAL - 1) begin
            if (v_cnt == V_TOTAL - 1) begin
                grid_y_cnt <= 6'd0;
                grid_y_flag <= 1'b1;
            end else if (grid_y_cnt == 6'd49) begin
                grid_y_cnt <= 6'd0;
                grid_y_flag <= 1'b1;
            end else begin
                grid_y_cnt <= grid_y_cnt + 1'b1;
                grid_y_flag <= (grid_y_cnt + 1'b1 == 6'd49);
            end
        end
    end
end

//=============================================================================
// 频谱地址生成（提前生成）
// 8192点FFT压缩到1920像素显示：每像素对应约4.27个频谱点
// 映射公式：spectrum_addr = (h_cnt * 8192) / 1920 ≈ h_cnt * 4.27 ≈ h_cnt << 2 + h_cnt >> 2
//=============================================================================
always @(posedge clk_pixel or negedge rst_n) begin
    if (!rst_n)
        spectrum_addr <= 13'd0;
    else begin
        if (h_cnt < H_ACTIVE) begin
            // spectrum_addr = h_cnt * 4 + h_cnt / 4 ≈ h_cnt * 4.25
            // 更精确方法：(h_cnt << 2) + (h_cnt >> 2) 
            spectrum_addr <= (h_cnt << 2) + {2'b00, h_cnt[11:2]};  // ≈ h_cnt * 4.25
        end else
            spectrum_addr <= 13'd8191;  // 超出范围时指向最后一个点
    end
end

//=============================================================================
// 参数数字预计算（每帧更新，避免实时除法造成时序违例）
//=============================================================================
always @(posedge clk_pixel or negedge rst_n) begin
    if (!rst_n) begin
        freq_d0 <= 4'd0; freq_d1 <= 4'd0; freq_d2 <= 4'd0; freq_d3 <= 4'd0; freq_d4 <= 4'd0;
        amp_d0 <= 4'd0; amp_d1 <= 4'd0; amp_d2 <= 4'd0; amp_d3 <= 4'd0;
        duty_d0 <= 4'd0; duty_d1 <= 4'd0; duty_d2 <= 4'd0;
        thd_d0 <= 4'd0; thd_d1 <= 4'd0; thd_d2 <= 4'd0;
        phase_d0 <= 4'd0; phase_d1 <= 4'd0; phase_d2 <= 4'd0; phase_d3 <= 4'd0;
    end else begin
        // 在场消隐期间更新（v_cnt == 0, h_cnt == 0），有充足时间计算
        if (v_cnt == 12'd0 && h_cnt == 12'd0) begin
            // 频率（5位数字）
            freq_d0 <= freq % 10;
            freq_d1 <= (freq / 10) % 10;
            freq_d2 <= (freq / 100) % 10;
            freq_d3 <= (freq / 1000) % 10;
            freq_d4 <= (freq / 10000) % 10;
            
            // 幅度（4位数字）
            amp_d0 <= amplitude % 10;
            amp_d1 <= (amplitude / 10) % 10;
            amp_d2 <= (amplitude / 100) % 10;
            amp_d3 <= (amplitude / 1000) % 10;
            
            // 占空比（3位数字，0-100.0）
            duty_d0 <= duty % 10;
            duty_d1 <= (duty / 10) % 10;
            duty_d2 <= (duty / 100) % 10;
            
            // THD（3位数字，0-100.0）
            thd_d0 <= thd % 10;
            thd_d1 <= (thd / 10) % 10;
            thd_d2 <= (thd / 100) % 10;
            
            // 相位差（4位数字，0-359.9）
            phase_d0 <= phase_diff % 10;
            phase_d1 <= (phase_diff / 10) % 10;
            phase_d2 <= (phase_diff / 100) % 10;
            phase_d3 <= (phase_diff / 1000) % 10;
        end
    end
end

//=============================================================================
// 坐标和控制信号延迟（匹配RAM读延迟）
//=============================================================================
always @(posedge clk_pixel or negedge rst_n) begin
    if (!rst_n) begin
        pixel_x_d1 <= 12'd0;
        pixel_x_d2 <= 12'd0;
        pixel_x_d3 <= 12'd0;
        pixel_y_d1 <= 12'd0;
        pixel_y_d2 <= 12'd0;
        pixel_y_d3 <= 12'd0;
        video_active_d1 <= 1'b0;
        video_active_d2 <= 1'b0;
        video_active_d3 <= 1'b0;
        work_mode_d1 <= 2'd0;
        work_mode_d2 <= 2'd0;
        work_mode_d3 <= 2'd0;
        grid_x_flag_d1 <= 1'b0;
        grid_x_flag_d2 <= 1'b0;
        grid_x_flag_d3 <= 1'b0;
        grid_y_flag_d1 <= 1'b0;
        grid_y_flag_d2 <= 1'b0;
        grid_y_flag_d3 <= 1'b0;
        spectrum_data_q <= 16'd0;
    end else begin
        // 延迟3拍（匹配字符ROM）
        pixel_x_d1 <= pixel_x;
        pixel_x_d2 <= pixel_x_d1;
        pixel_x_d3 <= pixel_x_d2;
        pixel_y_d1 <= pixel_y;
        pixel_y_d2 <= pixel_y_d1;
        pixel_y_d3 <= pixel_y_d2;
        video_active_d1 <= video_active;
        video_active_d2 <= video_active_d1;
        video_active_d3 <= video_active_d2;
        work_mode_d1 <= work_mode;
        work_mode_d2 <= work_mode_d1;
        work_mode_d3 <= work_mode_d2;
        grid_x_flag_d1 <= grid_x_flag;
        grid_x_flag_d2 <= grid_x_flag_d1;
        grid_x_flag_d3 <= grid_x_flag_d2;
        grid_y_flag_d1 <= grid_y_flag;
        grid_y_flag_d2 <= grid_y_flag_d1;
        grid_y_flag_d3 <= grid_y_flag_d2;
        
        // ✅ 流水线优化：Stage 4延迟
        grid_x_flag_d4 <= grid_x_flag_d3;
        grid_y_flag_d4 <= grid_y_flag_d3;
        work_mode_d4 <= work_mode_d3;
        pixel_x_d4 <= pixel_x_d3;
        pixel_y_d4 <= pixel_y_d3;
        ch1_enable_d4 <= ch1_enable;
        ch2_enable_d4 <= ch2_enable;
        
        // ✅ 双通道数据采样（3级流水线匹配显示延迟）
        ch1_data_q <= ch1_data;
        ch2_data_q <= ch2_data;
        
        // ✅ 流水线优化：Stage 3 - 仅计算波形/频谱高度
        ch1_waveform_calc_d1 <= ch1_waveform_height;
        ch2_waveform_calc_d1 <= ch2_waveform_height;
        ch1_spectrum_calc_d1 <= ch1_spectrum_height;
        ch2_spectrum_calc_d1 <= ch2_spectrum_height;
        
        // 兼容旧变量名（用于调试显示）
        spectrum_data_q <= ch1_enable ? ch1_data : ch2_data;
        time_data_q <= ch1_enable ? ch1_data : ch2_data;
    end
end

//=============================================================================
// 时域波形参数计算
//=============================================================================
// 时域采样点X坐标映射：1920像素 -> 8192采样点
// spectrum_addr范围0-8191，映射到0-1919
// 计算公式：x = (spectrum_addr * 1920) / 8192 ≈ spectrum_addr / 4.27
// 简化：x ≈ spectrum_addr >> 2（取每4个点）
assign time_sample_x = {1'b0, spectrum_addr[12:2]};  // 除以4，得到0-2047范围

//=============================================================================
// ✅ 双通道波形高度计算（Stage 3组合逻辑）
//=============================================================================
always @(*) begin
    // CH1波形高度计算
    if (ch1_data_q[15:6] > 10'd350)
        ch1_waveform_height = 12'd700;
    else
        ch1_waveform_height = {1'b0, ch1_data_q[15:6], 1'b0};  // 乘以2
    
    // CH2波形高度计算
    if (ch2_data_q[15:6] > 10'd350)
        ch2_waveform_height = 12'd700;
    else
        ch2_waveform_height = {1'b0, ch2_data_q[15:6], 1'b0};  // 乘以2
    
    // 兼容旧变量（用于其他地方）
    waveform_height = ch1_enable ? ch1_waveform_height : ch2_waveform_height;
end

//=============================================================================
// ✅ 流水线优化：Stage 4 - 波形命中检测（时序关键路径）
//=============================================================================
always @(posedge clk_pixel or negedge rst_n) begin
    if (!rst_n) begin
        ch1_hit <= 1'b0;
        ch2_hit <= 1'b0;
    end else begin
        // CH1波形命中检测（使用Stage 3的计算结果）
        if (ch1_waveform_calc_d1 >= 12'd350) begin
            // 波形在上半部分
            ch1_hit <= (pixel_y_d3 >= (WAVEFORM_CENTER_Y - (ch1_waveform_calc_d1 - 12'd350) - 12'd2)) &&
                       (pixel_y_d3 <= (WAVEFORM_CENTER_Y - (ch1_waveform_calc_d1 - 12'd350) + 12'd2));
        end else begin
            // 波形在下半部分
            ch1_hit <= (pixel_y_d3 >= (WAVEFORM_CENTER_Y + (12'd350 - ch1_waveform_calc_d1) - 12'd2)) &&
                       (pixel_y_d3 <= (WAVEFORM_CENTER_Y + (12'd350 - ch1_waveform_calc_d1) + 12'd2));
        end
        
        // CH2波形命中检测
        if (ch2_waveform_calc_d1 >= 12'd350) begin
            ch2_hit <= (pixel_y_d3 >= (WAVEFORM_CENTER_Y - (ch2_waveform_calc_d1 - 12'd350) - 12'd2)) &&
                       (pixel_y_d3 <= (WAVEFORM_CENTER_Y - (ch2_waveform_calc_d1 - 12'd350) + 12'd2));
        end else begin
            ch2_hit <= (pixel_y_d3 >= (WAVEFORM_CENTER_Y + (12'd350 - ch2_waveform_calc_d1) - 12'd2)) &&
                       (pixel_y_d3 <= (WAVEFORM_CENTER_Y + (12'd350 - ch2_waveform_calc_d1) + 12'd2));
        end
    end
end

//=============================================================================
// 字符ROM实例化
//=============================================================================
char_rom_16x32 u_char_rom (
    .char_code  (char_code),
    .row        (char_row),
    .pixel_row  (char_pixel_row)
);

//=============================================================================
// 数字分解函数
//=============================================================================
function [3:0] get_digit;
    input [15:0] number;
    input [2:0]  position;  // 0=个位, 1=十位, 2=百位, 3=千位, 4=万位
    reg [15:0] temp;
    begin
        temp = number;
        case (position)
            3'd0: get_digit = temp % 10;
            3'd1: get_digit = (temp / 10) % 10;
            3'd2: get_digit = (temp / 100) % 10;
            3'd3: get_digit = (temp / 1000) % 10;
            3'd4: get_digit = (temp / 10000) % 10;
            default: get_digit = 4'd0;
        endcase
    end
endfunction

//=============================================================================
// 参数显示字符生成（提前1拍生成，给ROM时间）
//=============================================================================
always @(posedge clk_pixel) begin
    char_code = 6'd15;  // 默认空格
    char_row = 5'd0;
    char_col = 4'd0;
    in_char_area = 1'b0;
    
    // 判断是否在参数显示区域
    if (pixel_y_d1 >= PARAM_Y_START && pixel_y_d1 < PARAM_Y_END) begin
        
        // 第1行: "Freq: XXXXX Hz"
        if (pixel_y_d1 < PARAM_Y_START + 40) begin
            char_row = pixel_y_d1[4:0];  // ✅ 修正：使用相对于PARAM_Y_START的行号
            if (pixel_x_d1 >= 40 && pixel_x_d1 < 56) begin
                char_code = 6'd13; // 'F'
                char_col = pixel_x_d1[3:0];
                in_char_area = 1'b1;
            end
            else if (pixel_x_d1 >= 70 && pixel_x_d1 < 86) begin
                char_code = 6'd11; // ':'
                char_col = pixel_x_d1[3:0] - 14;
                in_char_area = 1'b1;
            end
            // 显示频率数值 (5位数) - 使用预计算值
            else if (pixel_x_d1 >= 100 && pixel_x_d1 < 196) begin
                case (pixel_x_d1[11:5])
                    7'd3: begin  // 万位
                        char_code = {2'b00, freq_d4};
                        char_col = pixel_x_d1[4:0] - 5'd4;
                        in_char_area = 1'b1;
                    end
                    7'd4: begin  // 千位
                        char_code = {2'b00, freq_d3};
                        char_col = pixel_x_d1[4:0] - 5'd4;
                        in_char_area = 1'b1;
                    end
                    7'd5: begin  // 百位
                        char_code = {2'b00, freq_d2};
                        char_col = pixel_x_d1[4:0] - 5'd4;
                        in_char_area = 1'b1;
                    end
                    7'd6: begin  // 十位
                        char_code = {2'b00, freq_d1};
                        char_col = pixel_x_d1[4:0] - 5'd4;
                        in_char_area = 1'b1;
                    end
                    7'd7: begin  // 个位
                        char_code = {2'b00, freq_d0};
                        char_col = pixel_x_d1[4:0] - 5'd4;
                        in_char_area = 1'b1;
                    end
                endcase
            end
            // " Hz"
            else if (pixel_x_d1 >= 210 && pixel_x_d1 < 226) begin
                char_code = 6'd13; // 'H'
                char_col = pixel_x_d1[3:0] - 4'd2;
                in_char_area = 1'b1;
            end
            else if (pixel_x_d1 >= 230 && pixel_x_d1 < 246) begin
                char_code = 6'd14; // 'z'
                char_col = pixel_x_d1[3:0] - 4'd6;
                in_char_area = 1'b1;
            end
        end
        
        // 第2行: "Amp: XXXX"
        else if (pixel_y_d1 >= PARAM_Y_START + 45 && pixel_y_d1 < PARAM_Y_START + 85) begin
            char_row = pixel_y_d1 - PARAM_Y_START - 12'd45;  // 修正：直接计算相对行号
            if (pixel_x_d1 >= 340 && pixel_x_d1 < 356) begin
                char_code = 6'd13; // 'A' (用H代替)
                char_col = pixel_x_d1[3:0] - 4'd4;
                in_char_area = 1'b1;
            end
            else if (pixel_x_d1 >= 370 && pixel_x_d1 < 386) begin
                char_code = 6'd11; // ':'
                char_col = pixel_x_d1[3:0] - 4'd2;
                in_char_area = 1'b1;
            end
            // 显示幅度 (4位数) - 使用预计算值
            else if (pixel_x_d1 >= 400 && pixel_x_d1 < 480) begin
                case ((pixel_x_d1 - 400) >> 4)
                    4'd0: begin
                        char_code = {2'b00, amp_d3};
                        char_col = pixel_x_d1[3:0];
                        in_char_area = 1'b1;
                    end
                    4'd1: begin
                        char_code = {2'b00, amp_d2};
                        char_col = pixel_x_d1[3:0];
                        in_char_area = 1'b1;
                    end
                    4'd2: begin
                        char_code = {2'b00, amp_d1};
                        char_col = pixel_x_d1[3:0];
                        in_char_area = 1'b1;
                    end
                    4'd3: begin
                        char_code = {2'b00, amp_d0};
                        char_col = pixel_x_d1[3:0];
                        in_char_area = 1'b1;
                    end
                endcase
            end
        end
        
        // 第3行: "Duty: XX.X %" - 使用预计算值
        else if (pixel_y_d1 >= PARAM_Y_START + 90 && pixel_y_d1 < PARAM_Y_START + 130) begin
            char_row = pixel_y_d1 - PARAM_Y_START - 12'd90;  // 修正：直接计算相对行号
            if (pixel_x_d1 >= 640 && pixel_x_d1 < 720) begin
                case ((pixel_x_d1 - 640) >> 4)
                    4'd0: begin
                        char_code = {2'b00, duty_d2};  // 百位（十位）
                        char_col = pixel_x_d1[3:0];
                        in_char_area = 1'b1;
                    end
                    4'd1: begin
                        char_code = {2'b00, duty_d1};  // 十位（个位）
                        char_col = pixel_x_d1[3:0];
                        in_char_area = 1'b1;
                    end
                    4'd2: begin
                        char_code = 6'd10;  // '.'
                        char_col = pixel_x_d1[3:0];
                        in_char_area = 1'b1;
                    end
                    4'd3: begin
                        char_code = {2'b00, duty_d0};  // 个位（小数位）
                        char_col = pixel_x_d1[3:0];
                        in_char_area = 1'b1;
                    end
                    4'd4: begin
                        char_code = 6'd12;  // '%'
                        char_col = pixel_x_d1[3:0];
                        in_char_area = 1'b1;
                    end
                endcase
            end
        end
        
        // 第4行: "THD: X.XX %" - 使用预计算值
        else if (pixel_y_d1 >= PARAM_Y_START + 135 && pixel_y_d1 < PARAM_Y_START + 175) begin
            char_row = pixel_y_d1 - PARAM_Y_START - 12'd135;  // 修正：直接计算相对行号
            if (pixel_x_d1 >= 940 && pixel_x_d1 < 1020) begin
                case ((pixel_x_d1 - 940) >> 4)
                    4'd0: begin
                        char_code = {2'b00, thd_d2};  // 百位（个位）
                        char_col = pixel_x_d1[3:0];
                        in_char_area = 1'b1;
                    end
                    4'd1: begin
                        char_code = 6'd10;  // '.'
                        char_col = pixel_x_d1[3:0];
                        in_char_area = 1'b1;
                    end
                    4'd2: begin
                        char_code = {2'b00, thd_d1};  // 十位（小数第1位）
                        char_col = pixel_x_d1[3:0];
                        in_char_area = 1'b1;
                    end
                    4'd3: begin
                        char_code = {2'b00, thd_d0};  // 个位（小数第2位）
                        char_col = pixel_x_d1[3:0];
                        in_char_area = 1'b1;
                    end
                    4'd4: begin
                        char_code = 6'd12;  // '%'
                        char_col = pixel_x_d1[3:0];
                        in_char_area = 1'b1;
                    end
                endcase
            end
        end
        
        // 第5行: "Phase: XXX.X °" - 使用预计算值
        else if (pixel_y_d1 >= PARAM_Y_START + 180 && pixel_y_d1 < PARAM_Y_START + 220) begin
            char_row = pixel_y_d1 - PARAM_Y_START - 12'd180;  // 修正：直接计算相对行号
            if (pixel_x_d1 >= 920 && pixel_x_d1 < 1040) begin
                case ((pixel_x_d1 - 920) >> 4)
                    4'd0: begin
                        char_code = {2'b00, phase_d3};  // 千位（百位）
                        char_col = pixel_x_d1[3:0];
                        in_char_area = 1'b1;
                    end
                    4'd1: begin
                        char_code = {2'b00, phase_d2};  // 百位（十位）
                        char_col = pixel_x_d1[3:0];
                        in_char_area = 1'b1;
                    end
                    4'd2: begin
                        char_code = {2'b00, phase_d1};  // 十位（个位）
                        char_col = pixel_x_d1[3:0];
                        in_char_area = 1'b1;
                    end
                    4'd3: begin
                        char_code = 6'd10;  // '.'
                        char_col = pixel_x_d1[3:0];
                        in_char_area = 1'b1;
                    end
                    4'd4: begin
                        char_code = {2'b00, phase_d0};  // 个位（小数第1位）
                        char_col = pixel_x_d1[3:0];
                        in_char_area = 1'b1;
                    end
                    4'd5: begin
                        // TODO: 显示度数符号 '°' (可暂时用空格或其他字符代替)
                        char_code = 6'd0;  // 空格占位
                        char_col = pixel_x_d1[3:0];
                        in_char_area = 1'b1;
                    end
                endcase
            end
        end
    end
end

//=============================================================================
// RGB数据生成（美化版 - 使用延迟后的坐标）
//=============================================================================
always @(*) begin
    rgb_data = 24'h000000;  // 默认黑色背景
    spectrum_height_calc = 12'd0;
    char_color = 24'hFFFFFF;  // 默认白色文字
    
    // ✅ 避免latch：为频谱高度变量赋默认值
    ch1_spectrum_height = 12'd0;
    ch2_spectrum_height = 12'd0;
    ch1_spec_hit = 1'b0;
    ch2_spec_hit = 1'b0;
    
    if (video_active_d3) begin
        // ========== 顶部标题栏 ==========
        if (pixel_y_d3 < 50) begin
            if (pixel_x_d3 < 5 || pixel_x_d3 >= H_ACTIVE - 5 ||
                pixel_y_d3 < 2 || pixel_y_d3 >= 48) begin
                rgb_data = 24'h4080FF;  // 蓝色边框
            end else begin
                rgb_data = 24'h1A1A2E;  // 深蓝灰背景
            end
            
            // ✅ 显示通道指示（独立开关状态，类似示波器）
            if (pixel_y_d3 >= 15 && pixel_y_d3 < 35) begin
                // CH1指示器：开启=亮绿色，关闭=暗灰色
                if (pixel_x_d3 >= 20 && pixel_x_d3 < 120) begin
                    rgb_data = ch1_enable ? 24'h00FF00 : 24'h404040;
                end 
                // CH2指示器：开启=亮红色，关闭=暗灰色
                else if (pixel_x_d3 >= 140 && pixel_x_d3 < 240) begin
                    rgb_data = ch2_enable ? 24'hFF0000 : 24'h404040;
                end
                // ✅ 调试：显示当前数据值（渐变色条）
                else if (pixel_x_d3 >= 300 && pixel_x_d3 < 500) begin
                    if (work_mode_d3 == 2'd0) begin
                        // 时域模式：显示time_data_q的值
                        rgb_data = {time_data_q[15:8], 8'h00, 8'hFF - time_data_q[15:8]};
                    end else begin
                        // 频域模式：显示spectrum_data_q的值
                        rgb_data = {spectrum_data_q[15:8], spectrum_data_q[15:8], 8'h00};
                    end
                end
            end
        end
        
        // ========== 频谱/时域显示区域 ==========
        else if (pixel_y_d3 >= SPECTRUM_Y_START && pixel_y_d3 < SPECTRUM_Y_END) begin
            
            // ========== 工作模式0：时域波形显示 ==========
            if (work_mode_d4 == 2'd0) begin
                // 网格线（使用d4信号）
                if (grid_x_flag_d4 || grid_y_flag_d4) begin
                    rgb_data = 24'h303030;  // 深灰网格
                end
                // 中心参考线（0V参考）
                else if (pixel_y_d4 == WAVEFORM_CENTER_Y || 
                         pixel_y_d4 == WAVEFORM_CENTER_Y + 1) begin
                    rgb_data = 24'h606060;  // 灰色中心线
                end
                else begin
                    // ✅ 方案3优化：简化RGB选择逻辑（使用Stage 4计算的ch1_hit/ch2_hit）
                    // 使用case语句替代多层if-else，减少多路选择器层数
                    case ({ch1_hit & ch1_enable_d4, ch2_hit & ch2_enable_d4})
                        2'b11: rgb_data = 24'hFFFF00;  // 黄色（两通道重叠）
                        2'b10: rgb_data = 24'h00FF00;  // 绿色（仅CH1）
                        2'b01: rgb_data = 24'hFF0000;  // 红色（仅CH2）
                        default: rgb_data = {8'd16, 8'd16, (8'd20 + {5'd0, pixel_y_d4[8:6]})};  // 背景渐变
                    endcase
                end
            end
            
            // ========== 工作模式1：频域频谱显示 ==========
            else begin
                // ✅ 双通道频谱高度计算（4x增益）
                // CH1频谱高度
                if (ch1_data_q > 16'd8000)
                    ch1_spectrum_height = 12'd700;
                else if (ch1_data_q < 16'd4)
                    ch1_spectrum_height = 12'd0;
                else
                    ch1_spectrum_height = {ch1_data_q[12:0], 2'b00};
                
                // CH2频谱高度
                if (ch2_data_q > 16'd8000)
                    ch2_spectrum_height = 12'd700;
                else if (ch2_data_q < 16'd4)
                    ch2_spectrum_height = 12'd0;
                else
                    ch2_spectrum_height = {ch2_data_q[12:0], 2'b00};
                
                // 兼容旧变量（用于调试显示等）
                spectrum_height_calc = ch1_enable ? ch1_spectrum_height : ch2_spectrum_height;
                
                // 网格线（使用d4信号）
                if (grid_x_flag_d4 || grid_y_flag_d4) begin
                    rgb_data = 24'h303030;
                end
                else begin
                    // ✅ 流水线优化：频谱命中检测也在Stage 4完成
                    // 使用Stage 3计算的频谱高度（ch1_spectrum_calc_d1, ch2_spectrum_calc_d1）
                    
                    // ✅ 方案3优化：简化频谱RGB选择（减少嵌套if）
                    ch1_spec_hit = ch1_enable_d4 && (pixel_y_d4 >= (SPECTRUM_Y_END - ch1_spectrum_calc_d1 - 10));
                    ch2_spec_hit = ch2_enable_d4 && (pixel_y_d4 >= (SPECTRUM_Y_END - ch2_spectrum_calc_d1 - 10));
                    
                    // 简化的颜色选择
                    case ({ch1_spec_hit, ch2_spec_hit})
                        2'b11: begin  // 双通道重叠
                            if (ch1_spectrum_calc_d1 > ch2_spectrum_calc_d1)
                                rgb_data = (ch1_spectrum_calc_d1 > 500) ? 24'hFFFF00 : 24'h80FF80;
                            else
                                rgb_data = (ch2_spectrum_calc_d1 > 500) ? 24'hFF8000 : 24'hFF8080;
                        end
                        2'b10: begin  // 仅CH1
                            if (ch1_spectrum_calc_d1 > 500)      rgb_data = 24'h00FF00;
                            else if (ch1_spectrum_calc_d1 > 350) rgb_data = 24'h00DD00;
                            else if (ch1_spectrum_calc_d1 > 200) rgb_data = 24'h00BB00;
                            else                                  rgb_data = 24'h008800;
                        end
                        2'b01: begin  // 仅CH2
                            if (ch2_spectrum_calc_d1 > 500)      rgb_data = 24'hFF0000;
                            else if (ch2_spectrum_calc_d1 > 350) rgb_data = 24'hDD0000;
                            else if (ch2_spectrum_calc_d1 > 200) rgb_data = 24'hBB0000;
                            else                                  rgb_data = 24'h880000;
                        end
                        default: rgb_data = {8'd16, 8'd16, (8'd20 + {5'd0, pixel_y_d4[8:6]})};  // 背景
                    endcase
                end
            end  // 结束 work_mode_d4 else 块
        end
        
        // ========== 中间分隔条 ==========
        else if (pixel_y_d3 >= SPECTRUM_Y_END && pixel_y_d3 < PARAM_Y_START) begin
            if (pixel_y_d3 == SPECTRUM_Y_END || pixel_y_d3 == PARAM_Y_START - 1) begin
                rgb_data = 24'h4080FF;  // 蓝色分隔线
            end else begin
                rgb_data = 24'h0F0F23;  // 深色背景
            end
        end
        
        // ========== 参数显示区域 ==========
        else if (pixel_y_d3 >= PARAM_Y_START && pixel_y_d3 < PARAM_Y_END) begin
            // 背景渐变
            rgb_data = {8'd15, 8'd15, 8'd30};  // 深蓝色背景
            
            // 字符显示（使用延迟后的ROM数据）
            if (in_char_area && char_pixel_row[15 - char_col]) begin
                // 根据参数类型设置不同颜色
                if (pixel_y_d3 < PARAM_Y_START + 40)
                    char_color = 24'h00FFFF;  // 青色 - 频率
                else if (pixel_y_d3 < PARAM_Y_START + 85)
                    char_color = 24'hFFFF00;  // 黄色 - 幅度
                else if (pixel_y_d3 < PARAM_Y_START + 130)
                    char_color = 24'h00FF00;  // 绿色 - 占空比
                else if (pixel_y_d3 < PARAM_Y_START + 175)
                    char_color = 24'hFF8800;  // 橙色 - THD
                else
                    char_color = 24'hFF00FF;  // 洋红色 - 相位差
                
                rgb_data = char_color;
            end
            
            // 参数分组框（装饰性边框）
            if ((pixel_x_d3 == 30 || pixel_x_d3 == 300) && 
                (pixel_y_d3 >= PARAM_Y_START + 5 && pixel_y_d3 < PARAM_Y_START + 45)) begin
                rgb_data = 24'h00FFFF;  // 频率框
            end
            else if ((pixel_x_d3 == 330 || pixel_x_d3 == 550) && 
                     (pixel_y_d3 >= PARAM_Y_START + 50 && pixel_y_d3 < PARAM_Y_START + 90)) begin
                rgb_data = 24'hFFFF00;  // 幅度框
            end
            else if ((pixel_x_d3 == 630 || pixel_x_d3 == 850) && 
                     (pixel_y_d3 >= PARAM_Y_START + 95 && pixel_y_d3 < PARAM_Y_START + 135)) begin
                rgb_data = 24'h00FF00;  // 占空比框
            end
            else if ((pixel_x_d3 == 930 || pixel_x_d3 == 1150) && 
                     (pixel_y_d3 >= PARAM_Y_START + 140 && pixel_y_d3 < PARAM_Y_START + 180)) begin
                rgb_data = 24'hFF8800;  // THD框
            end
            else if ((pixel_x_d3 == 910 || pixel_x_d3 == 1130) && 
                     (pixel_y_d3 >= PARAM_Y_START + 185 && pixel_y_d3 < PARAM_Y_START + 225)) begin
                rgb_data = 24'hFF00FF;  // 相位差框
            end
        end
        
        // ========== 底部边框 ==========
        else if (pixel_y_d3 >= PARAM_Y_END) begin
            if (pixel_y_d3 >= V_ACTIVE - 2) begin
                rgb_data = 24'h4080FF;  // 蓝色底边
            end else begin
                rgb_data = 24'h000000;  // 黑色
            end
        end
        
        // ========== 左右边框 ==========
        if (pixel_x_d3 < 2 || pixel_x_d3 >= H_ACTIVE - 2) begin
            rgb_data = 24'h4080FF;  // 蓝色侧边
        end
    end
end

//=============================================================================
// 输出寄存器
//=============================================================================
always @(posedge clk_pixel or negedge rst_n) begin
    if (!rst_n) begin
        rgb_out_reg <= 24'h000000;
        de_out_reg  <= 1'b0;
        hs_out_reg  <= 1'b0;  // 修改：复位时也为0，与内部信号一致
        vs_out_reg  <= 1'b0;  // 修改：复位时也为0，与内部信号一致
    end else begin
        rgb_out_reg <= rgb_data;
        de_out_reg  <= video_active_d3;  // 使用延迟3拍后的，与RGB同步
        hs_out_reg  <= hs_internal;
        vs_out_reg  <= vs_internal;
    end
end

assign rgb_out = rgb_out_reg;
assign de_out  = de_out_reg;
assign hs_out  = hs_out_reg;
assign vs_out  = vs_out_reg;

endmodule