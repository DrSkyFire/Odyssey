//=============================================================================
// 文件�? hdmi_display_ctrl.v (美化增强�?- 带参数显�?+ 双通道独立控制)
// 描述: 720p@60Hz HDMI显示控制�?(时序优化�?
//       - 分辨�? 1280×720 @ 74.25MHz (降低带宽满足时序要求)
//       - 上部：双通道频谱/波形显示（带网格线）
//       - 下部：参数信息显示（大字体）
//       - 支持独立通道开关：CH1(绿色) CH2(红色)
//       - 配色：渐变频�?+ 深色背景 + 白色文字
//=============================================================================

module hdmi_display_ctrl (
    input  wire         clk_pixel,
    input  wire         rst_n,
    
    // �?双通道数据接口
    input  wire [15:0]  ch1_data,       // 通道1数据（时�?频域共用�?
    input  wire [15:0]  ch2_data,       // 通道2数据（时�?频域共用�?
    output reg  [12:0]  spectrum_addr,  // �?改为13位以支持8192点FFT
    
    // 双通道参数输入
    input  wire [15:0]  ch1_freq,           // CH1频率数�?
    input  wire         ch1_freq_is_khz,    // CH1频率单位 (0=Hz, 1=kHz)
    input  wire         ch1_freq_is_mhz,    // CH1 MHz单位 (1=MHz)
    input  wire [15:0]  ch1_amplitude,      // CH1幅度
    input  wire [15:0]  ch1_duty,           // CH1占空�?(0-1000 = 0-100%)
    input  wire [15:0]  ch1_thd,            // CH1 THD (0-1000 = 0-100%)
    input  wire [15:0]  ch2_freq,           // CH2频率数�?
    input  wire         ch2_freq_is_khz,    // CH2频率单位 (0=Hz, 1=kHz)
    input  wire         ch2_freq_is_mhz,    // CH2 MHz单位 (1=MHz)
    input  wire [15:0]  ch2_amplitude,      // CH2幅度
    input  wire [15:0]  ch2_duty,           // CH2占空�?0-1000 = 0-100%)
    input  wire [15:0]  ch2_thd,            // CH2 THD (0-1000 = 0-100%)
    input  wire signed [15:0]  phase_diff,  // 相位�?-1800 ~ +1799 = -180.0° ~ +179.9°)
    input  wire [7:0]   phase_confidence,   // 相位差置信度 (0-255)
    
    // �?AI识别结果输入
    input  wire [2:0]   ch1_waveform_type,   // CH1波形类型: 0=未知,1=正弦,2=方波,3=三角,4=锯齿,5=噪声
    input  wire [7:0]   ch1_confidence,      // CH1置信�?(0-100%)
    input  wire         ch1_ai_valid,        // CH1识别结果有效
    input  wire [2:0]   ch2_waveform_type,   // CH2波形类型
    input  wire [7:0]   ch2_confidence,      // CH2置信�?
    input  wire         ch2_ai_valid,        // CH2识别结果有效
    
    // �?双通道独立控制（替代current_channel�?
    input  wire         ch1_enable,     // 通道1显示使能
    input  wire         ch2_enable,     // 通道2显示使能
    
    input  wire [1:0]   work_mode,
    
    // �?自动测试模式显示
    input  wire         auto_test_enable,       // 自动测试模式使能
    input  wire [2:0]   param_adjust_mode,      // 参数调整模式 (0=IDLE, 1=FREQ, 2=AMP, 3=DUTY, 4=THD)
    input  wire [1:0]   adjust_step_mode,       // 步进模式 (0=细调, 1=中调, 2=粗调)
    input  wire [31:0]  freq_min_display,       // 频率下限
    input  wire [31:0]  freq_max_display,       // 频率上限
    input  wire [15:0]  amp_min_display,        // 幅度下限
    input  wire [15:0]  amp_max_display,        // 幅度上限
    input  wire [15:0]  duty_min_display,       // 占空比下�?
    input  wire [15:0]  duty_max_display,       // 占空比上�?
    input  wire [15:0]  thd_max_display,        // THD上限
    input  wire [7:0]   auto_test_result,       // 自动测试结果
    
    // HDMI输出
    output wire [23:0]  rgb_out,
    output wire         de_out,
    output wire         hs_out,
    output wire         vs_out
);

//=============================================================================
// 时序参数 - 720p@60Hz (降低像素时钟以满足时序要�?
//=============================================================================
localparam H_ACTIVE     = 1280;         // 水平有效像素
localparam H_FP         = 110;          // 水平前肩
localparam H_SYNC       = 40;           // 水平同步
localparam H_BP         = 220;          // 水平后肩
localparam H_TOTAL      = 1650;         // 总计 (1280+110+40+220)

localparam V_ACTIVE     = 720;          // 垂直有效�?
localparam V_FP         = 5;            // 垂直前肩
localparam V_SYNC       = 5;            // 垂直同步
localparam V_BP         = 20;           // 垂直后肩
localparam V_TOTAL      = 750;          // 总计 (720+5+5+20)

// 像素时钟�?650 × 750 × 60Hz = 74.25MHz

//=============================================================================
// 显示区域参数 (720p - 按比例缩�?
//=============================================================================
localparam SPECTRUM_Y_START = 50;       // 频谱区域起始Y (75 * 0.67)
localparam SPECTRUM_Y_END   = 550;      // 频谱区域结束Y (825 * 0.67)
localparam PARAM_Y_START    = 580;      // 参数区域起始Y (870 * 0.67)
localparam PARAM_Y_END      = 720;      // 参数区域结束Y

// 坐标轴标度参�?
localparam AXIS_LEFT_MARGIN = 53;       // 左侧Y轴标度区域宽�?(80 * 0.67)
localparam AXIS_BOTTOM_HEIGHT = 27;     // 底部X轴标度区域高�?(40 * 0.67)
localparam TICK_LENGTH = 5;             // 刻度线长�?(8 * 0.67)

//=============================================================================
// 表格布局参数 (参数显示区域)
//=============================================================================
// 垂直布局 (Y坐标)
localparam TABLE_Y_HEADER   = 580;      // 表头�?Y起始
localparam TABLE_Y_CH1      = 612;      // CH1数据�?Y起始 (580+32)
localparam TABLE_Y_CH2      = 648;      // CH2数据�?Y起始 (612+36)
localparam TABLE_Y_PHASE    = 684;      // 相位差行 Y起始 (648+36)
localparam ROW_HEIGHT       = 36;       // 数据行高�?(字符32px + 4px间距)

// 水平布局 (X坐标) - 列起始位�?
localparam COL_CH_X         = 40;       // CH�?
localparam COL_FREQ_X       = 120;      // Freq�?(右移40px)
localparam COL_AMPL_X       = 320;      // Ampl�?(右移40px)
localparam COL_DUTY_X       = 440;      // Duty�?(右移40px)
localparam COL_THD_X        = 560;      // THD�?(右移40px)
localparam COL_WAVE_X       = 680;      // Wave�?(右移40px)

// 列宽�?
localparam COL_CH_WIDTH     = 40;
localparam COL_FREQ_WIDTH   = 200;
localparam COL_AMPL_WIDTH   = 120;
localparam COL_DUTY_WIDTH   = 120;
localparam COL_THD_WIDTH    = 120;
localparam COL_WAVE_WIDTH   = 600;

//=============================================================================
// 自动测试显示区域参数 (屏幕右下�?
//=============================================================================
localparam AUTO_TEST_X_START = 900;     // 自动测试区域X起始
localparam AUTO_TEST_Y_START = 400;     // 自动测试区域Y起始
localparam AUTO_TEST_WIDTH   = 360;     // 自动测试区域宽度
localparam AUTO_TEST_HEIGHT  = 300;     // 自动测试区域高度
localparam AUTO_LINE_HEIGHT  = 28;      // 行高
localparam AUTO_CHAR_WIDTH   = 16;      // 字符宽度

// 自动测试模式状�?
localparam ADJUST_IDLE = 3'd0;
localparam ADJUST_FREQ = 3'd1;
localparam ADJUST_AMP  = 3'd2;
localparam ADJUST_DUTY = 3'd3;
localparam ADJUST_THD  = 3'd4;

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

// 延迟寄存器（匹配RAM和字符ROM延迟�?
reg [11:0] pixel_x_d1, pixel_x_d2, pixel_x_d3, pixel_x_d4;  // �?增加d4用于时序优化
reg [11:0] pixel_y_d1, pixel_y_d2, pixel_y_d3, pixel_y_d4;  // �?增加d4用于时序优化
reg        video_active_d1, video_active_d2, video_active_d3, video_active_d4;  // �?增加d4
reg [1:0]  work_mode_d1, work_mode_d2, work_mode_d3, work_mode_d4;  // �?增加d4

// 网格线标志（预计算，避免取模运算�?
reg        grid_x_flag, grid_y_flag;

// �?双通道波形相关信号
reg [15:0] ch1_data_q, ch2_data_q;  // 双通道数据寄存器（d1�?
reg [15:0] ch1_data_d2, ch2_data_d2;  // 数据延迟d2（匹配RAM+流水线）
reg [15:0] ch1_data_d3, ch2_data_d3;  // 数据延迟d3
reg [15:0] ch1_data_d4, ch2_data_d4;  // 数据延迟d4（与pixel_d4对齐�?
reg [11:0] ch1_waveform_height;     // CH1波形高度
reg [11:0] ch2_waveform_height;     // CH2波形高度

// 兼容旧变量名
reg [15:0] time_data_q;             // 时域数据寄存器（兼容�?
reg [15:0] spectrum_data_q;         // 频谱数据寄存器（兼容�?
reg [11:0] waveform_height;         // 波形高度计算结果（兼容）
wire [11:0] time_sample_x;          // 时域采样点X坐标�?920点对�?192采样点，压缩显示�?

// 时域波形参数
localparam WAVEFORM_CENTER_Y = (SPECTRUM_Y_START + SPECTRUM_Y_END) / 2;  // 波形中心�?
reg        grid_x_flag_d1, grid_y_flag_d1;
reg        grid_x_flag_d2, grid_y_flag_d2;
reg        grid_x_flag_d3, grid_y_flag_d3;
// �?流水线优化：新增�?级延�?
reg        grid_x_flag_d4, grid_y_flag_d4;

// 网格计数器（每行重置,避免大数取模�?
reg [6:0]  grid_x_cnt;  // 0-99 循环
reg [5:0]  grid_y_cnt;  // 0-49 循环

// (�?spectrum_data_q已在上面双通道部分声明，删除此处重复声�?

// �?双通道波形绘制辅助信号
reg        ch1_hit, ch2_hit;    // 波形命中标志（Stage 4计算结果�?
reg [11:0] ch1_spectrum_height; // CH1频谱高度
reg [11:0] ch2_spectrum_height; // CH2频谱高度

// �?流水线优化：Stage 3输出寄存�?
reg [11:0] ch1_waveform_calc_d1, ch2_waveform_calc_d1;  // 波形高度计算结果
reg [11:0] ch1_spectrum_calc_d1, ch2_spectrum_calc_d1;  // 频谱高度计算结果
reg        ch1_enable_d4, ch2_enable_d4;                 // 通道使能同步

// �?方案3优化：频谱命中检测信号（避免在always块内声明�?
reg        ch1_spec_hit, ch2_spec_hit;

// �?坐标轴标度相关信�?
reg        y_axis_tick;      // Y轴刻度线标志
reg        x_axis_tick;      // X轴刻度线标志
reg        in_axis_label;    // 坐标轴标签区域标�?

// �?流水线优化：Y轴标度预计算寄存器（在pixel_y时刻计算，提�?拍）
reg [7:0]  y_axis_char_code; // Y轴标度字符预计算
reg        y_axis_char_valid; // Y轴标度字符有效标�?
reg [4:0]  y_axis_char_row;  // Y轴字符行�?
reg [11:0] y_axis_char_col;  // Y轴字符列�?

reg [23:0] rgb_out_reg;
reg        de_out_reg;
reg        hs_out_reg;
reg        vs_out_reg;

reg [23:0] rgb_data;
reg [11:0] spectrum_height_calc;

// 字符显示相关
wire [15:0] char_pixel_row;
reg [7:0]   char_code;    // �?改为8位以支持ASCII�?(0-127)
reg [4:0]   char_row;     // 字符行号 (0-31)
reg [11:0]  char_col;     // �?修正：改�?2位以匹配像素坐标减法结果
reg         in_char_area;
reg [23:0]  char_color;

// �?时序优化：char_code中间级寄存器
reg [7:0]   char_code_d1;
reg [4:0]   char_row_d1;
reg [11:0]  char_col_d1;
reg         in_char_area_d1;

// 数字分解
reg [3:0]   digit_0, digit_1, digit_2, digit_3, digit_4;

// 【时序优化】BCD转换流水线寄存器，减少组合逻辑延迟
reg [15:0]  ch1_freq_div10, ch1_freq_div100, ch1_freq_div1000, ch1_freq_div10000;
reg [15:0]  ch2_freq_div10, ch2_freq_div100, ch2_freq_div1000, ch2_freq_div10000;

// CH1预计算的数字（每帧更新一次，避免实时除法�?
reg [3:0]   ch1_freq_d0, ch1_freq_d1, ch1_freq_d2, ch1_freq_d3, ch1_freq_d4;
reg [3:0]   ch1_amp_d0, ch1_amp_d1, ch1_amp_d2, ch1_amp_d3;
reg [3:0]   ch1_duty_d0, ch1_duty_d1, ch1_duty_d2;
reg [3:0]   ch1_thd_d0, ch1_thd_d1, ch1_thd_d2;

// CH2预计算的数字
reg [3:0]   ch2_freq_d0, ch2_freq_d1, ch2_freq_d2, ch2_freq_d3, ch2_freq_d4;
reg [3:0]   ch2_amp_d0, ch2_amp_d1, ch2_amp_d2, ch2_amp_d3;
reg [3:0]   ch2_duty_d0, ch2_duty_d1, ch2_duty_d2;
reg [3:0]   ch2_thd_d0, ch2_thd_d1, ch2_thd_d2;

// 相位差预计算（支持有符号�?
reg         phase_sign;                         // 符号�?(0=�? 1=�?
reg [15:0]  phase_abs;                          // 绝对�?
reg [3:0]   phase_d0, phase_d1, phase_d2, phase_d3;

// �?NEW: 频率自适应单位和数�?
reg [1:0]   ch1_freq_unit;      // 0=Hz, 1=kHz, 2=MHz
reg [15:0]  ch1_freq_display;   // 显示数值（已转换单位）
reg [1:0]   ch2_freq_unit;
reg [15:0]  ch2_freq_display;

// �?自动测试显示相关信号
reg         in_auto_test_area;      // 在自动测试显示区域内
reg [7:0]   auto_test_char_code;    // 自动测试字符编码
reg [4:0]   auto_test_char_row;     // 自动测试字符行号
reg [11:0]  auto_test_char_col;     // 自动测试字符列号
reg         auto_test_char_valid;   // 自动测试字符有效
reg [31:0]  freq_min_khz, freq_max_khz;  // 频率显示为kHz
reg [15:0]  amp_min_mv, amp_max_mv;      // 幅度显示为mV
reg [3:0]   freq_min_d0, freq_min_d1, freq_min_d2, freq_min_d3, freq_min_d4, freq_min_d5;
reg [3:0]   freq_max_d0, freq_max_d1, freq_max_d2, freq_max_d3, freq_max_d4, freq_max_d5;
reg [3:0]   amp_min_d0, amp_min_d1, amp_min_d2, amp_min_d3;
reg [3:0]   amp_max_d0, amp_max_d1, amp_max_d2, amp_max_d3;
reg [3:0]   duty_min_d0, duty_min_d1, duty_min_d2;
reg [3:0]   duty_max_d0, duty_max_d1, duty_max_d2;
reg [3:0]   thd_max_d0, thd_max_d1, thd_max_d2;

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
// 同步信号 (正极�?- 与MS7210兼容)
// 参考官方例�? hs = (h_cnt < H_SYNC)
//=============================================================================
always @(posedge clk_pixel or negedge rst_n) begin
    if (!rst_n)
        hs_internal <= 1'b0;
    else
        hs_internal <= (h_cnt < H_SYNC);  // �?0个周期为高（正极性）
end

always @(posedge clk_pixel or negedge rst_n) begin
    if (!rst_n)
        vs_internal <= 1'b0;
    else begin
        if (v_cnt == 12'd0)
            vs_internal <= 1'b1;        // 场计数器�?时，VS拉高
        else if (v_cnt == V_SYNC)
            vs_internal <= 1'b0;        // V_SYNC个周期后，VS拉低
        else
            vs_internal <= vs_internal; // 保持当前值（关键！）
    end
end

//=============================================================================
// 有效区域标志 (组合逻辑 - 与官方例程一�?
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
// 像素坐标 (相对于有效区域起始位�?
//=============================================================================
always @(posedge clk_pixel or negedge rst_n) begin
    if (!rst_n) begin
        pixel_x <= 12'd0;
        pixel_y <= 12'd0;
    end else begin
        // 坐标从SYNC+BP开始计�?
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
// 网格计数器和标志（避免昂贵的取模运算�?
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
// 频谱地址生成（提前生成）- 适配720p分辨率，根据work_mode动态映�?
// 采样�?5MHz，奈奎斯特频�?7.5MHz
// 720p有效显示区域�?227像素�?3-1279�?
// 
// 频谱模式: 映射�?096个频谱点 (0-Fs/2)
//   spectrum_addr = (h_offset * 4096) / 1227 �?h_offset * 3.34
//   近似: (h_offset << 2) - (h_offset >> 3) = h_offset * 3.875
//   精确: (h_offset * 10) / 3 = h_offset * 3.33
//
// 时域模式: 映射�?192个采样点
//   spectrum_addr = (h_offset * 8192) / 1227 �?h_offset * 6.68
//   近似: (h_offset << 3) - (h_offset >> 2) = h_offset * 7.75
//   精确: (h_offset * 20) / 3 = h_offset * 6.67
//=============================================================================
reg [11:0] h_offset;     // 水平偏移量（h_cnt - AXIS_LEFT_MARGIN�?
reg [18:0] addr_mult_107; // 【v11新增】h_offset × 107，用于高精度频谱映射

always @(posedge clk_pixel or negedge rst_n) begin
    if (!rst_n) begin
        spectrum_addr <= 13'd0;
        h_offset <= 12'd0;
        addr_mult_107 <= 19'd0;
    end
    else begin
        // 使用pixel_x而不是h_cnt来计算地址，确保坐标对�?
        if (pixel_x < AXIS_LEFT_MARGIN) begin
            // 左侧Y轴区域，保持在起�?
            spectrum_addr <= 13'd0;
            h_offset <= 12'd0;
            addr_mult_107 <= 19'd0;
        end
        else if (pixel_x < H_ACTIVE) begin
            // 有效显示区域：pixel_x = 53-1279
            h_offset <= pixel_x - AXIS_LEFT_MARGIN;
            
            // 根据工作模式选择映射公式
            if (work_mode == 2'b00) begin
                // **时域模式**: spectrum_addr = h_offset * 6.5
                //          = (h_offset<<2) + (h_offset<<1) + (h_offset>>1)
                //          目标6.68，误�?2.7%（损�?17个采样点，范�?-7975�?
                spectrum_addr <= (h_offset << 2) + (h_offset << 1) + {1'b0, h_offset[11:1]};
                addr_mult_107 <= 19'd0;  // 未使�?
            end
            else begin
                // 【v11b修复】频谱模�?- 使用流水线计算，避免组合逻辑时序问题
                // 目标：spectrum_addr = h_offset × 3.34 (4096 bins / 1227 pixels)
                // 
                // Stage 1: 计算 h_offset × 107
                // 107 = 64 + 32 + 8 + 2 + 1
                addr_mult_107 <= (h_offset << 6) + (h_offset << 5) + (h_offset << 3) + 
                                 (h_offset << 1) + h_offset;
                                 
                // Stage 2: 右移5位（÷32�?
                spectrum_addr <= addr_mult_107[18:5];
            end
        end
        else begin
            // 超出范围，指向最后有效点
            if (work_mode == 2'b00)
                spectrum_addr <= 13'd8191;  // 时域最大采样点
            else
                spectrum_addr <= 13'd4095;  // 频谱最大bin
            h_offset <= 12'd0;
            addr_mult_107 <= 19'd0;
        end
    end
end

//=============================================================================
// 参数数字预计算（每帧更新，避免实时除法造成时序违例�?
//=============================================================================
always @(posedge clk_pixel or negedge rst_n) begin
    if (!rst_n) begin
        ch1_freq_d0 <= 4'd0; ch1_freq_d1 <= 4'd0; ch1_freq_d2 <= 4'd0; ch1_freq_d3 <= 4'd0; ch1_freq_d4 <= 4'd0;
        ch1_amp_d0 <= 4'd0; ch1_amp_d1 <= 4'd0; ch1_amp_d2 <= 4'd0; ch1_amp_d3 <= 4'd0;
        ch1_duty_d0 <= 4'd0; ch1_duty_d1 <= 4'd0; ch1_duty_d2 <= 4'd0;
        ch1_thd_d0 <= 4'd0; ch1_thd_d1 <= 4'd0; ch1_thd_d2 <= 4'd0;
        ch2_freq_d0 <= 4'd0; ch2_freq_d1 <= 4'd0; ch2_freq_d2 <= 4'd0; ch2_freq_d3 <= 4'd0; ch2_freq_d4 <= 4'd0;
        ch2_amp_d0 <= 4'd0; ch2_amp_d1 <= 4'd0; ch2_amp_d2 <= 4'd0; ch2_amp_d3 <= 4'd0;
        ch2_duty_d0 <= 4'd0; ch2_duty_d1 <= 4'd0; ch2_duty_d2 <= 4'd0;
        ch2_thd_d0 <= 4'd0; ch2_thd_d1 <= 4'd0; ch2_thd_d2 <= 4'd0;
        phase_sign <= 1'b0;
        phase_abs <= 16'd0;
        phase_d0 <= 4'd0; phase_d1 <= 4'd0; phase_d2 <= 4'd0; phase_d3 <= 4'd0;
        ch1_freq_unit <= 2'd0; ch1_freq_display <= 16'd0;
        ch2_freq_unit <= 2'd0; ch2_freq_display <= 16'd0;
        // 流水线寄存器初始�?
        ch1_freq_div10 <= 16'd0; ch1_freq_div100 <= 16'd0; 
        ch1_freq_div1000 <= 16'd0; ch1_freq_div10000 <= 16'd0;
        ch2_freq_div10 <= 16'd0; ch2_freq_div100 <= 16'd0;
        ch2_freq_div1000 <= 16'd0; ch2_freq_div10000 <= 16'd0;
    end else begin
        // 在场消隐期间更新（v_cnt == 0），分散到多个时钟周期避免时序违�?
        if (v_cnt == 12'd0 && h_cnt == 12'd0) begin
            // 【修复】CH1频率显示逻辑 - 支持Hz/kHz/MHz三档单位
            // ch1_freq_is_mhz和ch1_freq_is_khz组合判断�?
            // MHz: ch1_freq_is_mhz=1
            // kHz: ch1_freq_is_mhz=0, ch1_freq_is_khz=1
            // Hz:  ch1_freq_is_mhz=0, ch1_freq_is_khz=0
            
            if (ch1_freq_is_mhz) begin
                // MHz单位，直接显示（已经�?位小数格式）
                ch1_freq_unit <= 2'd2;              // MHz
                ch1_freq_display <= ch1_freq;
            end else if (ch1_freq_is_khz) begin
                // kHz单位，直接显示（已经�?位小数格式）
                ch1_freq_unit <= 2'd1;              // kHz
                ch1_freq_display <= ch1_freq;
            end else begin
                // Hz单位，直接显�?
                ch1_freq_unit <= 2'd0;              // Hz
                ch1_freq_display <= ch1_freq;
            end
        end
        
        // 【时序优化】BCD转换流水线：先计算除法，再取�?
        // Stage 1: 计算除法结果（h_cnt = 5, 10, 15...�?
        if (v_cnt == 12'd0 && h_cnt == 12'd5) begin
            ch1_freq_div10 <= ch1_freq_display / 5'd10;
            ch1_freq_div100 <= ch1_freq_display / 7'd100;
            ch1_freq_div1000 <= ch1_freq_display / 10'd1000;
            ch1_freq_div10000 <= ch1_freq_display / 14'd10000;
        end
        
        // Stage 2: 基于除法结果取模（h_cnt = 10, 15, 20...�?
        if (v_cnt == 12'd0 && h_cnt == 12'd10) begin
            ch1_freq_d0 <= ch1_freq_display % 4'd10;  // 个位：直接取�?
        end
        if (v_cnt == 12'd0 && h_cnt == 12'd15) begin
            ch1_freq_d1 <= ch1_freq_div10 % 4'd10;  // 十位：从流水线读�?
        end
        if (v_cnt == 12'd0 && h_cnt == 12'd20) begin
            ch1_freq_d2 <= ch1_freq_div100 % 4'd10;  // 百位：从流水线读�?
        end
        if (v_cnt == 12'd0 && h_cnt == 12'd25) begin
            ch1_freq_d3 <= ch1_freq_div1000 % 4'd10;  // 千位：从流水线读�?
        end
        if (v_cnt == 12'd0 && h_cnt == 12'd30) begin
            ch1_freq_d4 <= ch1_freq_div10000 % 4'd10;  // 万位：从流水线读�?
        end
            
        // CH1幅度�?位数字）- 分散处理
        if (v_cnt == 12'd0 && h_cnt == 12'd35) begin
            ch1_amp_d0 <= ch1_amplitude % 10;
        end
        if (v_cnt == 12'd0 && h_cnt == 12'd40) begin
            ch1_amp_d1 <= (ch1_amplitude / 10) % 10;
        end
        if (v_cnt == 12'd0 && h_cnt == 12'd45) begin
            ch1_amp_d2 <= (ch1_amplitude / 100) % 10;
        end
        if (v_cnt == 12'd0 && h_cnt == 12'd50) begin
            ch1_amp_d3 <= (ch1_amplitude / 1000) % 10;
        end
        
        // CH1占空比（3位数字，0-100.0�?
        if (v_cnt == 12'd0 && h_cnt == 12'd55) begin
            ch1_duty_d0 <= ch1_duty % 10;
        end
        if (v_cnt == 12'd0 && h_cnt == 12'd60) begin
            ch1_duty_d1 <= (ch1_duty / 10) % 10;
        end
        if (v_cnt == 12'd0 && h_cnt == 12'd65) begin
            ch1_duty_d2 <= (ch1_duty / 100) % 10;
        end
        
        // CH1 THD�?位数字，0-100.0�?
        if (v_cnt == 12'd0 && h_cnt == 12'd48) begin
            ch1_thd_d0 <= ch1_thd % 10;
        end
        if (v_cnt == 12'd0 && h_cnt == 12'd75) begin
            ch1_thd_d1 <= (ch1_thd / 10) % 10;
        end
        if (v_cnt == 12'd0 && h_cnt == 12'd80) begin
            ch1_thd_d2 <= (ch1_thd / 100) % 10;
        end
        
        // CH2处理（从h_cnt=100开始）
        if (v_cnt == 12'd0 && h_cnt == 12'd100) begin
            // 【修复】CH2频率显示逻辑 - 支持Hz/kHz/MHz三档单位
            // ch2_freq_is_mhz和ch2_freq_is_khz组合判断�?
            // MHz: ch2_freq_is_mhz=1
            // kHz: ch2_freq_is_mhz=0, ch2_freq_is_khz=1
            // Hz:  ch2_freq_is_mhz=0, ch2_freq_is_khz=0
            
            if (ch2_freq_is_mhz) begin
                // MHz单位，直接显示（已经�?位小数格式）
                ch2_freq_unit <= 2'd2;              // MHz
                ch2_freq_display <= ch2_freq;
            end else if (ch2_freq_is_khz) begin
                // kHz单位，直接显示（已经�?位小数格式）
                ch2_freq_unit <= 2'd1;              // kHz
                ch2_freq_display <= ch2_freq;
            end else begin
                // Hz单位，直接显�?
                ch2_freq_unit <= 2'd0;              // Hz
                ch2_freq_display <= ch2_freq;
            end
        end
        
        // 【时序优化】CH2频率BCD转换流水�?
        // Stage 1: 计算除法结果
        if (v_cnt == 12'd0 && h_cnt == 12'd105) begin
            ch2_freq_div10 <= ch2_freq_display / 5'd10;
            ch2_freq_div100 <= ch2_freq_display / 7'd100;
            ch2_freq_div1000 <= ch2_freq_display / 10'd1000;
            ch2_freq_div10000 <= ch2_freq_display / 14'd10000;
        end
        
        // Stage 2: 基于除法结果取模
        if (v_cnt == 12'd0 && h_cnt == 12'd110) begin
            ch2_freq_d0 <= ch2_freq_display % 10;
        end
        if (v_cnt == 12'd0 && h_cnt == 12'd115) begin
            ch2_freq_d1 <= ch2_freq_div10 % 10;
        end
        if (v_cnt == 12'd0 && h_cnt == 12'd120) begin
            ch2_freq_d2 <= ch2_freq_div100 % 10;
        end
        if (v_cnt == 12'd0 && h_cnt == 12'd125) begin
            ch2_freq_d3 <= ch2_freq_div1000 % 10;
        end
        if (v_cnt == 12'd0 && h_cnt == 12'd130) begin
            ch2_freq_d4 <= ch2_freq_div10000 % 10;
        end
        
        // CH2幅度�?位数字）
        if (v_cnt == 12'd0 && h_cnt == 12'd135) begin
            ch2_amp_d0 <= ch2_amplitude % 10;
        end
        if (v_cnt == 12'd0 && h_cnt == 12'd96) begin
            ch2_amp_d1 <= (ch2_amplitude / 10) % 10;
        end
        if (v_cnt == 12'd0 && h_cnt == 12'd145) begin
            ch2_amp_d2 <= (ch2_amplitude / 100) % 10;
        end
        if (v_cnt == 12'd0 && h_cnt == 12'd150) begin
            ch2_amp_d3 <= (ch2_amplitude / 1000) % 10;
        end
        
        // CH2占空比（3位数字）
        if (v_cnt == 12'd0 && h_cnt == 12'd155) begin
            ch2_duty_d0 <= ch2_duty % 10;
        end
        if (v_cnt == 12'd0 && h_cnt == 12'd160) begin
            ch2_duty_d1 <= (ch2_duty / 10) % 10;
        end
        if (v_cnt == 12'd0 && h_cnt == 12'd165) begin
            ch2_duty_d2 <= (ch2_duty / 100) % 10;
        end
        
        // CH2 THD�?位数字）
        if (v_cnt == 12'd0 && h_cnt == 12'd170) begin
            ch2_thd_d0 <= ch2_thd % 10;
        end
        if (v_cnt == 12'd0 && h_cnt == 12'd120) begin
            ch2_thd_d1 <= (ch2_thd / 10) % 10;
        end
        if (v_cnt == 12'd0 && h_cnt == 12'd180) begin
            ch2_thd_d2 <= (ch2_thd / 100) % 10;
        end
        
        // 相位差（支持有符号显�? ±XXX.X°�?
        // Stage 1: 计算符号和绝对�?
        if (v_cnt == 12'd0 && h_cnt == 12'd182) begin
            phase_sign <= phase_diff[15];  // 符号�?
            phase_abs <= phase_diff[15] ? ((~phase_diff) + 16'd1) : phase_diff;
        end
        
        // Stage 2: BCD转换（基于绝对值）
        if (v_cnt == 12'd0 && h_cnt == 12'd185) begin
            phase_d0 <= phase_abs % 10;
        end
        if (v_cnt == 12'd0 && h_cnt == 12'd190) begin
            phase_d1 <= (phase_abs / 10) % 10;
        end
        if (v_cnt == 12'd0 && h_cnt == 12'd195) begin
            phase_d2 <= (phase_abs / 100) % 10;
        end
        if (v_cnt == 12'd0 && h_cnt == 12'd200) begin
            phase_d3 <= (phase_abs / 1000) % 10;
        end
        
        // �?自动测试参数预计�?(从h_cnt=210开�?
        if (v_cnt == 12'd0 && h_cnt == 12'd210) begin
            // 频率转换为kHz显示 (32位频�?/ 1000)
            freq_min_khz <= freq_min_display >> 10;  // �Ż�������1024�������1000
            freq_max_khz <= freq_max_display >> 10;  // �Ż�������1024�������1000
            // 幅度保持mV单位
            amp_min_mv <= amp_min_display;
            amp_max_mv <= amp_max_display;
        end
        
        // 频率下限BCD转换 (6位数字，最�?00kHz)
        if (v_cnt == 12'd0 && h_cnt == 12'd215) begin
            freq_min_d0 <= freq_min_khz % 10;
            freq_min_d1 <= (freq_min_khz / 10) % 10;
            freq_min_d2 <= (freq_min_khz / 100) % 10;
            freq_min_d3 <= (freq_min_khz / 1000) % 10;
            freq_min_d4 <= (freq_min_khz / 10000) % 10;
            freq_min_d5 <= (freq_min_khz / 100000) % 10;
        end
        
        // 频率上限BCD转换
        if (v_cnt == 12'd0 && h_cnt == 12'd220) begin
            freq_max_d0 <= freq_max_khz % 10;
            freq_max_d1 <= (freq_max_khz / 10) % 10;
            freq_max_d2 <= (freq_max_khz / 100) % 10;
            freq_max_d3 <= (freq_max_khz / 1000) % 10;
            freq_max_d4 <= (freq_max_khz / 10000) % 10;
            freq_max_d5 <= (freq_max_khz / 100000) % 10;
        end
        
        // 幅度下限BCD转换 (4位数字，最�?999mV)
        if (v_cnt == 12'd0 && h_cnt == 12'd225) begin
            amp_min_d0 <= amp_min_mv % 10;
            amp_min_d1 <= (amp_min_mv / 10) % 10;
            amp_min_d2 <= (amp_min_mv / 100) % 10;
            amp_min_d3 <= (amp_min_mv / 1000) % 10;
        end
        
        // 幅度上限BCD转换
        if (v_cnt == 12'd0 && h_cnt == 12'd230) begin
            amp_max_d0 <= amp_max_mv % 10;
            amp_max_d1 <= (amp_max_mv / 10) % 10;
            amp_max_d2 <= (amp_max_mv / 100) % 10;
            amp_max_d3 <= (amp_max_mv / 1000) % 10;
        end
        
        // 占空比上下限BCD转换 (3位数字，0-100.0%)
        if (v_cnt == 12'd0 && h_cnt == 12'd235) begin
            duty_min_d0 <= duty_min_display % 10;
            duty_min_d1 <= (duty_min_display / 10) % 10;
            duty_min_d2 <= (duty_min_display / 100) % 10;
        end
        
        if (v_cnt == 12'd0 && h_cnt == 12'd240) begin
            duty_max_d0 <= duty_max_display % 10;
            duty_max_d1 <= (duty_max_display / 10) % 10;
            duty_max_d2 <= (duty_max_display / 100) % 10;
        end
        
        // THD上限BCD转换 (3位数字，0-100.0%)
        if (v_cnt == 12'd0 && h_cnt == 12'd245) begin
            thd_max_d0 <= thd_max_display % 10;
            thd_max_d1 <= (thd_max_display / 10) % 10;
            thd_max_d2 <= (thd_max_display / 100) % 10;
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
        pixel_x_d4 <= 12'd0;  // �?新增
        pixel_y_d1 <= 12'd0;
        pixel_y_d2 <= 12'd0;
        pixel_y_d3 <= 12'd0;
        pixel_y_d4 <= 12'd0;  // �?新增
        video_active_d1 <= 1'b0;
        video_active_d2 <= 1'b0;
        video_active_d3 <= 1'b0;
        video_active_d4 <= 1'b0;  // �?新增
        work_mode_d1 <= 2'd0;
        work_mode_d2 <= 2'd0;
        work_mode_d3 <= 2'd0;
        work_mode_d4 <= 2'd0;  // �?新增
        grid_x_flag_d1 <= 1'b0;
        grid_x_flag_d2 <= 1'b0;
        grid_x_flag_d3 <= 1'b0;
        grid_y_flag_d1 <= 1'b0;
        grid_y_flag_d2 <= 1'b0;
        grid_y_flag_d3 <= 1'b0;
        spectrum_data_q <= 16'd0;
        
        // �?时序优化：char_code中间寄存�?
        char_code_d1 <= 8'd32;
        char_row_d1 <= 5'd0;
        char_col_d1 <= 12'd0;
        in_char_area_d1 <= 1'b0;
    end else begin
        // 延迟4拍（时序优化后延迟链�?
        pixel_x_d1 <= pixel_x;
        pixel_x_d2 <= pixel_x_d1;
        pixel_x_d3 <= pixel_x_d2;
        pixel_x_d4 <= pixel_x_d3;  // �?新增
        pixel_y_d1 <= pixel_y;
        pixel_y_d2 <= pixel_y_d1;
        pixel_y_d3 <= pixel_y_d2;
        pixel_y_d4 <= pixel_y_d3;  // �?新增
        video_active_d1 <= video_active;
        video_active_d2 <= video_active_d1;
        video_active_d3 <= video_active_d2;
        video_active_d4 <= video_active_d3;  // �?新增
        work_mode_d1 <= work_mode;
        work_mode_d2 <= work_mode_d1;
        work_mode_d3 <= work_mode_d2;
        work_mode_d4 <= work_mode_d3;  // �?新增
        
        // �?时序优化：char_code信号延迟一�?
        char_code_d1 <= char_code;
        char_row_d1 <= char_row;
        char_col_d1 <= char_col;
        in_char_area_d1 <= in_char_area;
        grid_x_flag_d1 <= grid_x_flag;
        grid_x_flag_d2 <= grid_x_flag_d1;
        grid_x_flag_d3 <= grid_x_flag_d2;
        grid_y_flag_d1 <= grid_y_flag;
        grid_y_flag_d2 <= grid_y_flag_d1;
        grid_y_flag_d3 <= grid_y_flag_d2;
        
        // �?流水线优化：Stage 4延迟
        grid_x_flag_d4 <= grid_x_flag_d3;
        grid_y_flag_d4 <= grid_y_flag_d3;
        work_mode_d4 <= work_mode_d3;
        pixel_x_d4 <= pixel_x_d3;
        pixel_y_d4 <= pixel_y_d3;
        ch1_enable_d4 <= ch1_enable;
        ch2_enable_d4 <= ch2_enable;
        
        // �?双通道数据采样：多级延迟匹配RAM读取+显示流水�?
        ch1_data_q <= ch1_data;      // d1: RAM输出采样
        ch2_data_q <= ch2_data;
        ch1_data_d2 <= ch1_data_q;   // d2: �?级延�?
        ch2_data_d2 <= ch2_data_q;
        ch1_data_d3 <= ch1_data_d2;  // d3: �?级延�?
        ch2_data_d3 <= ch2_data_d2;
        ch1_data_d4 <= ch1_data_d3;  // d4: 与pixel_d4对齐
        ch2_data_d4 <= ch2_data_d3;
        
        // 频谱高度计算（时序逻辑，使用d3数据提前1拍计算）
        // CH1频谱高度 (×1增益，无放大) - 直接使用原始FFT幅度
        if (ch1_data_d3 > 16'd500)
            ch1_spectrum_height <= 12'd500;
        else if (ch1_data_d3 < 16'd2)
            ch1_spectrum_height <= 12'd0;
        else
            ch1_spectrum_height <= ch1_data_d3[11:0];
        
        // CH2频谱高度 (×1增益，无放大)
        if (ch2_data_d3 > 16'd500)
            ch2_spectrum_height <= 12'd500;
        else if (ch2_data_d3 < 16'd2)
            ch2_spectrum_height <= 12'd0;
        else
            ch2_spectrum_height <= ch2_data_d3[11:0];
        
        // �?流水线优化：Stage 3 - 采样计算好的波形/频谱高度
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
// �?流水线优化：Y轴标度预计算（提�?拍，在pixel_y时刻计算�?
//=============================================================================
always @(posedge clk_pixel or negedge rst_n) begin
    if (!rst_n) begin
        y_axis_char_code <= 8'd32;
        y_axis_char_valid <= 1'b0;
        y_axis_char_row <= 5'd0;
        y_axis_char_col <= 12'd0;
    end else begin
        // 默认�?
        y_axis_char_code <= 8'd32;  // 空格
        y_axis_char_valid <= 1'b0;
        y_axis_char_row <= 5'd0;
        y_axis_char_col <= 12'd0;
        
        // Y轴单位标�?"%" (Y: 28-44, 16px高，2倍缩放显�?
        if (pixel_y >= 28 && pixel_y < 44 && pixel_x >= 4 && pixel_x < 12) begin
            y_axis_char_row <= (pixel_y - 12'd28) << 1;  // 0-15 -> 0-30 (隔行采样)
            y_axis_char_col <= (pixel_x - 12'd4) << 1;   // 0-7 -> 0-14 (隔列采样)
            y_axis_char_code <= 8'd37;  // '%'
            y_axis_char_valid <= 1'b1;
        end
        // 只在Y轴标度区域预计算字符（缩放显示，16px高）
        else if (pixel_x >= 4 && pixel_x < AXIS_LEFT_MARGIN - TICK_LENGTH - 4) begin
            // 100% (Y: 50-66, 16px高，2倍缩�?
            if (pixel_y >= 50 && pixel_y < 66) begin
                y_axis_char_row <= (pixel_y - 12'd50) << 1;  // 0-15 -> 0-30 (隔行采样)
                y_axis_char_valid <= 1'b1;
                if (pixel_x >= 4 && pixel_x < 12) begin
                    y_axis_char_code <= 8'd49;  // '1'
                    y_axis_char_col <= (pixel_x - 12'd4) << 1;  // 0-7 -> 0-14
                end
                else if (pixel_x >= 12 && pixel_x < 20) begin
                    y_axis_char_code <= 8'd48;  // '0'
                    y_axis_char_col <= (pixel_x - 12'd12) << 1;
                end
                else if (pixel_x >= 20 && pixel_x < 28) begin
                    y_axis_char_code <= 8'd48;  // '0'
                    y_axis_char_col <= (pixel_x - 12'd20) << 1;
                end
                else if (pixel_x >= 28 && pixel_x < 36) begin
                    y_axis_char_code <= 8'd37;  // '%'
                    y_axis_char_col <= (pixel_x - 12'd28) << 1;
                end
                else begin
                    y_axis_char_valid <= 1'b0;
                end
            end
            // 75% (Y: 175-191, 16px高，2倍缩�?
            else if (pixel_y >= 175 && pixel_y < 191) begin
                y_axis_char_row <= (pixel_y - 12'd175) << 1;  // 0-15 -> 0-30
                y_axis_char_valid <= 1'b1;
                if (pixel_x >= 12 && pixel_x < 20) begin
                    y_axis_char_code <= 8'd55;  // '7'
                    y_axis_char_col <= (pixel_x - 12'd12) << 1;
                end
                else if (pixel_x >= 20 && pixel_x < 28) begin
                    y_axis_char_code <= 8'd53;  // '5'
                    y_axis_char_col <= (pixel_x - 12'd20) << 1;
                end
                else if (pixel_x >= 28 && pixel_x < 36) begin
                    y_axis_char_code <= 8'd37;  // '%'
                    y_axis_char_col <= (pixel_x - 12'd28) << 1;
                end
                else begin
                    y_axis_char_valid <= 1'b0;
                end
            end
            // 50% (Y: 300-316, 16px高，2倍缩�?
            else if (pixel_y >= 300 && pixel_y < 316) begin
                y_axis_char_row <= (pixel_y - 12'd300) << 1;  // 0-15 -> 0-30
                y_axis_char_valid <= 1'b1;
                if (pixel_x >= 12 && pixel_x < 20) begin
                    y_axis_char_code <= 8'd53;  // '5'
                    y_axis_char_col <= (pixel_x - 12'd12) << 1;
                end
                else if (pixel_x >= 20 && pixel_x < 28) begin
                    y_axis_char_code <= 8'd48;  // '0'
                    y_axis_char_col <= (pixel_x - 12'd20) << 1;
                end
                else if (pixel_x >= 28 && pixel_x < 36) begin
                    y_axis_char_code <= 8'd37;  // '%'
                    y_axis_char_col <= (pixel_x - 12'd28) << 1;
                end
                else begin
                    y_axis_char_valid <= 1'b0;
                end
            end
            // 25% (Y: 425-441, 16px高，2倍缩�?
            else if (pixel_y >= 425 && pixel_y < 441) begin
                y_axis_char_row <= (pixel_y - 12'd425) << 1;  // 0-15 -> 0-30
                y_axis_char_valid <= 1'b1;
                if (pixel_x >= 12 && pixel_x < 20) begin
                    y_axis_char_code <= 8'd50;  // '2'
                    y_axis_char_col <= (pixel_x - 12'd12) << 1;
                end
                else if (pixel_x >= 20 && pixel_x < 28) begin
                    y_axis_char_code <= 8'd53;  // '5'
                    y_axis_char_col <= (pixel_x - 12'd20) << 1;
                end
                else if (pixel_x >= 28 && pixel_x < 36) begin
                    y_axis_char_code <= 8'd37;  // '%'
                    y_axis_char_col <= (pixel_x - 12'd28) << 1;
                end
                else begin
                    y_axis_char_valid <= 1'b0;
                end
            end
            // 0% (Y: 532-548, 16px高，2倍缩�?
            else if (pixel_y >= 532 && pixel_y < 548) begin
                y_axis_char_row <= (pixel_y - 12'd532) << 1;  // 0-15 -> 0-30
                y_axis_char_valid <= 1'b1;
                if (pixel_x >= 20 && pixel_x < 28) begin
                    y_axis_char_code <= 8'd48;  // '0'
                    y_axis_char_col <= (pixel_x - 12'd20) << 1;
                end
                else if (pixel_x >= 28 && pixel_x < 36) begin
                    y_axis_char_code <= 8'd37;  // '%'
                    y_axis_char_col <= (pixel_x - 12'd28) << 1;
                end
                else begin
                    y_axis_char_valid <= 1'b0;
                end
            end
        end
    end
end

//=============================================================================
// 时域波形参数计算
//=============================================================================
// 【已修复】spectrum_addr已经根据work_mode正确映射�?
// - 频谱模式: 0-4095 (映射�?096个频谱bin)
// - 时域模式: 0-8191 (映射�?192个采样点)
// 不再需要额外的除法操作
assign time_sample_x = spectrum_addr[12:0];  // 直接使用spectrum_addr

//=============================================================================
// �?双通道波形高度计算（Stage 3组合逻辑�?
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
    
    // 兼容旧变量（用于其他地方�?
    waveform_height = ch1_enable ? ch1_waveform_height : ch2_waveform_height;
end

//=============================================================================
// �?流水线优化：Stage 4 - 波形命中检测（时序关键路径�?
//=============================================================================
always @(posedge clk_pixel or negedge rst_n) begin
    if (!rst_n) begin
        ch1_hit <= 1'b0;
        ch2_hit <= 1'b0;
    end else begin
        // CH1波形命中检测（使用Stage 3的计算结果）
        if (ch1_waveform_calc_d1 >= 12'd350) begin
            // 波形在上半部�?
            ch1_hit <= (pixel_y_d3 >= (WAVEFORM_CENTER_Y - (ch1_waveform_calc_d1 - 12'd350) - 12'd2)) &&
                       (pixel_y_d3 <= (WAVEFORM_CENTER_Y - (ch1_waveform_calc_d1 - 12'd350) + 12'd2));
        end else begin
            // 波形在下半部�?
            ch1_hit <= (pixel_y_d3 >= (WAVEFORM_CENTER_Y + (12'd350 - ch1_waveform_calc_d1) - 12'd2)) &&
                       (pixel_y_d3 <= (WAVEFORM_CENTER_Y + (12'd350 - ch1_waveform_calc_d1) + 12'd2));
        end
        
        // CH2波形命中检�?
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
// 字符ROM实例�?- 使用完整ASCII标准字符ROM
// �?时序优化：使用延迟后的char_code信号
//=============================================================================
ascii_rom_16x32_full u_char_rom (
    .clk        (clk_pixel),
    .char_code  (char_code_d1),      // �?使用延迟1拍的char_code
    .char_row   (char_row_d1[4:0]),  // �?使用延迟1拍的char_row
    .char_data  (char_pixel_row)     // 16位字符行数据
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
// BCD数字转ASCII码辅助函�?
//=============================================================================
function [7:0] digit_to_ascii;
    input [3:0] digit;
    begin
        digit_to_ascii = 8'd48 + {4'd0, digit};  // ASCII '0' = 48
    end
endfunction

//=============================================================================
// 参数显示字符生成（提�?拍生成，给ROM时间�? 使用ASCII标准编码
// �?时序优化：改为时序逻辑（非阻塞赋值），打�?1层组合逻辑�?
//=============================================================================
always @(posedge clk_pixel or negedge rst_n) begin
    if (!rst_n) begin
        char_code <= 8'd32;
        char_row <= 5'd0;
        char_col <= 12'd0;
        in_char_area <= 1'b0;
    end else begin
        char_code <= 8'd32;  // 默认空格 (ASCII 32)
        char_row <= 5'd0;
        char_col <= 12'd0;
        in_char_area <= 1'b0;
    
    // ========== �?Y轴标度数字显示（使用预计算结果，无组合逻辑�?==========
    if (y_axis_char_valid) begin
        char_code <= y_axis_char_code;
        char_row <= y_axis_char_row;
        char_col <= y_axis_char_col;
        in_char_area <= 1'b1;
    end
    
    // ========== X轴标度数字显示（底部�?- 修正�?==========
    // �?采样�?5MHz，FFT 8192点，频率分辨�?= 35MHz/8192 = 4.272kHz/bin
    // �?有效频谱�? �?Fs/2 = 17.5MHz（前4096个bin�?
    // 频域模式�?, 3.5, 7.0, 10.5, 14.0, 17.5 MHz
    // 时域模式�?, 47, 93, 140, 186, 234 us (8192�?@ 35MHz = 234us)
    else if (pixel_y_d1 >= SPECTRUM_Y_END && pixel_y_d1 < SPECTRUM_Y_END + 24) begin
        char_row <= ((pixel_y_d1 - SPECTRUM_Y_END) << 2) / 3;  // 0-23 -> 0-30 (1.33倍缩�?
        
        // 标记�?: X=80, "0"
        if (pixel_x_d1 >= 80 && pixel_x_d1 < 92) begin
            char_code <= 8'd48;  // '0'
            char_col <= ((pixel_x_d1 - 12'd80) << 2) / 3;  // 0-11 -> 0-14 (1.33倍缩�?
            in_char_area <= 1'b1;
        end
        // 标记�?: X=272, "2.9" (频域MHz) / "39" (时域us)
        else if (pixel_x_d1 >= 260 && pixel_x_d1 < 272) begin
            char_code <= work_mode_d1[0] ? 8'd50 : 8'd51;  // '2' or '3'
            char_col <= ((pixel_x_d1 - 12'd260) << 2) / 3;
            in_char_area <= 1'b1;
        end
        else if (pixel_x_d1 >= 272 && pixel_x_d1 < 284) begin
            char_code <= work_mode_d1[0] ? 8'd46 : 8'd57;  // '.' or '9'
            char_col <= ((pixel_x_d1 - 12'd272) << 2) / 3;
            in_char_area <= 1'b1;
        end
        else if (pixel_x_d1 >= 284 && pixel_x_d1 < 296 && work_mode_d1[0]) begin
            char_code <= 8'd57;  // '9' (频域的小数位)
            char_col <= ((pixel_x_d1 - 12'd284) << 2) / 3;
            in_char_area <= 1'b1;
        end
        // 标记�?: X=463, "5.8" (频域MHz) / "78" (时域us)
        else if (pixel_x_d1 >= 451 && pixel_x_d1 < 463) begin
            char_code <= work_mode_d1[0] ? 8'd53 : 8'd55;  // '5' or '7'
            char_col <= ((pixel_x_d1 - 12'd451) << 2) / 3;
            in_char_area <= 1'b1;
        end
        else if (pixel_x_d1 >= 463 && pixel_x_d1 < 475) begin
            char_code <= work_mode_d1[0] ? 8'd46 : 8'd56;  // '.' or '8'
            char_col <= ((pixel_x_d1 - 12'd463) << 2) / 3;
            in_char_area <= 1'b1;
        end
        else if (pixel_x_d1 >= 475 && pixel_x_d1 < 487 && work_mode_d1[0]) begin
            char_code <= 8'd56;  // '8' (频域的小数位)
            char_col <= ((pixel_x_d1 - 12'd475) << 2) / 3;
            in_char_area <= 1'b1;
        end
        // 标记�?: X=655, "8.8" (频域MHz) / "117" (时域us)
        else if (pixel_x_d1 >= 643 && pixel_x_d1 < 655) begin
            char_code <= work_mode_d1[0] ? 8'd56 : 8'd49;  // '8' or '1'
            char_col <= ((pixel_x_d1 - 12'd643) << 2) / 3;
            in_char_area <= 1'b1;
        end
        else if (pixel_x_d1 >= 655 && pixel_x_d1 < 667) begin
            char_code <= work_mode_d1[0] ? 8'd46 : 8'd49;  // '.' or '1'
            char_col <= ((pixel_x_d1 - 12'd655) << 2) / 3;
            in_char_area <= 1'b1;
        end
        else if (pixel_x_d1 >= 667 && pixel_x_d1 < 679) begin
            char_code <= work_mode_d1[0] ? 8'd56 : 8'd55;  // '8' or '7'
            char_col <= ((pixel_x_d1 - 12'd667) << 2) / 3;
            in_char_area <= 1'b1;
        end
        // 标记�?: X=847, "11.7" (频域MHz) / "156" (时域us)
        else if (pixel_x_d1 >= 835 && pixel_x_d1 < 847) begin
            char_code <= 8'd49;  // '1'
            char_col <= ((pixel_x_d1 - 12'd835) << 2) / 3;
            in_char_area <= 1'b1;
        end
        else if (pixel_x_d1 >= 847 && pixel_x_d1 < 859) begin
            char_code <= work_mode_d1[0] ? 8'd49 : 8'd53;  // '1' or '5'
            char_col <= ((pixel_x_d1 - 12'd847) << 2) / 3;
            in_char_area <= 1'b1;
        end
        else if (pixel_x_d1 >= 859 && pixel_x_d1 < 871) begin
            char_code <= work_mode_d1[0] ? 8'd46 : 8'd54;  // '.' or '6'
            char_col <= ((pixel_x_d1 - 12'd859) << 2) / 3;
            in_char_area <= 1'b1;
        end
        else if (pixel_x_d1 >= 871 && pixel_x_d1 < 883 && work_mode_d1[0]) begin
            char_code <= 8'd55;  // '7' (频域的小数位)
            char_col <= ((pixel_x_d1 - 12'd871) << 2) / 3;
            in_char_area <= 1'b1;
        end
        // 标记�?: X=1038, "14.6" (频域MHz) / "195" (时域us)
        else if (pixel_x_d1 >= 1026 && pixel_x_d1 < 1038) begin
            char_code <= work_mode_d1[0] ? 8'd49 : 8'd49;  // '1'
            char_col <= ((pixel_x_d1 - 12'd1026) << 2) / 3;
            in_char_area <= 1'b1;
        end
        else if (pixel_x_d1 >= 1038 && pixel_x_d1 < 1050) begin
            char_code <= work_mode_d1[0] ? 8'd52 : 8'd57;  // '4' or '9'
            char_col <= ((pixel_x_d1 - 12'd1038) << 2) / 3;
            in_char_area <= 1'b1;
        end
        else if (pixel_x_d1 >= 1050 && pixel_x_d1 < 1062) begin
            char_code <= work_mode_d1[0] ? 8'd46 : 8'd53;  // '.' or '5'
            char_col <= ((pixel_x_d1 - 12'd1050) << 2) / 3;
            in_char_area <= 1'b1;
        end
        else if (pixel_x_d1 >= 1062 && pixel_x_d1 < 1074 && work_mode_d1[0]) begin
            char_code <= 8'd54;  // '6' (频域的小数位)
            char_col <= ((pixel_x_d1 - 12'd1062) << 2) / 3;
            in_char_area <= 1'b1;
        end
        // 标记�?: X=1230, "17.5" (频域MHz) / "234" (时域us)
        else if (pixel_x_d1 >= 1218 && pixel_x_d1 < 1230) begin
            char_code <= work_mode_d1[0] ? 8'd49 : 8'd50;  // '1' or '2'
            char_col <= ((pixel_x_d1 - 12'd1218) << 2) / 3;
            in_char_area <= 1'b1;
        end
        else if (pixel_x_d1 >= 1230 && pixel_x_d1 < 1242) begin
            char_code <= work_mode_d1[0] ? 8'd55 : 8'd51;  // '7' or '3'
            char_col <= ((pixel_x_d1 - 12'd1230) << 2) / 3;
            in_char_area <= 1'b1;
        end
        else if (pixel_x_d1 >= 1242 && pixel_x_d1 < 1254) begin
            char_code <= work_mode_d1[0] ? 8'd46 : 8'd52;  // '.' or '4'
            char_col <= ((pixel_x_d1 - 12'd1242) << 2) / 3;
            in_char_area <= 1'b1;
        end
        else if (pixel_x_d1 >= 1254 && pixel_x_d1 < 1266 && work_mode_d1[0]) begin
            char_code <= 8'd53;  // '5' (频域的小数位)
            char_col <= ((pixel_x_d1 - 12'd1254) << 2) / 3;
            in_char_area <= 1'b1;
        end
        // X轴单位标�? "MHz" (频域) / "us" (时域) - 右侧，仅显示�?个字�?
        else if (pixel_x_d1 >= 1256 && pixel_x_d1 < 1268 && work_mode_d1[0]) begin
            char_code <= 8'd77;  // 'M' (频域)
            char_col <= ((pixel_x_d1 - 12'd1256) << 2) / 3;
            in_char_area <= 1'b1;
        end
        else if (pixel_x_d1 >= 1268 && pixel_x_d1 < 1280 && work_mode_d1[0]) begin
            char_code <= 8'd72;  // 'H' (频域)
            char_col <= ((pixel_x_d1 - 12'd1268) << 2) / 3;
            in_char_area <= 1'b1;
        end
        else if (pixel_x_d1 >= 1256 && pixel_x_d1 < 1268 && !work_mode_d1[0]) begin
            char_code <= 8'd117;  // 'u' (时域)
            char_col <= ((pixel_x_d1 - 12'd1256) << 2) / 3;
            in_char_area <= 1'b1;
        end
        else if (pixel_x_d1 >= 1268 && pixel_x_d1 < 1280 && !work_mode_d1[0]) begin
            char_code <= 8'd115;  // 's' (时域)
            char_col <= ((pixel_x_d1 - 12'd1268) << 2) / 3;
            in_char_area <= 1'b1;
        end
    end
    
    //=========================================================================
    // 表格式参数显示区�?(新版)
    //=========================================================================
    else if (pixel_y_d1 >= PARAM_Y_START && pixel_y_d1 < PARAM_Y_END) begin
        
        //=====================================================================
        // 表头�?(Y: 580-612, 32px�?
        //=====================================================================
        if (pixel_y_d1 >= TABLE_Y_HEADER && pixel_y_d1 < TABLE_Y_HEADER + 32) begin
            char_row <= pixel_y_d1 - TABLE_Y_HEADER;  // 0-31
            
            // �?: "CH"
            if (pixel_x_d1 >= COL_CH_X + 4 && pixel_x_d1 < COL_CH_X + 20) begin
                char_code <= 8'd67;  // 'C'
                char_col <= pixel_x_d1 - COL_CH_X - 12'd4;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= COL_CH_X + 20 && pixel_x_d1 < COL_CH_X + 36) begin
                char_code <= 8'd72;  // 'H'
                char_col <= pixel_x_d1 - COL_CH_X - 12'd20;
                in_char_area <= 1'b1;
            end
            
            // �?: "Freq"
            else if (pixel_x_d1 >= COL_FREQ_X + 8 && pixel_x_d1 < COL_FREQ_X + 24) begin
                char_code <= 8'd70;  // 'F'
                char_col <= pixel_x_d1 - COL_FREQ_X - 12'd8;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= COL_FREQ_X + 24 && pixel_x_d1 < COL_FREQ_X + 40) begin
                char_code <= 8'd114;  // 'r'
                char_col <= pixel_x_d1 - COL_FREQ_X - 12'd24;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= COL_FREQ_X + 40 && pixel_x_d1 < COL_FREQ_X + 56) begin
                char_code <= 8'd101;  // 'e'
                char_col <= pixel_x_d1 - COL_FREQ_X - 12'd40;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= COL_FREQ_X + 56 && pixel_x_d1 < COL_FREQ_X + 72) begin
                char_code <= 8'd113;  // 'q'
                char_col <= pixel_x_d1 - COL_FREQ_X - 12'd56;
                in_char_area <= 1'b1;
            end
            
            // �?: "Ampl"
            else if (pixel_x_d1 >= COL_AMPL_X + 8 && pixel_x_d1 < COL_AMPL_X + 24) begin
                char_code <= 8'd65;  // 'A'
                char_col <= pixel_x_d1 - COL_AMPL_X - 12'd8;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= COL_AMPL_X + 24 && pixel_x_d1 < COL_AMPL_X + 40) begin
                char_code <= 8'd109;  // 'm'
                char_col <= pixel_x_d1 - COL_AMPL_X - 12'd24;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= COL_AMPL_X + 40 && pixel_x_d1 < COL_AMPL_X + 56) begin
                char_code <= 8'd112;  // 'p'
                char_col <= pixel_x_d1 - COL_AMPL_X - 12'd40;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= COL_AMPL_X + 56 && pixel_x_d1 < COL_AMPL_X + 72) begin
                char_code <= 8'd108;  // 'l'
                char_col <= pixel_x_d1 - COL_AMPL_X - 12'd56;
                in_char_area <= 1'b1;
            end
            
            // �?: "Duty"
            else if (pixel_x_d1 >= COL_DUTY_X + 8 && pixel_x_d1 < COL_DUTY_X + 24) begin
                char_code <= 8'd68;  // 'D'
                char_col <= pixel_x_d1 - COL_DUTY_X - 12'd8;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= COL_DUTY_X + 24 && pixel_x_d1 < COL_DUTY_X + 40) begin
                char_code <= 8'd117;  // 'u'
                char_col <= pixel_x_d1 - COL_DUTY_X - 12'd24;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= COL_DUTY_X + 40 && pixel_x_d1 < COL_DUTY_X + 56) begin
                char_code <= 8'd116;  // 't'
                char_col <= pixel_x_d1 - COL_DUTY_X - 12'd40;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= COL_DUTY_X + 56 && pixel_x_d1 < COL_DUTY_X + 72) begin
                char_code <= 8'd121;  // 'y'
                char_col <= pixel_x_d1 - COL_DUTY_X - 12'd56;
                in_char_area <= 1'b1;
            end
            
            // �?: "THD"
            else if (pixel_x_d1 >= COL_THD_X + 8 && pixel_x_d1 < COL_THD_X + 24) begin
                char_code <= 8'd84;  // 'T'
                char_col <= pixel_x_d1 - COL_THD_X - 12'd8;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= COL_THD_X + 24 && pixel_x_d1 < COL_THD_X + 40) begin
                char_code <= 8'd72;  // 'H'
                char_col <= pixel_x_d1 - COL_THD_X - 12'd24;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= COL_THD_X + 40 && pixel_x_d1 < COL_THD_X + 56) begin
                char_code <= 8'd68;  // 'D'
                char_col <= pixel_x_d1 - COL_THD_X - 12'd40;
                in_char_area <= 1'b1;
            end
            
            // �?: "Wave"
            else if (pixel_x_d1 >= COL_WAVE_X + 8 && pixel_x_d1 < COL_WAVE_X + 24) begin
                char_code <= 8'd87;  // 'W'
                char_col <= pixel_x_d1 - COL_WAVE_X - 12'd8;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= COL_WAVE_X + 24 && pixel_x_d1 < COL_WAVE_X + 40) begin
                char_code <= 8'd97;  // 'a'
                char_col <= pixel_x_d1 - COL_WAVE_X - 12'd24;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= COL_WAVE_X + 40 && pixel_x_d1 < COL_WAVE_X + 56) begin
                char_code <= 8'd118;  // 'v'
                char_col <= pixel_x_d1 - COL_WAVE_X - 12'd40;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= COL_WAVE_X + 56 && pixel_x_d1 < COL_WAVE_X + 72) begin
                char_code <= 8'd101;  // 'e'
                char_col <= pixel_x_d1 - COL_WAVE_X - 12'd56;
                in_char_area <= 1'b1;
            end
            else begin
                in_char_area <= 1'b0;
            end
        end
        
        //=====================================================================
        // CH1数据�?(Y: 600-640, 40px�?
        //=====================================================================
        else if (pixel_y_d1 >= TABLE_Y_CH1 && pixel_y_d1 < TABLE_Y_CH1 + ROW_HEIGHT) begin
            // 只在行内�?2px显示字符�?0px行高，字�?2px，底�?px留空�?
            if (pixel_y_d1 < TABLE_Y_CH1 + 32) begin
                char_row <= pixel_y_d1 - TABLE_Y_CH1;  // 0-31，不需要左�?
            
                // �?: 通道�?"1"
                if (pixel_x_d1 >= COL_CH_X + 12 && pixel_x_d1 < COL_CH_X + 28) begin
                char_code <= 8'd49;  // '1'
                char_col <= pixel_x_d1 - COL_CH_X - 12'd12;
                in_char_area <= ch1_enable;
            end
            
            // �?: 频率显示 (自适应Hz/kHz/MHz)
            // Hz模式: "12345Hz " (5位整�?
            // kHz模式: "123.45kHz" (3位整�?小数�?2位小�?
            else if (pixel_x_d1 >= COL_FREQ_X && pixel_x_d1 < COL_FREQ_X + 200) begin
                if (ch1_freq_unit == 2'd0) begin
                    // Hz模式：显�?位整�?+ "Hz"
                    if (pixel_x_d1 >= COL_FREQ_X + 8 && pixel_x_d1 < COL_FREQ_X + 24) begin
                        // �?位：万位 (前导零抑�?
                        char_code <= (ch1_freq_d4 == 4'd0) ? 8'd32 : digit_to_ascii(ch1_freq_d4);
                        char_col <= pixel_x_d1 - COL_FREQ_X - 12'd8;
                        in_char_area <= ch1_enable;
                    end
                    else if (pixel_x_d1 >= COL_FREQ_X + 24 && pixel_x_d1 < COL_FREQ_X + 40) begin
                        // �?位：千位 (前导零抑�?
                        char_code <= ((ch1_freq_d4 == 4'd0) && (ch1_freq_d3 == 4'd0)) ? 8'd32 : digit_to_ascii(ch1_freq_d3);
                        char_col <= pixel_x_d1 - COL_FREQ_X - 12'd24;
                        in_char_area <= ch1_enable;
                    end
                    else if (pixel_x_d1 >= COL_FREQ_X + 40 && pixel_x_d1 < COL_FREQ_X + 56) begin
                        // �?位：百位
                        char_code <= digit_to_ascii(ch1_freq_d2);
                        char_col <= pixel_x_d1 - COL_FREQ_X - 12'd40;
                        in_char_area <= ch1_enable;
                    end
                    else if (pixel_x_d1 >= COL_FREQ_X + 56 && pixel_x_d1 < COL_FREQ_X + 72) begin
                        // �?位：十位
                        char_code <= digit_to_ascii(ch1_freq_d1);
                        char_col <= pixel_x_d1 - COL_FREQ_X - 12'd56;
                        in_char_area <= ch1_enable;
                    end
                    else if (pixel_x_d1 >= COL_FREQ_X + 72 && pixel_x_d1 < COL_FREQ_X + 88) begin
                        // �?位：个位
                        char_code <= digit_to_ascii(ch1_freq_d0);
                        char_col <= pixel_x_d1 - COL_FREQ_X - 12'd72;
                        in_char_area <= ch1_enable;
                    end
                    else if (pixel_x_d1 >= COL_FREQ_X + 88 && pixel_x_d1 < COL_FREQ_X + 104) begin
                        char_code <= 8'd72;  // 'H'
                        char_col <= pixel_x_d1 - COL_FREQ_X - 12'd88;
                        in_char_area <= ch1_enable;
                    end
                    else if (pixel_x_d1 >= COL_FREQ_X + 104 && pixel_x_d1 < COL_FREQ_X + 120) begin
                        char_code <= 8'd122; // 'z'
                        char_col <= pixel_x_d1 - COL_FREQ_X - 12'd104;
                        in_char_area <= ch1_enable;
                    end
                    else begin
                        in_char_area <= 1'b0;
                    end
                end else if (ch1_freq_unit == 2'd1) begin
                    // kHz模式：显�?"100.5kHz" (1位小�?
                    // 输入格式：ch1_freq = 1005 表示 100.5kHz
                    // d0=个位（小数部分）, d1=十位（整数个位）, d2=百位（整数十位）, d3=千位（整数百位）
                    
                    if (pixel_x_d1 >= COL_FREQ_X + 8 && pixel_x_d1 < COL_FREQ_X + 24) begin
                        // 整数百位（d3）：前导零抑�?
                        char_code <= (ch1_freq_d3 == 4'd0) ? 8'd32 : digit_to_ascii(ch1_freq_d3);
                        char_col <= pixel_x_d1 - COL_FREQ_X - 12'd8;
                        in_char_area <= ch1_enable;
                    end
                    else if (pixel_x_d1 >= COL_FREQ_X + 24 && pixel_x_d1 < COL_FREQ_X + 40) begin
                        // 整数十位（d2）：当百位为0且十位为0时抑�?
                        char_code <= ((ch1_freq_d3 == 4'd0) && (ch1_freq_d2 == 4'd0)) ? 8'd32 : digit_to_ascii(ch1_freq_d2);
                        char_col <= pixel_x_d1 - COL_FREQ_X - 12'd24;
                        in_char_area <= ch1_enable;
                    end
                    else if (pixel_x_d1 >= COL_FREQ_X + 40 && pixel_x_d1 < COL_FREQ_X + 56) begin
                        // 整数个位（d1）：始终显示
                        char_code <= digit_to_ascii(ch1_freq_d1);
                        char_col <= pixel_x_d1 - COL_FREQ_X - 12'd40;
                        in_char_area <= ch1_enable;
                    end
                    else if (pixel_x_d1 >= COL_FREQ_X + 56 && pixel_x_d1 < COL_FREQ_X + 72) begin
                        char_code <= 8'd46;  // '.'
                        char_col <= pixel_x_d1 - COL_FREQ_X - 12'd56;
                        in_char_area <= ch1_enable;
                    end
                    else if (pixel_x_d1 >= COL_FREQ_X + 72 && pixel_x_d1 < COL_FREQ_X + 88) begin
                        // 小数�?位（d0�?
                        char_code <= digit_to_ascii(ch1_freq_d0);
                        char_col <= pixel_x_d1 - COL_FREQ_X - 12'd72;
                        in_char_area <= ch1_enable;
                    end
                    else if (pixel_x_d1 >= COL_FREQ_X + 88 && pixel_x_d1 < COL_FREQ_X + 104) begin
                        char_code <= 8'd107; // 'k'
                        char_col <= pixel_x_d1 - COL_FREQ_X - 12'd88;
                        in_char_area <= ch1_enable;
                    end
                    else if (pixel_x_d1 >= COL_FREQ_X + 104 && pixel_x_d1 < COL_FREQ_X + 120) begin
                        char_code <= 8'd72;  // 'H'
                        char_col <= pixel_x_d1 - COL_FREQ_X - 12'd104;
                        in_char_area <= ch1_enable;
                    end
                    else if (pixel_x_d1 >= COL_FREQ_X + 120 && pixel_x_d1 < COL_FREQ_X + 136) begin
                        char_code <= 8'd122; // 'z'
                        char_col <= pixel_x_d1 - COL_FREQ_X - 12'd120;
                        in_char_area <= ch1_enable;
                    end
                    else begin
                        in_char_area <= 1'b0;
                    end
                end else begin
                    // MHz模式：显�?"17.50MHz" (2位小�?
                    // 输入格式：ch1_freq = 1750 表示 17.50MHz
                    // d0=个位（小数第2位）, d1=十位（小数第1位）, d2=百位（整数个位）, d3=千位（整数十位）
                    
                    if (pixel_x_d1 >= COL_FREQ_X + 8 && pixel_x_d1 < COL_FREQ_X + 24) begin
                        // 整数十位（d3）：前导零抑�?
                        char_code <= (ch1_freq_d3 == 4'd0) ? 8'd32 : digit_to_ascii(ch1_freq_d3);
                        char_col <= pixel_x_d1 - COL_FREQ_X - 12'd8;
                        in_char_area <= ch1_enable;
                    end
                    else if (pixel_x_d1 >= COL_FREQ_X + 24 && pixel_x_d1 < COL_FREQ_X + 40) begin
                        // 整数个位（d2）：始终显示
                        char_code <= digit_to_ascii(ch1_freq_d2);
                        char_col <= pixel_x_d1 - COL_FREQ_X - 12'd24;
                        in_char_area <= ch1_enable;
                    end
                    else if (pixel_x_d1 >= COL_FREQ_X + 40 && pixel_x_d1 < COL_FREQ_X + 56) begin
                        char_code <= 8'd46;  // '.'
                        char_col <= pixel_x_d1 - COL_FREQ_X - 12'd40;
                        in_char_area <= ch1_enable;
                    end
                    else if (pixel_x_d1 >= COL_FREQ_X + 56 && pixel_x_d1 < COL_FREQ_X + 72) begin
                        // 小数�?位（d1�?
                        char_code <= digit_to_ascii(ch1_freq_d1);
                        char_col <= pixel_x_d1 - COL_FREQ_X - 12'd56;
                        in_char_area <= ch1_enable;
                    end
                    else if (pixel_x_d1 >= COL_FREQ_X + 72 && pixel_x_d1 < COL_FREQ_X + 88) begin
                        // 小数�?位（d0�?
                        char_code <= digit_to_ascii(ch1_freq_d0);
                        char_col <= pixel_x_d1 - COL_FREQ_X - 12'd72;
                        in_char_area <= ch1_enable;
                    end
                    else if (pixel_x_d1 >= COL_FREQ_X + 88 && pixel_x_d1 < COL_FREQ_X + 104) begin
                        char_code <= 8'd77;  // 'M'
                        char_col <= pixel_x_d1 - COL_FREQ_X - 12'd88;
                        in_char_area <= ch1_enable;
                    end
                    else if (pixel_x_d1 >= COL_FREQ_X + 104 && pixel_x_d1 < COL_FREQ_X + 120) begin
                        char_code <= 8'd72;  // 'H'
                        char_col <= pixel_x_d1 - COL_FREQ_X - 12'd104;
                        in_char_area <= ch1_enable;
                    end
                    else if (pixel_x_d1 >= COL_FREQ_X + 120 && pixel_x_d1 < COL_FREQ_X + 136) begin
                        char_code <= 8'd122; // 'z'
                        char_col <= pixel_x_d1 - COL_FREQ_X - 12'd120;
                        in_char_area <= ch1_enable;
                    end
                    else begin
                        in_char_area <= 1'b0;
                    end
                end
            end
            
            // �?: 幅度显示 "255mV" (前导零抑�?
            else if (pixel_x_d1 >= COL_AMPL_X && pixel_x_d1 < COL_AMPL_X + 120) begin
                if (pixel_x_d1 >= COL_AMPL_X + 8 && pixel_x_d1 < COL_AMPL_X + 24) begin
                    // 千位：前导零抑制
                    char_code <= (ch1_amp_d3 == 4'd0) ? 8'd32 : digit_to_ascii(ch1_amp_d3);
                    char_col <= pixel_x_d1 - COL_AMPL_X - 12'd8;
                    in_char_area <= ch1_enable;
                end
                else if (pixel_x_d1 >= COL_AMPL_X + 24 && pixel_x_d1 < COL_AMPL_X + 40) begin
                    // 百位：千位和百位都为0时抑�?
                    char_code <= ((ch1_amp_d3 == 4'd0) && (ch1_amp_d2 == 4'd0)) ? 8'd32 : digit_to_ascii(ch1_amp_d2);
                    char_col <= pixel_x_d1 - COL_AMPL_X - 12'd24;
                    in_char_area <= ch1_enable;
                end
                else if (pixel_x_d1 >= COL_AMPL_X + 40 && pixel_x_d1 < COL_AMPL_X + 56) begin
                    char_code <= digit_to_ascii(ch1_amp_d1);  // 十位：始终显�?
                    char_col <= pixel_x_d1 - COL_AMPL_X - 12'd40;
                    in_char_area <= ch1_enable;
                end
                else if (pixel_x_d1 >= COL_AMPL_X + 56 && pixel_x_d1 < COL_AMPL_X + 72) begin
                    char_code <= digit_to_ascii(ch1_amp_d0);  // 个位
                    char_col <= pixel_x_d1 - COL_AMPL_X - 12'd56;
                    in_char_area <= ch1_enable;
                end
                else if (pixel_x_d1 >= COL_AMPL_X + 72 && pixel_x_d1 < COL_AMPL_X + 88) begin
                    char_code <= 8'd109;  // 'm'
                    char_col <= pixel_x_d1 - COL_AMPL_X - 12'd72;
                    in_char_area <= ch1_enable;
                end
                else if (pixel_x_d1 >= COL_AMPL_X + 88 && pixel_x_d1 < COL_AMPL_X + 104) begin
                    char_code <= 8'd86;  // 'V'
                    char_col <= pixel_x_d1 - COL_AMPL_X - 12'd88;
                    in_char_area <= ch1_enable;
                end
                else begin
                    in_char_area <= 1'b0;
                end
            end
            
            // �?: 占空比显�?"50.0%"
            else if (pixel_x_d1 >= COL_DUTY_X && pixel_x_d1 < COL_DUTY_X + 120) begin
                if (pixel_x_d1 >= COL_DUTY_X + 8 && pixel_x_d1 < COL_DUTY_X + 24) begin
                    char_code <= digit_to_ascii(ch1_duty_d2);  // 百位（十位整数）
                    char_col <= pixel_x_d1 - COL_DUTY_X - 12'd8;
                    in_char_area <= ch1_enable;
                end
                else if (pixel_x_d1 >= COL_DUTY_X + 24 && pixel_x_d1 < COL_DUTY_X + 40) begin
                    char_code <= digit_to_ascii(ch1_duty_d1);  // 十位（个位整数）
                    char_col <= pixel_x_d1 - COL_DUTY_X - 12'd24;
                    in_char_area <= ch1_enable;
                end
                else if (pixel_x_d1 >= COL_DUTY_X + 40 && pixel_x_d1 < COL_DUTY_X + 56) begin
                    char_code <= 8'd46;  // '.'
                    char_col <= pixel_x_d1 - COL_DUTY_X - 12'd40;
                    in_char_area <= ch1_enable;
                end
                else if (pixel_x_d1 >= COL_DUTY_X + 56 && pixel_x_d1 < COL_DUTY_X + 72) begin
                    char_code <= digit_to_ascii(ch1_duty_d0);  // 小数�?
                    char_col <= pixel_x_d1 - COL_DUTY_X - 12'd56;
                    in_char_area <= ch1_enable;
                end
                else if (pixel_x_d1 >= COL_DUTY_X + 72 && pixel_x_d1 < COL_DUTY_X + 88) begin
                    char_code <= 8'd37;  // '%'
                    char_col <= pixel_x_d1 - COL_DUTY_X - 12'd72;
                    in_char_area <= ch1_enable;
                end
                else begin
                    in_char_area <= 1'b0;
                end
            end
            
            // �?: THD显示 "02.5%" �?"2.5%" (前导零抑�?
            else if (pixel_x_d1 >= COL_THD_X && pixel_x_d1 < COL_THD_X + 120) begin
                if (pixel_x_d1 >= COL_THD_X + 8 && pixel_x_d1 < COL_THD_X + 24) begin
                    // 十位：前导零抑制�?-99.9%范围�?
                    char_code <= (ch1_thd_d2 == 4'd0) ? 8'd32 : digit_to_ascii(ch1_thd_d2);
                    char_col <= pixel_x_d1 - COL_THD_X - 12'd8;
                    in_char_area <= ch1_enable;
                end
                else if (pixel_x_d1 >= COL_THD_X + 24 && pixel_x_d1 < COL_THD_X + 40) begin
                    char_code <= digit_to_ascii(ch1_thd_d1);  // 个位：始终显�?
                    char_col <= pixel_x_d1 - COL_THD_X - 12'd24;
                    in_char_area <= ch1_enable;
                end
                else if (pixel_x_d1 >= COL_THD_X + 40 && pixel_x_d1 < COL_THD_X + 56) begin
                    char_code <= 8'd46;  // '.'
                    char_col <= pixel_x_d1 - COL_THD_X - 12'd40;
                    in_char_area <= ch1_enable;
                end
                else if (pixel_x_d1 >= COL_THD_X + 56 && pixel_x_d1 < COL_THD_X + 72) begin
                    char_code <= digit_to_ascii(ch1_thd_d0);  // 小数�?
                    char_col <= pixel_x_d1 - COL_THD_X - 12'd56;
                    in_char_area <= ch1_enable;
                end
                else if (pixel_x_d1 >= COL_THD_X + 72 && pixel_x_d1 < COL_THD_X + 88) begin
                    char_code <= 8'd37;  // '%'
                    char_col <= pixel_x_d1 - COL_THD_X - 12'd72;
                    in_char_area <= ch1_enable;
                end
                else begin
                    in_char_area <= 1'b0;
                end
            end
            
            // �?: 波形类型显示
            else if (pixel_x_d1 >= COL_WAVE_X && pixel_x_d1 < COL_WAVE_X + 600) begin
                // 根据ch1_waveform_type显示波形名称
                case (ch1_waveform_type)
                    3'd1: begin  // Sine
                        if (pixel_x_d1 >= COL_WAVE_X + 8 && pixel_x_d1 < COL_WAVE_X + 24) begin
                            char_code <= 8'd83;  // 'S'
                            char_col <= pixel_x_d1 - COL_WAVE_X - 12'd8;
                            in_char_area <= ch1_enable;
                        end
                        else if (pixel_x_d1 >= COL_WAVE_X + 24 && pixel_x_d1 < COL_WAVE_X + 40) begin
                            char_code <= 8'd105; // 'i'
                            char_col <= pixel_x_d1 - COL_WAVE_X - 12'd24;
                            in_char_area <= ch1_enable;
                        end
                        else if (pixel_x_d1 >= COL_WAVE_X + 40 && pixel_x_d1 < COL_WAVE_X + 56) begin
                            char_code <= 8'd110; // 'n'
                            char_col <= pixel_x_d1 - COL_WAVE_X - 12'd40;
                            in_char_area <= ch1_enable;
                        end
                        else if (pixel_x_d1 >= COL_WAVE_X + 56 && pixel_x_d1 < COL_WAVE_X + 72) begin
                            char_code <= 8'd101; // 'e'
                            char_col <= pixel_x_d1 - COL_WAVE_X - 12'd56;
                            in_char_area <= ch1_enable;
                        end
                        else begin
                            in_char_area <= 1'b0;
                        end
                    end
                    3'd2: begin  // Square
                        if (pixel_x_d1 >= COL_WAVE_X + 8 && pixel_x_d1 < COL_WAVE_X + 24) begin
                            char_code <= 8'd83;  // 'S'
                            char_col <= pixel_x_d1 - COL_WAVE_X - 12'd8;
                            in_char_area <= ch1_enable;
                        end
                        else if (pixel_x_d1 >= COL_WAVE_X + 24 && pixel_x_d1 < COL_WAVE_X + 40) begin
                            char_code <= 8'd113; // 'q'
                            char_col <= pixel_x_d1 - COL_WAVE_X - 12'd24;
                            in_char_area <= ch1_enable;
                        end
                        else if (pixel_x_d1 >= COL_WAVE_X + 40 && pixel_x_d1 < COL_WAVE_X + 56) begin
                            char_code <= 8'd117; // 'u'
                            char_col <= pixel_x_d1 - COL_WAVE_X - 12'd40;
                            in_char_area <= ch1_enable;
                        end
                        else if (pixel_x_d1 >= COL_WAVE_X + 56 && pixel_x_d1 < COL_WAVE_X + 72) begin
                            char_code <= 8'd97;  // 'a'
                            char_col <= pixel_x_d1 - COL_WAVE_X - 12'd56;
                            in_char_area <= ch1_enable;
                        end
                        else if (pixel_x_d1 >= COL_WAVE_X + 72 && pixel_x_d1 < COL_WAVE_X + 88) begin
                            char_code <= 8'd114; // 'r'
                            char_col <= pixel_x_d1 - COL_WAVE_X - 12'd72;
                            in_char_area <= ch1_enable;
                        end
                        else if (pixel_x_d1 >= COL_WAVE_X + 88 && pixel_x_d1 < COL_WAVE_X + 104) begin
                            char_code <= 8'd101; // 'e'
                            char_col <= pixel_x_d1 - COL_WAVE_X - 12'd88;
                            in_char_area <= ch1_enable;
                        end
                        else begin
                            in_char_area <= 1'b0;
                        end
                    end
                    3'd3: begin  // Triangle
                        if (pixel_x_d1 >= COL_WAVE_X + 8 && pixel_x_d1 < COL_WAVE_X + 24) begin
                            char_code <= 8'd84;  // 'T'
                            char_col <= pixel_x_d1 - COL_WAVE_X - 12'd8;
                            in_char_area <= ch1_enable;
                        end
                        else if (pixel_x_d1 >= COL_WAVE_X + 24 && pixel_x_d1 < COL_WAVE_X + 40) begin
                            char_code <= 8'd114; // 'r'
                            char_col <= pixel_x_d1 - COL_WAVE_X - 12'd24;
                            in_char_area <= ch1_enable;
                        end
                        else if (pixel_x_d1 >= COL_WAVE_X + 40 && pixel_x_d1 < COL_WAVE_X + 56) begin
                            char_code <= 8'd105; // 'i'
                            char_col <= pixel_x_d1 - COL_WAVE_X - 12'd40;
                            in_char_area <= ch1_enable;
                        end
                        else begin
                            in_char_area <= 1'b0;
                        end
                    end
                    3'd4: begin  // Sawtooth
                        if (pixel_x_d1 >= COL_WAVE_X + 8 && pixel_x_d1 < COL_WAVE_X + 24) begin
                            char_code <= 8'd83;  // 'S'
                            char_col <= pixel_x_d1 - COL_WAVE_X - 12'd8;
                            in_char_area <= ch1_enable;
                        end
                        else if (pixel_x_d1 >= COL_WAVE_X + 24 && pixel_x_d1 < COL_WAVE_X + 40) begin
                            char_code <= 8'd97;  // 'a'
                            char_col <= pixel_x_d1 - COL_WAVE_X - 12'd24;
                            in_char_area <= ch1_enable;
                        end
                        else if (pixel_x_d1 >= COL_WAVE_X + 40 && pixel_x_d1 < COL_WAVE_X + 56) begin
                            char_code <= 8'd119; // 'w'
                            char_col <= pixel_x_d1 - COL_WAVE_X - 12'd40;
                            in_char_area <= ch1_enable;
                        end
                        else begin
                            in_char_area <= 1'b0;
                        end
                    end
                    default: begin  // Unknown或Noise
                        if (pixel_x_d1 >= COL_WAVE_X + 8 && pixel_x_d1 < COL_WAVE_X + 24) begin
                            char_code <= 8'd45;  // '-'
                            char_col <= pixel_x_d1 - COL_WAVE_X - 12'd8;
                            in_char_area <= ch1_enable;
                        end
                        else begin
                            in_char_area <= 1'b0;
                        end
                    end
                endcase
            end
            end  // 结束 if (pixel_y_d1 < TABLE_Y_CH1 + 32)
        end
        
        //=====================================================================
        // CH2数据�?(Y: 640-680, 40px�?
        //=====================================================================
        else if (pixel_y_d1 >= TABLE_Y_CH2 && pixel_y_d1 < TABLE_Y_CH2 + ROW_HEIGHT) begin
            // 只在行内�?2px显示字符�?0px行高，字�?2px，底�?px留空�?
            if (pixel_y_d1 < TABLE_Y_CH2 + 32) begin
                char_row <= pixel_y_d1 - TABLE_Y_CH2;  // 0-31，不需要左�?
            
                // �?: 通道�?"2"
                if (pixel_x_d1 >= COL_CH_X + 12 && pixel_x_d1 < COL_CH_X + 28) begin
                char_code <= 8'd50;  // '2'
                char_col <= pixel_x_d1 - COL_CH_X - 12'd12;
                in_char_area <= ch2_enable;
            end
            
            // �?: 频率显示 (自适应Hz/kHz/MHz)
            else if (pixel_x_d1 >= COL_FREQ_X && pixel_x_d1 < COL_FREQ_X + 200) begin
                if (ch2_freq_unit == 2'd0) begin
                    // Hz模式：显�?位整�?+ "Hz"
                    if (pixel_x_d1 >= COL_FREQ_X + 8 && pixel_x_d1 < COL_FREQ_X + 24) begin
                        char_code <= (ch2_freq_d4 == 4'd0) ? 8'd32 : digit_to_ascii(ch2_freq_d4);
                        char_col <= pixel_x_d1 - COL_FREQ_X - 12'd8;
                        in_char_area <= ch2_enable;
                    end
                    else if (pixel_x_d1 >= COL_FREQ_X + 24 && pixel_x_d1 < COL_FREQ_X + 40) begin
                        char_code <= ((ch2_freq_d4 == 4'd0) && (ch2_freq_d3 == 4'd0)) ? 8'd32 : digit_to_ascii(ch2_freq_d3);
                        char_col <= pixel_x_d1 - COL_FREQ_X - 12'd24;
                        in_char_area <= ch2_enable;
                    end
                    else if (pixel_x_d1 >= COL_FREQ_X + 40 && pixel_x_d1 < COL_FREQ_X + 56) begin
                        char_code <= digit_to_ascii(ch2_freq_d2);
                        char_col <= pixel_x_d1 - COL_FREQ_X - 12'd40;
                        in_char_area <= ch2_enable;
                    end
                    else if (pixel_x_d1 >= COL_FREQ_X + 56 && pixel_x_d1 < COL_FREQ_X + 72) begin
                        char_code <= digit_to_ascii(ch2_freq_d1);
                        char_col <= pixel_x_d1 - COL_FREQ_X - 12'd56;
                        in_char_area <= ch2_enable;
                    end
                    else if (pixel_x_d1 >= COL_FREQ_X + 72 && pixel_x_d1 < COL_FREQ_X + 88) begin
                        char_code <= digit_to_ascii(ch2_freq_d0);
                        char_col <= pixel_x_d1 - COL_FREQ_X - 12'd72;
                        in_char_area <= ch2_enable;
                    end
                    else if (pixel_x_d1 >= COL_FREQ_X + 88 && pixel_x_d1 < COL_FREQ_X + 104) begin
                        char_code <= 8'd72;  // 'H'
                        char_col <= pixel_x_d1 - COL_FREQ_X - 12'd88;
                        in_char_area <= ch2_enable;
                    end
                    else if (pixel_x_d1 >= COL_FREQ_X + 104 && pixel_x_d1 < COL_FREQ_X + 120) begin
                        char_code <= 8'd122; // 'z'
                        char_col <= pixel_x_d1 - COL_FREQ_X - 12'd104;
                        in_char_area <= ch2_enable;
                    end
                    else begin
                        in_char_area <= 1'b0;
                    end
                end else if (ch2_freq_unit == 2'd1) begin
                    // kHz模式：显�?"100.5kHz" (1位小�?
                    // 输入格式：ch2_freq = 1005 表示 100.5kHz
                    // d0=个位（小数部分）, d1=十位（整数个位）, d2=百位（整数十位）, d3=千位（整数百位）
                    
                    if (pixel_x_d1 >= COL_FREQ_X + 8 && pixel_x_d1 < COL_FREQ_X + 24) begin
                        // 整数百位（d3）：前导零抑�?
                        char_code <= (ch2_freq_d3 == 4'd0) ? 8'd32 : digit_to_ascii(ch2_freq_d3);
                        char_col <= pixel_x_d1 - COL_FREQ_X - 12'd8;
                        in_char_area <= ch2_enable;
                    end
                    else if (pixel_x_d1 >= COL_FREQ_X + 24 && pixel_x_d1 < COL_FREQ_X + 40) begin
                        // 整数十位（d2）：当百位为0且十位为0时抑�?
                        char_code <= ((ch2_freq_d3 == 4'd0) && (ch2_freq_d2 == 4'd0)) ? 8'd32 : digit_to_ascii(ch2_freq_d2);
                        char_col <= pixel_x_d1 - COL_FREQ_X - 12'd24;
                        in_char_area <= ch2_enable;
                    end
                    else if (pixel_x_d1 >= COL_FREQ_X + 40 && pixel_x_d1 < COL_FREQ_X + 56) begin
                        // 整数个位（d1）：始终显示
                        char_code <= digit_to_ascii(ch2_freq_d1);
                        char_col <= pixel_x_d1 - COL_FREQ_X - 12'd40;
                        in_char_area <= ch2_enable;
                    end
                    else if (pixel_x_d1 >= COL_FREQ_X + 56 && pixel_x_d1 < COL_FREQ_X + 72) begin
                        char_code <= 8'd46;  // '.'
                        char_col <= pixel_x_d1 - COL_FREQ_X - 12'd56;
                        in_char_area <= ch2_enable;
                    end
                    else if (pixel_x_d1 >= COL_FREQ_X + 72 && pixel_x_d1 < COL_FREQ_X + 88) begin
                        // 小数�?位（d0�?
                        char_code <= digit_to_ascii(ch2_freq_d0);
                        char_col <= pixel_x_d1 - COL_FREQ_X - 12'd72;
                        in_char_area <= ch2_enable;
                    end
                    else if (pixel_x_d1 >= COL_FREQ_X + 88 && pixel_x_d1 < COL_FREQ_X + 104) begin
                        char_code <= 8'd107; // 'k'
                        char_col <= pixel_x_d1 - COL_FREQ_X - 12'd88;
                        in_char_area <= ch2_enable;
                    end
                    else if (pixel_x_d1 >= COL_FREQ_X + 104 && pixel_x_d1 < COL_FREQ_X + 120) begin
                        char_code <= 8'd72;  // 'H'
                        char_col <= pixel_x_d1 - COL_FREQ_X - 12'd104;
                        in_char_area <= ch2_enable;
                    end
                    else if (pixel_x_d1 >= COL_FREQ_X + 120 && pixel_x_d1 < COL_FREQ_X + 136) begin
                        char_code <= 8'd122; // 'z'
                        char_col <= pixel_x_d1 - COL_FREQ_X - 12'd120;
                        in_char_area <= ch2_enable;
                    end
                    else begin
                        in_char_area <= 1'b0;
                    end
                end else begin
                    // MHz模式：显�?"17.50MHz" (2位小�?
                    // 输入格式：ch2_freq = 1750 表示 17.50MHz
                    // d0=个位（小数第2位）, d1=十位（小数第1位）, d2=百位（整数个位）, d3=千位（整数十位）
                    
                    if (pixel_x_d1 >= COL_FREQ_X + 8 && pixel_x_d1 < COL_FREQ_X + 24) begin
                        // 整数十位（d3）：前导零抑�?
                        char_code <= (ch2_freq_d3 == 4'd0) ? 8'd32 : digit_to_ascii(ch2_freq_d3);
                        char_col <= pixel_x_d1 - COL_FREQ_X - 12'd8;
                        in_char_area <= ch2_enable;
                    end
                    else if (pixel_x_d1 >= COL_FREQ_X + 24 && pixel_x_d1 < COL_FREQ_X + 40) begin
                        // 整数个位（d2）：始终显示
                        char_code <= digit_to_ascii(ch2_freq_d2);
                        char_col <= pixel_x_d1 - COL_FREQ_X - 12'd24;
                        in_char_area <= ch2_enable;
                    end
                    else if (pixel_x_d1 >= COL_FREQ_X + 40 && pixel_x_d1 < COL_FREQ_X + 56) begin
                        char_code <= 8'd46;  // '.'
                        char_col <= pixel_x_d1 - COL_FREQ_X - 12'd40;
                        in_char_area <= ch2_enable;
                    end
                    else if (pixel_x_d1 >= COL_FREQ_X + 56 && pixel_x_d1 < COL_FREQ_X + 72) begin
                        // 小数�?位（d1�?
                        char_code <= digit_to_ascii(ch2_freq_d1);
                        char_col <= pixel_x_d1 - COL_FREQ_X - 12'd56;
                        in_char_area <= ch2_enable;
                    end
                    else if (pixel_x_d1 >= COL_FREQ_X + 72 && pixel_x_d1 < COL_FREQ_X + 88) begin
                        // 小数�?位（d0�?
                        char_code <= digit_to_ascii(ch2_freq_d0);
                        char_col <= pixel_x_d1 - COL_FREQ_X - 12'd72;
                        in_char_area <= ch2_enable;
                    end
                    else if (pixel_x_d1 >= COL_FREQ_X + 88 && pixel_x_d1 < COL_FREQ_X + 104) begin
                        char_code <= 8'd77;  // 'M'
                        char_col <= pixel_x_d1 - COL_FREQ_X - 12'd88;
                        in_char_area <= ch2_enable;
                    end
                    else if (pixel_x_d1 >= COL_FREQ_X + 104 && pixel_x_d1 < COL_FREQ_X + 120) begin
                        char_code <= 8'd72;  // 'H'
                        char_col <= pixel_x_d1 - COL_FREQ_X - 12'd104;
                        in_char_area <= ch2_enable;
                    end
                    else if (pixel_x_d1 >= COL_FREQ_X + 120 && pixel_x_d1 < COL_FREQ_X + 136) begin
                        char_code <= 8'd122; // 'z'
                        char_col <= pixel_x_d1 - COL_FREQ_X - 12'd120;
                        in_char_area <= ch2_enable;
                    end
                    else begin
                        in_char_area <= 1'b0;
                    end
                end
            end
            
            // �?: 幅度显示 "255mV" (前导零抑�?
            else if (pixel_x_d1 >= COL_AMPL_X && pixel_x_d1 < COL_AMPL_X + 120) begin
                if (pixel_x_d1 >= COL_AMPL_X + 8 && pixel_x_d1 < COL_AMPL_X + 24) begin
                    // 千位：前导零抑制
                    char_code <= (ch2_amp_d3 == 4'd0) ? 8'd32 : digit_to_ascii(ch2_amp_d3);
                    char_col <= pixel_x_d1 - COL_AMPL_X - 12'd8;
                    in_char_area <= ch2_enable;
                end
                else if (pixel_x_d1 >= COL_AMPL_X + 24 && pixel_x_d1 < COL_AMPL_X + 40) begin
                    // 百位：千位和百位都为0时抑�?
                    char_code <= ((ch2_amp_d3 == 4'd0) && (ch2_amp_d2 == 4'd0)) ? 8'd32 : digit_to_ascii(ch2_amp_d2);
                    char_col <= pixel_x_d1 - COL_AMPL_X - 12'd24;
                    in_char_area <= ch2_enable;
                end
                else if (pixel_x_d1 >= COL_AMPL_X + 40 && pixel_x_d1 < COL_AMPL_X + 56) begin
                    char_code <= digit_to_ascii(ch2_amp_d1);  // 十位：始终显�?
                    char_col <= pixel_x_d1 - COL_AMPL_X - 12'd40;
                    in_char_area <= ch2_enable;
                end
                else if (pixel_x_d1 >= COL_AMPL_X + 56 && pixel_x_d1 < COL_AMPL_X + 72) begin
                    char_code <= digit_to_ascii(ch2_amp_d0);  // 个位：始终显�?
                    char_col <= pixel_x_d1 - COL_AMPL_X - 12'd56;
                    in_char_area <= ch2_enable;
                end
                else if (pixel_x_d1 >= COL_AMPL_X + 72 && pixel_x_d1 < COL_AMPL_X + 88) begin
                    char_code <= 8'd109;  // 'm'
                    char_col <= pixel_x_d1 - COL_AMPL_X - 12'd72;
                    in_char_area <= ch2_enable;
                end
                else if (pixel_x_d1 >= COL_AMPL_X + 88 && pixel_x_d1 < COL_AMPL_X + 104) begin
                    char_code <= 8'd86;  // 'V'
                    char_col <= pixel_x_d1 - COL_AMPL_X - 12'd88;
                    in_char_area <= ch2_enable;
                end
                else begin
                    in_char_area <= 1'b0;
                end
            end
            
            // �?: 占空比显�?"50.0%"
            else if (pixel_x_d1 >= COL_DUTY_X && pixel_x_d1 < COL_DUTY_X + 120) begin
                if (pixel_x_d1 >= COL_DUTY_X + 8 && pixel_x_d1 < COL_DUTY_X + 24) begin
                    char_code <= digit_to_ascii(ch2_duty_d2);
                    char_col <= pixel_x_d1 - COL_DUTY_X - 12'd8;
                    in_char_area <= ch2_enable;
                end
                else if (pixel_x_d1 >= COL_DUTY_X + 24 && pixel_x_d1 < COL_DUTY_X + 40) begin
                    char_code <= digit_to_ascii(ch2_duty_d1);
                    char_col <= pixel_x_d1 - COL_DUTY_X - 12'd24;
                    in_char_area <= ch2_enable;
                end
                else if (pixel_x_d1 >= COL_DUTY_X + 40 && pixel_x_d1 < COL_DUTY_X + 56) begin
                    char_code <= 8'd46;  // '.'
                    char_col <= pixel_x_d1 - COL_DUTY_X - 12'd40;
                    in_char_area <= ch2_enable;
                end
                else if (pixel_x_d1 >= COL_DUTY_X + 56 && pixel_x_d1 < COL_DUTY_X + 72) begin
                    char_code <= digit_to_ascii(ch2_duty_d0);
                    char_col <= pixel_x_d1 - COL_DUTY_X - 12'd56;
                    in_char_area <= ch2_enable;
                end
                else if (pixel_x_d1 >= COL_DUTY_X + 72 && pixel_x_d1 < COL_DUTY_X + 88) begin
                    char_code <= 8'd37;  // '%'
                    char_col <= pixel_x_d1 - COL_DUTY_X - 12'd72;
                    in_char_area <= ch2_enable;
                end
                else begin
                    in_char_area <= 1'b0;
                end
            end
            
            // �?: THD显示 "02.5%" �?"2.5%" (前导零抑�?
            else if (pixel_x_d1 >= COL_THD_X && pixel_x_d1 < COL_THD_X + 120) begin
                if (pixel_x_d1 >= COL_THD_X + 8 && pixel_x_d1 < COL_THD_X + 24) begin
                    // 十位：前导零抑制
                    char_code <= (ch2_thd_d2 == 4'd0) ? 8'd32 : digit_to_ascii(ch2_thd_d2);
                    char_col <= pixel_x_d1 - COL_THD_X - 12'd8;
                    in_char_area <= ch2_enable;
                end
                else if (pixel_x_d1 >= COL_THD_X + 24 && pixel_x_d1 < COL_THD_X + 40) begin
                    char_code <= digit_to_ascii(ch2_thd_d1);  // 个位：始终显�?
                    char_col <= pixel_x_d1 - COL_THD_X - 12'd24;
                    in_char_area <= ch2_enable;
                end
                else if (pixel_x_d1 >= COL_THD_X + 40 && pixel_x_d1 < COL_THD_X + 56) begin
                    char_code <= 8'd46;  // '.'
                    char_col <= pixel_x_d1 - COL_THD_X - 12'd40;
                    in_char_area <= ch2_enable;
                end
                else if (pixel_x_d1 >= COL_THD_X + 56 && pixel_x_d1 < COL_THD_X + 72) begin
                    char_code <= digit_to_ascii(ch2_thd_d0);
                    char_col <= pixel_x_d1 - COL_THD_X - 12'd56;
                    in_char_area <= ch2_enable;
                end
                else if (pixel_x_d1 >= COL_THD_X + 72 && pixel_x_d1 < COL_THD_X + 88) begin
                    char_code <= 8'd37;  // '%'
                    char_col <= pixel_x_d1 - COL_THD_X - 12'd72;
                    in_char_area <= ch2_enable;
                end
                else begin
                    in_char_area <= 1'b0;
                end
            end
            
            // �?: 波形类型显示
            else if (pixel_x_d1 >= COL_WAVE_X && pixel_x_d1 < COL_WAVE_X + 600) begin
                case (ch2_waveform_type)
                    3'd1: begin  // Sine
                        if (pixel_x_d1 >= COL_WAVE_X + 8 && pixel_x_d1 < COL_WAVE_X + 24) begin
                            char_code <= 8'd83;  // 'S'
                            char_col <= pixel_x_d1 - COL_WAVE_X - 12'd8;
                            in_char_area <= ch2_enable;
                        end
                        else if (pixel_x_d1 >= COL_WAVE_X + 24 && pixel_x_d1 < COL_WAVE_X + 40) begin
                            char_code <= 8'd105; // 'i'
                            char_col <= pixel_x_d1 - COL_WAVE_X - 12'd24;
                            in_char_area <= ch2_enable;
                        end
                        else if (pixel_x_d1 >= COL_WAVE_X + 40 && pixel_x_d1 < COL_WAVE_X + 56) begin
                            char_code <= 8'd110; // 'n'
                            char_col <= pixel_x_d1 - COL_WAVE_X - 12'd40;
                            in_char_area <= ch2_enable;
                        end
                        else if (pixel_x_d1 >= COL_WAVE_X + 56 && pixel_x_d1 < COL_WAVE_X + 72) begin
                            char_code <= 8'd101; // 'e'
                            char_col <= pixel_x_d1 - COL_WAVE_X - 12'd56;
                            in_char_area <= ch2_enable;
                        end
                        else begin
                            in_char_area <= 1'b0;
                        end
                    end
                    3'd2: begin  // Square
                        if (pixel_x_d1 >= COL_WAVE_X + 8 && pixel_x_d1 < COL_WAVE_X + 24) begin
                            char_code <= 8'd83;  // 'S'
                            char_col <= pixel_x_d1 - COL_WAVE_X - 12'd8;
                            in_char_area <= ch2_enable;
                        end
                        else if (pixel_x_d1 >= COL_WAVE_X + 24 && pixel_x_d1 < COL_WAVE_X + 40) begin
                            char_code <= 8'd113; // 'q'
                            char_col <= pixel_x_d1 - COL_WAVE_X - 12'd24;
                            in_char_area <= ch2_enable;
                        end
                        else if (pixel_x_d1 >= COL_WAVE_X + 40 && pixel_x_d1 < COL_WAVE_X + 56) begin
                            char_code <= 8'd117; // 'u'
                            char_col <= pixel_x_d1 - COL_WAVE_X - 12'd40;
                            in_char_area <= ch2_enable;
                        end
                        else if (pixel_x_d1 >= COL_WAVE_X + 56 && pixel_x_d1 < COL_WAVE_X + 72) begin
                            char_code <= 8'd97;  // 'a'
                            char_col <= pixel_x_d1 - COL_WAVE_X - 12'd56;
                            in_char_area <= ch2_enable;
                        end
                        else if (pixel_x_d1 >= COL_WAVE_X + 72 && pixel_x_d1 < COL_WAVE_X + 88) begin
                            char_code <= 8'd114; // 'r'
                            char_col <= pixel_x_d1 - COL_WAVE_X - 12'd72;
                            in_char_area <= ch2_enable;
                        end
                        else if (pixel_x_d1 >= COL_WAVE_X + 88 && pixel_x_d1 < COL_WAVE_X + 104) begin
                            char_code <= 8'd101; // 'e'
                            char_col <= pixel_x_d1 - COL_WAVE_X - 12'd88;
                            in_char_area <= ch2_enable;
                        end
                        else begin
                            in_char_area <= 1'b0;
                        end
                    end
                    3'd3: begin  // Triangle
                        if (pixel_x_d1 >= COL_WAVE_X + 8 && pixel_x_d1 < COL_WAVE_X + 24) begin
                            char_code <= 8'd84;  // 'T'
                            char_col <= pixel_x_d1 - COL_WAVE_X - 12'd8;
                            in_char_area <= ch2_enable;
                        end
                        else if (pixel_x_d1 >= COL_WAVE_X + 24 && pixel_x_d1 < COL_WAVE_X + 40) begin
                            char_code <= 8'd114; // 'r'
                            char_col <= pixel_x_d1 - COL_WAVE_X - 12'd24;
                            in_char_area <= ch2_enable;
                        end
                        else if (pixel_x_d1 >= COL_WAVE_X + 40 && pixel_x_d1 < COL_WAVE_X + 56) begin
                            char_code <= 8'd105; // 'i'
                            char_col <= pixel_x_d1 - COL_WAVE_X - 12'd40;
                            in_char_area <= ch2_enable;
                        end
                        else begin
                            in_char_area <= 1'b0;
                        end
                    end
                    3'd4: begin  // Sawtooth
                        if (pixel_x_d1 >= COL_WAVE_X + 8 && pixel_x_d1 < COL_WAVE_X + 24) begin
                            char_code <= 8'd83;  // 'S'
                            char_col <= pixel_x_d1 - COL_WAVE_X - 12'd8;
                            in_char_area <= ch2_enable;
                        end
                        else if (pixel_x_d1 >= COL_WAVE_X + 24 && pixel_x_d1 < COL_WAVE_X + 40) begin
                            char_code <= 8'd97;  // 'a'
                            char_col <= pixel_x_d1 - COL_WAVE_X - 12'd24;
                            in_char_area <= ch2_enable;
                        end
                        else if (pixel_x_d1 >= COL_WAVE_X + 40 && pixel_x_d1 < COL_WAVE_X + 56) begin
                            char_code <= 8'd119; // 'w'
                            char_col <= pixel_x_d1 - COL_WAVE_X - 12'd40;
                            in_char_area <= ch2_enable;
                        end
                        else begin
                            in_char_area <= 1'b0;
                        end
                    end
                    default: begin  // Unknown或Noise
                        if (pixel_x_d1 >= COL_WAVE_X + 8 && pixel_x_d1 < COL_WAVE_X + 24) begin
                            char_code <= 8'd45;  // '-'
                            char_col <= pixel_x_d1 - COL_WAVE_X - 12'd8;
                            in_char_area <= ch2_enable;
                        end
                        else begin
                            in_char_area <= 1'b0;
                        end
                    end
                endcase
            end
            end  // 结束 if (pixel_y_d1 < TABLE_Y_CH2 + 32)
        end
        
        //=====================================================================
        // 相位差行 (Y: 680-720, 40px�? - 居中显示 "Phase Diff: XXX.X°"
        //=====================================================================
        else if (pixel_y_d1 >= TABLE_Y_PHASE && pixel_y_d1 < PARAM_Y_END) begin
            // 只在行内�?2px显示字符�?0px行高，字�?2px，底�?px留空�?
            if (pixel_y_d1 < TABLE_Y_PHASE + 32) begin
                char_row <= pixel_y_d1 - TABLE_Y_PHASE;  // 0-31，不需要左�?
            
                // 左对齐显�?"Phase: XXX.X°"
            
                // "Phase: "
                if (pixel_x_d1 >= 60 && pixel_x_d1 < 76) begin
                char_code <= 8'd80;  // 'P'
                char_col <= pixel_x_d1 - 12'd60;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 76 && pixel_x_d1 < 92) begin
                char_code <= 8'd104;  // 'h'
                char_col <= pixel_x_d1 - 12'd76;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 92 && pixel_x_d1 < 108) begin
                char_code <= 8'd97;  // 'a'
                char_col <= pixel_x_d1 - 12'd92;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 108 && pixel_x_d1 < 124) begin
                char_code <= 8'd115;  // 's'
                char_col <= pixel_x_d1 - 12'd108;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 124 && pixel_x_d1 < 140) begin
                char_code <= 8'd101;  // 'e'
                char_col <= pixel_x_d1 - 12'd124;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 140 && pixel_x_d1 < 156) begin
                char_code <= 8'd58;  // ':'
                char_col <= pixel_x_d1 - 12'd140;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 156 && pixel_x_d1 < 172) begin
                char_code <= 8'd32;  // ' '
                char_col <= pixel_x_d1 - 12'd156;
                in_char_area <= 1'b1;
            end

            // "±XXX.X°" - 相位差数值（-180.0° ~ +179.9°�?
            // 符号�?
            else if (pixel_x_d1 >= 172 && pixel_x_d1 < 188) begin
                char_code <= phase_sign ? 8'd45 : 8'd43;  // '-' or '+'
                char_col <= pixel_x_d1 - 12'd172;
                in_char_area <= 1'b1;
            end
            // 百位
            else if (pixel_x_d1 >= 188 && pixel_x_d1 < 204) begin
                char_code <= digit_to_ascii(phase_d3);
                char_col <= pixel_x_d1 - 12'd188;
                in_char_area <= 1'b1;
            end
            // 十位
            else if (pixel_x_d1 >= 204 && pixel_x_d1 < 220) begin
                char_code <= digit_to_ascii(phase_d2);
                char_col <= pixel_x_d1 - 12'd204;
                in_char_area <= 1'b1;
            end
            // 个位
            else if (pixel_x_d1 >= 220 && pixel_x_d1 < 236) begin
                char_code <= digit_to_ascii(phase_d1);
                char_col <= pixel_x_d1 - 12'd220;
                in_char_area <= 1'b1;
            end
            // 小数�?
            else if (pixel_x_d1 >= 236 && pixel_x_d1 < 252) begin
                char_code <= 8'd46;  // '.'
                char_col <= pixel_x_d1 - 12'd236;
                in_char_area <= 1'b1;
            end
            // 小数�?
            else if (pixel_x_d1 >= 252 && pixel_x_d1 < 268) begin
                char_code <= digit_to_ascii(phase_d0);
                char_col <= pixel_x_d1 - 12'd252;
                in_char_area <= 1'b1;
            end
            // 度数符号 '°'
            else if (pixel_x_d1 >= 268 && pixel_x_d1 < 284) begin
                char_code <= 8'd176;  // '°' (度数符号)
                char_col <= pixel_x_d1 - 12'd268;
                in_char_area <= 1'b1;
            end
            else begin
                in_char_area <= 1'b0;
            end
            end  // 结束 if (pixel_y_d1 < TABLE_Y_PHASE + 32)
        end
    end  // 结束 if (pixel_y_d1 >= PARAM_Y_START && pixel_y_d1 < PARAM_Y_END)
    
    // ========== �?自动测试显示区域（屏幕右下角�?==========
    else if (auto_test_enable && pixel_y_d1 >= AUTO_TEST_Y_START && 
             pixel_y_d1 < (AUTO_TEST_Y_START + AUTO_TEST_HEIGHT) &&
             pixel_x_d1 >= AUTO_TEST_X_START && 
             pixel_x_d1 < (AUTO_TEST_X_START + AUTO_TEST_WIDTH)) begin
        
        // 计算行号和列�?
        auto_test_char_row <= (pixel_y_d1 - AUTO_TEST_Y_START) % AUTO_LINE_HEIGHT;
        auto_test_char_col <= (pixel_x_d1 - AUTO_TEST_X_START) % AUTO_CHAR_WIDTH;
        
        // 标题行：�?�?
        if (pixel_y_d1 < (AUTO_TEST_Y_START + AUTO_LINE_HEIGHT)) begin
            char_row <= auto_test_char_row;
            if (pixel_x_d1 >= AUTO_TEST_X_START && pixel_x_d1 < AUTO_TEST_X_START + 16*AUTO_CHAR_WIDTH) begin
                // "Auto Test Mode"
                case ((pixel_x_d1 - AUTO_TEST_X_START) / AUTO_CHAR_WIDTH)
                    0: char_code <= 8'd65;  // 'A'
                    1: char_code <= 8'd117; // 'u'
                    2: char_code <= 8'd116; // 't'
                    3: char_code <= 8'd111; // 'o'
                    4: char_code <= 8'd32;  // ' '
                    5: char_code <= 8'd84;  // 'T'
                    6: char_code <= 8'd101; // 'e'
                    7: char_code <= 8'd115; // 's'
                    8: char_code <= 8'd116; // 't'
                    default: char_code <= 8'd32;
                endcase
                char_col <= auto_test_char_col;
                in_char_area <= 1'b1;
            end
        end
        
        // 参数选择界面（param_adjust_mode == IDLE�?
        else if (param_adjust_mode == ADJUST_IDLE) begin
            char_row <= auto_test_char_row;
            
            // �?行："[0]Freq [1]Amp"
            if (pixel_y_d1 < (AUTO_TEST_Y_START + 2*AUTO_LINE_HEIGHT)) begin
                if (pixel_x_d1 >= AUTO_TEST_X_START && pixel_x_d1 < AUTO_TEST_X_START + 16*AUTO_CHAR_WIDTH) begin
                    case ((pixel_x_d1 - AUTO_TEST_X_START) / AUTO_CHAR_WIDTH)
                        0: char_code <= 8'd91;  // '['
                        1: char_code <= 8'd48;  // '0'
                        2: char_code <= 8'd93;  // ']'
                        3: char_code <= 8'd70;  // 'F'
                        4: char_code <= 8'd114; // 'r'
                        5: char_code <= 8'd101; // 'e'
                        6: char_code <= 8'd113; // 'q'
                        7: char_code <= 8'd32;  // ' '
                        8: char_code <= 8'd91;  // '['
                        9: char_code <= 8'd49;  // '1'
                        10: char_code <= 8'd93; // ']'
                        11: char_code <= 8'd65; // 'A'
                        12: char_code <= 8'd109; // 'm'
                        13: char_code <= 8'd112; // 'p'
                        default: char_code <= 8'd32;
                    endcase
                    char_col <= auto_test_char_col;
                    in_char_area <= 1'b1;
                end
            end
            
            // �?行："[2]Duty [3]THD"
            else if (pixel_y_d1 < (AUTO_TEST_Y_START + 3*AUTO_LINE_HEIGHT)) begin
                if (pixel_x_d1 >= AUTO_TEST_X_START && pixel_x_d1 < AUTO_TEST_X_START + 16*AUTO_CHAR_WIDTH) begin
                    case ((pixel_x_d1 - AUTO_TEST_X_START) / AUTO_CHAR_WIDTH)
                        0: char_code <= 8'd91;  // '['
                        1: char_code <= 8'd50;  // '2'
                        2: char_code <= 8'd93;  // ']'
                        3: char_code <= 8'd68;  // 'D'
                        4: char_code <= 8'd117; // 'u'
                        5: char_code <= 8'd116; // 't'
                        6: char_code <= 8'd121; // 'y'
                        7: char_code <= 8'd32;  // ' '
                        8: char_code <= 8'd91;  // '['
                        9: char_code <= 8'd51;  // '3'
                        10: char_code <= 8'd93; // ']'
                        11: char_code <= 8'd84; // 'T'
                        12: char_code <= 8'd72; // 'H'
                        13: char_code <= 8'd68; // 'D'
                        default: char_code <= 8'd32;
                    endcase
                    char_col <= auto_test_char_col;
                    in_char_area <= 1'b1;
                end
            end
            
            // �?行："[7]Exit"
            else if (pixel_y_d1 < (AUTO_TEST_Y_START + 4*AUTO_LINE_HEIGHT)) begin
                if (pixel_x_d1 >= AUTO_TEST_X_START && pixel_x_d1 < AUTO_TEST_X_START + 8*AUTO_CHAR_WIDTH) begin
                    case ((pixel_x_d1 - AUTO_TEST_X_START) / AUTO_CHAR_WIDTH)
                        0: char_code <= 8'd91;  // '['
                        1: char_code <= 8'd55;  // '7'
                        2: char_code <= 8'd93;  // ']'
                        3: char_code <= 8'd69;  // 'E'
                        4: char_code <= 8'd120; // 'x'
                        5: char_code <= 8'd105; // 'i'
                        6: char_code <= 8'd116; // 't'
                        default: char_code <= 8'd32;
                    endcase
                    char_col <= auto_test_char_col;
                    in_char_area <= 1'b1;
                end
            end
        end
        
        // 参数调整界面（param_adjust_mode != IDLE�?
        else begin
            char_row <= auto_test_char_row;
            
            // �?行：显示当前调整参数名称
            if (pixel_y_d1 < (AUTO_TEST_Y_START + 2*AUTO_LINE_HEIGHT)) begin
                if (pixel_x_d1 >= AUTO_TEST_X_START && pixel_x_d1 < AUTO_TEST_X_START + 20*AUTO_CHAR_WIDTH) begin
                    case (param_adjust_mode)
                        ADJUST_FREQ: begin
                            case ((pixel_x_d1 - AUTO_TEST_X_START) / AUTO_CHAR_WIDTH)
                                0: char_code <= 8'd70;  // 'F'
                                1: char_code <= 8'd114; // 'r'
                                2: char_code <= 8'd101; // 'e'
                                3: char_code <= 8'd113; // 'q'
                                4: char_code <= 8'd32;  // ' '
                                5: char_code <= 8'd65;  // 'A'
                                6: char_code <= 8'd100; // 'd'
                                7: char_code <= 8'd106; // 'j'
                                8: char_code <= 8'd117; // 'u'
                                9: char_code <= 8'd115; // 's'
                                10: char_code <= 8'd116; // 't'
                                default: char_code <= 8'd32;
                            endcase
                        end
                        ADJUST_AMP: begin
                            case ((pixel_x_d1 - AUTO_TEST_X_START) / AUTO_CHAR_WIDTH)
                                0: char_code <= 8'd65;  // 'A'
                                1: char_code <= 8'd109; // 'm'
                                2: char_code <= 8'd112; // 'p'
                                3: char_code <= 8'd32;  // ' '
                                4: char_code <= 8'd65;  // 'A'
                                5: char_code <= 8'd100; // 'd'
                                6: char_code <= 8'd106; // 'j'
                                7: char_code <= 8'd117; // 'u'
                                8: char_code <= 8'd115; // 's'
                                9: char_code <= 8'd116; // 't'
                                default: char_code <= 8'd32;
                            endcase
                        end
                        ADJUST_DUTY: begin
                            case ((pixel_x_d1 - AUTO_TEST_X_START) / AUTO_CHAR_WIDTH)
                                0: char_code <= 8'd68;  // 'D'
                                1: char_code <= 8'd117; // 'u'
                                2: char_code <= 8'd116; // 't'
                                3: char_code <= 8'd121; // 'y'
                                4: char_code <= 8'd32;  // ' '
                                5: char_code <= 8'd65;  // 'A'
                                6: char_code <= 8'd100; // 'd'
                                7: char_code <= 8'd106; // 'j'
                                8: char_code <= 8'd117; // 'u'
                                9: char_code <= 8'd115; // 's'
                                10: char_code <= 8'd116; // 't'
                                default: char_code <= 8'd32;
                            endcase
                        end
                        ADJUST_THD: begin
                            case ((pixel_x_d1 - AUTO_TEST_X_START) / AUTO_CHAR_WIDTH)
                                0: char_code <= 8'd84;  // 'T'
                                1: char_code <= 8'd72;  // 'H'
                                2: char_code <= 8'd68;  // 'D'
                                3: char_code <= 8'd32;  // ' '
                                4: char_code <= 8'd65;  // 'A'
                                5: char_code <= 8'd100; // 'd'
                                6: char_code <= 8'd106; // 'j'
                                7: char_code <= 8'd117; // 'u'
                                8: char_code <= 8'd115; // 's'
                                9: char_code <= 8'd116; // 't'
                                default: char_code <= 8'd32;
                            endcase
                        end
                        default: char_code <= 8'd32;
                    endcase
                    char_col <= auto_test_char_col;
                    in_char_area <= 1'b1;
                end
            end
            
            // �?行："Min: XXXX"
            else if (pixel_y_d1 < (AUTO_TEST_Y_START + 3*AUTO_LINE_HEIGHT)) begin
                if (pixel_x_d1 >= AUTO_TEST_X_START && pixel_x_d1 < AUTO_TEST_X_START + 16*AUTO_CHAR_WIDTH) begin
                    case ((pixel_x_d1 - AUTO_TEST_X_START) / AUTO_CHAR_WIDTH)
                        0: char_code <= 8'd77;  // 'M'
                        1: char_code <= 8'd105; // 'i'
                        2: char_code <= 8'd110; // 'n'
                        3: char_code <= 8'd58;  // ':'
                        4: char_code <= 8'd32;  // ' '
                        // 根据模式显示不同的数�?
                        5: begin
                            case (param_adjust_mode)
                                ADJUST_FREQ: char_code <= 8'd48 + freq_min_d5;
                                ADJUST_AMP:  char_code <= 8'd48 + amp_min_d3;
                                ADJUST_DUTY: char_code <= 8'd48 + duty_min_d2;
                                default:     char_code <= 8'd32;
                            endcase
                        end
                        6: begin
                            case (param_adjust_mode)
                                ADJUST_FREQ: char_code <= 8'd48 + freq_min_d4;
                                ADJUST_AMP:  char_code <= 8'd48 + amp_min_d2;
                                ADJUST_DUTY: char_code <= 8'd48 + duty_min_d1;
                                default:     char_code <= 8'd32;
                            endcase
                        end
                        7: begin
                            case (param_adjust_mode)
                                ADJUST_FREQ: char_code <= 8'd48 + freq_min_d3;
                                ADJUST_AMP:  char_code <= 8'd48 + amp_min_d1;
                                ADJUST_DUTY: char_code <= 8'd46;  // '.'
                                default:     char_code <= 8'd32;
                            endcase
                        end
                        8: begin
                            case (param_adjust_mode)
                                ADJUST_FREQ: char_code <= 8'd48 + freq_min_d2;
                                ADJUST_AMP:  char_code <= 8'd48 + amp_min_d0;
                                ADJUST_DUTY: char_code <= 8'd48 + duty_min_d0;
                                default:     char_code <= 8'd32;
                            endcase
                        end
                        9: begin
                            case (param_adjust_mode)
                                ADJUST_FREQ: char_code <= 8'd48 + freq_min_d1;
                                ADJUST_AMP:  char_code <= 8'd32;
                                ADJUST_DUTY: char_code <= 8'd37;  // '%'
                                default:     char_code <= 8'd32;
                            endcase
                        end
                        10: begin
                            case (param_adjust_mode)
                                ADJUST_FREQ: char_code <= 8'd48 + freq_min_d0;
                                default:     char_code <= 8'd32;
                            endcase
                        end
                        default: char_code <= 8'd32;
                    endcase
                    char_col <= auto_test_char_col;
                    in_char_area <= 1'b1;
                end
            end
            
            // �?行："Max: XXXX"（THD模式不显示Min，只显示Max�?
            else if (pixel_y_d1 < (AUTO_TEST_Y_START + 4*AUTO_LINE_HEIGHT)) begin
                if (pixel_x_d1 >= AUTO_TEST_X_START && pixel_x_d1 < AUTO_TEST_X_START + 16*AUTO_CHAR_WIDTH) begin
                    case ((pixel_x_d1 - AUTO_TEST_X_START) / AUTO_CHAR_WIDTH)
                        0: char_code <= 8'd77;  // 'M'
                        1: char_code <= 8'd97;  // 'a'
                        2: char_code <= 8'd120; // 'x'
                        3: char_code <= 8'd58;  // ':'
                        4: char_code <= 8'd32;  // ' '
                        5: begin
                            case (param_adjust_mode)
                                ADJUST_FREQ: char_code <= 8'd48 + freq_max_d5;
                                ADJUST_AMP:  char_code <= 8'd48 + amp_max_d3;
                                ADJUST_DUTY: char_code <= 8'd48 + duty_max_d2;
                                ADJUST_THD:  char_code <= 8'd48 + thd_max_d2;
                                default:     char_code <= 8'd32;
                            endcase
                        end
                        6: begin
                            case (param_adjust_mode)
                                ADJUST_FREQ: char_code <= 8'd48 + freq_max_d4;
                                ADJUST_AMP:  char_code <= 8'd48 + amp_max_d2;
                                ADJUST_DUTY: char_code <= 8'd48 + duty_max_d1;
                                ADJUST_THD:  char_code <= 8'd48 + thd_max_d1;
                                default:     char_code <= 8'd32;
                            endcase
                        end
                        7: begin
                            case (param_adjust_mode)
                                ADJUST_FREQ: char_code <= 8'd48 + freq_max_d3;
                                ADJUST_AMP:  char_code <= 8'd48 + amp_max_d1;
                                ADJUST_DUTY: char_code <= 8'd46;  // '.'
                                ADJUST_THD:  char_code <= 8'd46;  // '.'
                                default:     char_code <= 8'd32;
                            endcase
                        end
                        8: begin
                            case (param_adjust_mode)
                                ADJUST_FREQ: char_code <= 8'd48 + freq_max_d2;
                                ADJUST_AMP:  char_code <= 8'd48 + amp_max_d0;
                                ADJUST_DUTY: char_code <= 8'd48 + duty_max_d0;
                                ADJUST_THD:  char_code <= 8'd48 + thd_max_d0;
                                default:     char_code <= 8'd32;
                            endcase
                        end
                        9: begin
                            case (param_adjust_mode)
                                ADJUST_FREQ: char_code <= 8'd48 + freq_max_d1;
                                ADJUST_AMP:  char_code <= 8'd32;
                                ADJUST_DUTY: char_code <= 8'd37;  // '%'
                                ADJUST_THD:  char_code <= 8'd37;  // '%'
                                default:     char_code <= 8'd32;
                            endcase
                        end
                        10: begin
                            case (param_adjust_mode)
                                ADJUST_FREQ: char_code <= 8'd48 + freq_max_d0;
                                default:     char_code <= 8'd32;
                            endcase
                        end
                        default: char_code <= 8'd32;
                    endcase
                    char_col <= auto_test_char_col;
                    in_char_area <= 1'b1;
                end
            end
            
            // �?行：显示步进模式
            else if (pixel_y_d1 < (AUTO_TEST_Y_START + 5*AUTO_LINE_HEIGHT)) begin
                if (pixel_x_d1 >= AUTO_TEST_X_START && pixel_x_d1 < AUTO_TEST_X_START + 16*AUTO_CHAR_WIDTH) begin
                    case ((pixel_x_d1 - AUTO_TEST_X_START) / AUTO_CHAR_WIDTH)
                        0: char_code <= 8'd83;  // 'S'
                        1: char_code <= 8'd116; // 't'
                        2: char_code <= 8'd101; // 'e'
                        3: char_code <= 8'd112; // 'p'
                        4: char_code <= 8'd58;  // ':'
                        5: char_code <= 8'd32;  // ' '
                        6: begin
                            case (adjust_step_mode)
                                2'd0: char_code <= 8'd70;  // 'F' (Fine)
                                2'd1: char_code <= 8'd77;  // 'M' (Mid)
                                2'd2: char_code <= 8'd67;  // 'C' (Coarse)
                                default: char_code <= 8'd32;
                            endcase
                        end
                        7: begin
                            case (adjust_step_mode)
                                2'd0: char_code <= 8'd105; // 'i'
                                2'd1: char_code <= 8'd105; // 'i'
                                2'd2: char_code <= 8'd111; // 'o'
                                default: char_code <= 8'd32;
                            endcase
                        end
                        8: begin
                            case (adjust_step_mode)
                                2'd0: char_code <= 8'd110; // 'n'
                                2'd1: char_code <= 8'd100; // 'd'
                                2'd2: char_code <= 8'd97;  // 'a'
                                default: char_code <= 8'd32;
                            endcase
                        end
                        9: begin
                            case (adjust_step_mode)
                                2'd0: char_code <= 8'd101; // 'e'
                                2'd2: char_code <= 8'd114; // 'r'
                                default: char_code <= 8'd32;
                            endcase
                        end
                        10: begin
                            case (adjust_step_mode)
                                2'd2: char_code <= 8'd115; // 's'
                                default: char_code <= 8'd32;
                            endcase
                        end
                        11: begin
                            case (adjust_step_mode)
                                2'd2: char_code <= 8'd101; // 'e'
                                default: char_code <= 8'd32;
                            endcase
                        end
                        default: char_code <= 8'd32;
                    endcase
                    char_col <= auto_test_char_col;
                    in_char_area <= 1'b1;
                end
            end
            
            // �?行："[7]Back"
            else if (pixel_y_d1 < (AUTO_TEST_Y_START + 6*AUTO_LINE_HEIGHT)) begin
                if (pixel_x_d1 >= AUTO_TEST_X_START && pixel_x_d1 < AUTO_TEST_X_START + 8*AUTO_CHAR_WIDTH) begin
                    case ((pixel_x_d1 - AUTO_TEST_X_START) / AUTO_CHAR_WIDTH)
                        0: char_code <= 8'd91;  // '['
                        1: char_code <= 8'd55;  // '7'
                        2: char_code <= 8'd93;  // ']'
                        3: char_code <= 8'd66;  // 'B'
                        4: char_code <= 8'd97;  // 'a'
                        5: char_code <= 8'd99;  // 'c'
                        6: char_code <= 8'd107; // 'k'
                        default: char_code <= 8'd32;
                    endcase
                    char_col <= auto_test_char_col;
                    in_char_area <= 1'b1;
                end
            end
        end
    end  // 结束自动测试显示区域
    
    end  // �?结束 else begin (char_code时序逻辑�?
end  // 结束 always @(posedge clk_pixel)

//=============================================================================
// RGB数据生成（美化版 - 使用延迟后的坐标�?
//=============================================================================
always @(*) begin
    rgb_data = 24'h000000;  // 默认黑色背景
    spectrum_height_calc = 12'd0;
    char_color = 24'hFFFFFF;  // 默认白色文字
    
    // �?坐标轴刻度线检测（在频�?波形区域内）
    y_axis_tick = 1'b0;
    x_axis_tick = 1'b0;
    in_axis_label = 1'b0;
    
    if (pixel_y_d3 >= SPECTRUM_Y_START && pixel_y_d3 < SPECTRUM_Y_END) begin
        // �?Y轴刻度线检测（简化版�?个关键刻度点�?
        // 位置：Y=50 (100%), Y=175 (75%), Y=300 (50%), Y=425 (25%), Y=530 (0%) - 720p
        if (pixel_x_d3 >= AXIS_LEFT_MARGIN - TICK_LENGTH && pixel_x_d3 < AXIS_LEFT_MARGIN) begin
            if (pixel_y_d3 == 50 || pixel_y_d3 == 175 || pixel_y_d3 == 300 || 
                pixel_y_d3 == 425 || pixel_y_d3 == 532) begin
                y_axis_tick = 1'b1;
            end
        end
        
        // �?X轴刻度线检测（简化版�?个关键刻度点�?
        // 位置：X=80, 444, 808, 1172, 1536, 1840
        if (pixel_y_d3 >= SPECTRUM_Y_END - TICK_LENGTH && pixel_y_d3 < SPECTRUM_Y_END) begin
            if (pixel_x_d3 == 80 || pixel_x_d3 == 444 || pixel_x_d3 == 808 || 
                pixel_x_d3 == 1172 || pixel_x_d3 == 1536 || pixel_x_d3 == 1840) begin
                x_axis_tick = 1'b1;
            end
        end
        
        // Y轴标签区域（左侧边距内）
        if (pixel_x_d3 < AXIS_LEFT_MARGIN - TICK_LENGTH - 4) begin
            in_axis_label = 1'b1;
        end
    end
    ch1_spec_hit = 1'b0;
    ch2_spec_hit = 1'b0;
    
    if (video_active_d3) begin
        // ========== 顶部标题�?==========
        if (pixel_y_d3 < 50) begin
            if (pixel_x_d3 < 5 || pixel_x_d3 >= H_ACTIVE - 5 ||
                pixel_y_d3 < 2 || pixel_y_d3 >= 48) begin
                rgb_data = 24'h4080FF;  // 蓝色边框
            end else begin
                rgb_data = 24'h1A1A2E;  // 深蓝灰背�?
            end
            
            // �?显示通道指示（独立开关状态，类似示波器）
            if (pixel_y_d3 >= 15 && pixel_y_d3 < 35) begin
                // CH1指示器：开�?亮绿色，关闭=暗灰�?
                if (pixel_x_d3 >= 20 && pixel_x_d3 < 120) begin
                    rgb_data = ch1_enable ? 24'h00FF00 : 24'h404040;
                end 
                // CH2指示器：开�?亮红色，关闭=暗灰�?
                else if (pixel_x_d3 >= 140 && pixel_x_d3 < 240) begin
                    rgb_data = ch2_enable ? 24'hFF0000 : 24'h404040;
                end
                // �?调试：显示当前数据值（渐变色条�?
                else if (pixel_x_d3 >= 300 && pixel_x_d3 < 500) begin
                    if (work_mode_d3 == 2'd0) begin
                        // 时域模式：显示time_data_q的�?
                        rgb_data = {time_data_q[15:8], 8'h00, 8'hFF - time_data_q[15:8]};
                    end else begin
                        // 频域模式：显示spectrum_data_q的�?
                        rgb_data = {spectrum_data_q[15:8], spectrum_data_q[15:8], 8'h00};
                    end
                end
            end
        end
        
        // ========== 频谱/时域显示区域 ==========
        else if (pixel_y_d3 >= SPECTRUM_Y_START && pixel_y_d3 < SPECTRUM_Y_END) begin
            
            // �?坐标轴绘制优先级最�?
            // Y轴（左侧边界线）
            if (pixel_x_d3 == AXIS_LEFT_MARGIN || pixel_x_d3 == AXIS_LEFT_MARGIN - 1) begin
                rgb_data = 24'hFFFFFF;  // 白色Y�?
            end
            // Y轴刻度线
            else if (y_axis_tick) begin
                rgb_data = 24'hCCCCCC;  // 浅灰色刻度线
            end
            // X轴刻度线
            else if (x_axis_tick) begin
                rgb_data = 24'hCCCCCC;  // 浅灰色刻度线
            end
            // Y轴标签区域（深色背景�?
            else if (in_axis_label) begin
                rgb_data = 24'h1A1A2E;  // 深色背景
                // Y轴标度数字显�?
                if (in_char_area_d1 && char_pixel_row[15 - char_col_d1[3:0]]) begin
                    rgb_data = 24'hFFFFFF;  // 白色数字
                end
            end
            
            // ========== 工作模式0：时域波形显�?==========
            else if (work_mode_d4 == 2'd0) begin
                // 网格线（使用d4信号�?
                if (grid_x_flag_d4 || grid_y_flag_d4) begin
                    rgb_data = 24'h303030;  // 深灰网格
                end
                // 中心参考线�?V参考）
                else if (pixel_y_d4 == WAVEFORM_CENTER_Y || 
                         pixel_y_d4 == WAVEFORM_CENTER_Y + 1) begin
                    rgb_data = 24'h606060;  // 灰色中心�?
                end
                else begin
                    // �?方案3优化：简化RGB选择逻辑（使用Stage 4计算的ch1_hit/ch2_hit�?
                    // 使用case语句替代多层if-else，减少多路选择器层�?
                    case ({ch1_hit & ch1_enable_d4, ch2_hit & ch2_enable_d4})
                        2'b11: rgb_data = 24'hFFFF00;  // 黄色（两通道重叠�?
                        2'b10: rgb_data = 24'h00FF00;  // 绿色（仅CH1�?
                        2'b01: rgb_data = 24'hFF0000;  // 红色（仅CH2�?
                        default: rgb_data = {8'd16, 8'd16, (8'd20 + {5'd0, pixel_y_d4[8:6]})};  // 背景渐变
                    endcase
                end
            end
            
            // ========== 工作模式1：频域频谱显�?==========
            else begin
                // 兼容旧变量（用于调试显示等）
                spectrum_height_calc = ch1_enable ? ch1_spectrum_calc_d1 : ch2_spectrum_calc_d1;
                
                // 网格线（使用d4信号�?
                if (grid_x_flag_d4 || grid_y_flag_d4) begin
                    rgb_data = 24'h303030;
                end
                else begin
                    // �?流水线优化：频谱命中检测也在Stage 4完成
                    // 使用Stage 3计算的频谱高度（ch1_spectrum_calc_d1, ch2_spectrum_calc_d1�?
                    
                    // 【修复】移�?10偏移，避免频谱柱向下延伸造成X轴上方出现粉色横�?
                    ch1_spec_hit = ch1_enable_d4 && (pixel_y_d4 >= (SPECTRUM_Y_END - ch1_spectrum_calc_d1));
                    ch2_spec_hit = ch2_enable_d4 && (pixel_y_d4 >= (SPECTRUM_Y_END - ch2_spectrum_calc_d1));
                    
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
            end  // 结束 work_mode_d4 else �?
        end
        
        // ========== 中间分隔�?+ AI识别显示区域 ==========
        else if (pixel_y_d3 >= SPECTRUM_Y_END && pixel_y_d3 < PARAM_Y_START) begin
            // 分隔�?
            if (pixel_y_d3 == SPECTRUM_Y_END || pixel_y_d3 == PARAM_Y_START - 1) begin
                rgb_data = 24'h4080FF;  // 蓝色分隔�?
            end
            // �?X轴标度数字显示区域（底部32像素�?
            else if (pixel_y_d4 >= SPECTRUM_Y_END && pixel_y_d4 < SPECTRUM_Y_END + 32) begin
                rgb_data = 24'h1A1A2E;  // 深色背景
                // X轴标度数字显�?
                if (in_char_area_d1 && char_pixel_row[15 - char_col_d1[3:0]]) begin
                    rgb_data = 24'hFFFFFF;  // 白色数字
                end
            end
            // AI识别显示区域 (Y: 830-862)
            else if (pixel_y_d4 >= 830 && pixel_y_d4 < 862) begin
                rgb_data = 24'h0F0F23;  // 深色背景
                // AI识别文字显示
                if (in_char_area_d1 && char_pixel_row[15 - char_col_d1[3:0]]) begin
                    rgb_data = 24'hFFFFFF;  // 白色 - AI识别结果
                end
            end
            else begin
                rgb_data = 24'h0F0F23;  // 深色背景
            end
        end
        
        // ========== 参数显示区域 ==========
        // �?时序优化：由于char_code增加了一级延迟，这里使用d4坐标
        else if (pixel_y_d4 >= PARAM_Y_START && pixel_y_d4 < PARAM_Y_END) begin
            // 背景渐变
            rgb_data = {8'd15, 8'd15, 8'd30};  // 深蓝色背�?
            
            // 字符显示（使用延迟后的ROM数据和in_char_area信号�?
            // �?时序优化：使用延�?拍的in_char_area_d1和char_col_d1
            if (in_char_area_d1 && char_pixel_row[15 - char_col_d1[3:0]]) begin
                // 根据参数行位置设置不同颜色（紧凑布局�?px间距�?
                if (pixel_y_d4 < TABLE_Y_CH1)
                    char_color = 24'hFFFFFF;
                else if (pixel_y_d4 < TABLE_Y_CH2)
                    char_color = 24'h00FF00;
                else if (pixel_y_d4 < TABLE_Y_PHASE)
                    char_color = 24'hFF0000;
                else
                    char_color = 24'hFF00FF;
                rgb_data = char_color;
            end
        end
        
        // ========== �?自动测试显示区域（右下角浮窗�?==========
        if (auto_test_enable && 
            pixel_y_d4 >= AUTO_TEST_Y_START && 
            pixel_y_d4 < (AUTO_TEST_Y_START + AUTO_TEST_HEIGHT) &&
            pixel_x_d4 >= AUTO_TEST_X_START && 
            pixel_x_d4 < (AUTO_TEST_X_START + AUTO_TEST_WIDTH)) begin
            
            // 边框绘制�?像素宽）
            if (pixel_y_d4 < (AUTO_TEST_Y_START + 2) ||                              // 上边�?
                pixel_y_d4 >= (AUTO_TEST_Y_START + AUTO_TEST_HEIGHT - 2) ||          // 下边�?
                pixel_x_d4 < (AUTO_TEST_X_START + 2) ||                              // 左边�?
                pixel_x_d4 >= (AUTO_TEST_X_START + AUTO_TEST_WIDTH - 2)) begin
                rgb_data = 24'h00FFFF;  // 青色边框
            end
            // 内部区域
            else begin
                // 半透明背景（深蓝色�?
                rgb_data = 24'h0A0A20;  // 深色背景
                
                // 字符显示
                if (in_char_area_d1 && char_pixel_row[15 - char_col_d1[3:0]]) begin
                    // 标题行使用黄�?
                    if (pixel_y_d4 < (AUTO_TEST_Y_START + AUTO_LINE_HEIGHT)) begin
                        rgb_data = 24'hFFFF00;  // 黄色标题
                    end
                    // 其他行使用白�?
                    else begin
                        rgb_data = 24'hFFFFFF;  // 白色文字
                    end
                end
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
        // 修复右边缘显示问题：避免与网格线重叠
        if (pixel_x_d3 < 2) begin
            rgb_data = 24'h4080FF;  // 蓝色左侧�?
        end 
        else if (pixel_x_d3 >= H_ACTIVE - 2) begin
            rgb_data = 24'h4080FF;  // 蓝色右侧�?
        end
    end
end

//=============================================================================
// 输出寄存�?
//=============================================================================
always @(posedge clk_pixel or negedge rst_n) begin
    if (!rst_n) begin
        rgb_out_reg <= 24'h000000;
        de_out_reg  <= 1'b0;
        hs_out_reg  <= 1'b0;  // 修改：复位时也为0，与内部信号一�?
        vs_out_reg  <= 1'b0;  // 修改：复位时也为0，与内部信号一�?
    end else begin
        rgb_out_reg <= rgb_data;
        de_out_reg  <= video_active_d4;  // �?时序优化：改为d4以匹配字符显示延�?
        hs_out_reg  <= hs_internal;
        vs_out_reg  <= vs_internal;
    end
end

assign rgb_out = rgb_out_reg;
assign de_out  = de_out_reg;
assign hs_out  = hs_out_reg;
assign vs_out  = vs_out_reg;

endmodule