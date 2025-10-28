//=============================================================================
// 文件�? hdmi_display_ctrl.v (美化增强�?- 带参数显�?+ 双通道独立控制)
// 描述: 1080p HDMI显示控制�?
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
    
    // CH1参数输入
    input  wire [15:0]  ch1_freq,           // CH1频率 (Hz)
    input  wire [15:0]  ch1_amplitude,      // CH1幅度
    input  wire [15:0]  ch1_duty,           // CH1占空�?(0-1000 = 0-100%)
    input  wire [15:0]  ch1_thd,            // CH1 THD (0-1000 = 0-100%)
    
    // CH2参数输入
    input  wire [15:0]  ch2_freq,           // CH2频率 (Hz)
    input  wire [15:0]  ch2_amplitude,      // CH2幅度
    input  wire [15:0]  ch2_duty,           // CH2占空�?(0-1000 = 0-100%)
    input  wire [15:0]  ch2_thd,            // CH2 THD (0-1000 = 0-100%)
    
    // 双通道相位�?
    input  wire [15:0]  phase_diff,         // 相位�?(0-3599 = 0-359.9°)
    
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
localparam PARAM_Y_END      = 1080;     // 参数区域结束Y（使用全部屏幕空间）

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
reg [11:0] pixel_x_d1, pixel_x_d2, pixel_x_d3;
reg [11:0] pixel_y_d1, pixel_y_d2, pixel_y_d3;
reg        video_active_d1, video_active_d2, video_active_d3;
reg [1:0]  work_mode_d1, work_mode_d2, work_mode_d3;

// 网格线标志（预计算，避免取模运算�?
reg        grid_x_flag, grid_y_flag;

// �?双通道波形相关信号
reg [15:0] ch1_data_q, ch2_data_q;  // 双通道数据寄存�?
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
reg [1:0]  work_mode_d4;
reg [11:0] pixel_x_d4, pixel_y_d4;

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

reg [23:0] rgb_out_reg;
reg        de_out_reg;
reg        hs_out_reg;
reg        vs_out_reg;

reg [23:0] rgb_data;
reg [11:0] spectrum_height_calc;

// 字符显示相关 - 简化版本去除流水线
wire [15:0] char_pixel_row;
reg [7:0]   char_code;    // 字符ASCII�?
reg [4:0]   char_row;     // 字符行号 (0-31)
reg [11:0]  char_col;     // 字符列号
reg         in_char_area;
reg [23:0]  char_color;

// 数字分解
reg [3:0]   digit_0, digit_1, digit_2, digit_3, digit_4;

// 预计算的数字（每帧更新一次，避免实时除法�?
// CH1参数数字
reg [3:0]   ch1_freq_d0, ch1_freq_d1, ch1_freq_d2, ch1_freq_d3, ch1_freq_d4;
reg [3:0]   ch1_amp_d0, ch1_amp_d1, ch1_amp_d2, ch1_amp_d3;
reg [3:0]   ch1_duty_d0, ch1_duty_d1, ch1_duty_d2;
reg [3:0]   ch1_thd_d0, ch1_thd_d1, ch1_thd_d2;

// CH2参数数字
reg [3:0]   ch2_freq_d0, ch2_freq_d1, ch2_freq_d2, ch2_freq_d3, ch2_freq_d4;
reg [3:0]   ch2_amp_d0, ch2_amp_d1, ch2_amp_d2, ch2_amp_d3;
reg [3:0]   ch2_duty_d0, ch2_duty_d1, ch2_duty_d2;
reg [3:0]   ch2_thd_d0, ch2_thd_d1, ch2_thd_d2;

// 相位差数�?
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
// 频谱地址生成（提前生成，时序优化�?
// 8192点FFT压缩�?920像素显示：每像素对应�?.27个频谱点
// 
// 时序问题：除法器 (h_cnt * 8192) / 1920 产生10层组合逻辑，违�?1.845ns
// 
// 优化方案：分离乘法和加法，降低组合逻辑复杂�?
//   方法1: h_cnt * 4.25 = (h_cnt << 2) + (h_cnt >> 2)
//          优点�?层逻辑（移�?加法），时序良好
//          缺点：末端累积误�?2点（0.39%），视觉影响极小
//   
//   方法2: (h_cnt * 8192) / 1920（精确）
//          优点：完美精�?
//          缺点�?0层逻辑，严重时序违�?
//
// 采用方案1：牺�?.39%精度换取时序裕度
//=============================================================================

// 组合逻辑计算（移�?加法�?层逻辑�?
wire [12:0] spectrum_addr_calc;
assign spectrum_addr_calc = {h_cnt, 2'b00} + {2'b00, h_cnt[11:2]};  // h<<2 + h>>2

// 单级寄存器（保持1拍延迟，与原设计一致）
always @(posedge clk_pixel or negedge rst_n) begin
    if (!rst_n)
        spectrum_addr <= 13'd0;
    else begin
        if (h_cnt < H_ACTIVE) begin
            // 限制在有效范�?[0, 8191]
            if (spectrum_addr_calc > 13'd8191)
                spectrum_addr <= 13'd8191;
            else
                spectrum_addr <= spectrum_addr_calc;
        end else
            spectrum_addr <= 13'd8191;
    end
end

//=============================================================================
// 参数数字预计算（每帧更新，避免实时除法造成时序违例�?
//=============================================================================
always @(posedge clk_pixel or negedge rst_n) begin
    if (!rst_n) begin
        // CH1参数
        ch1_freq_d0 <= 4'd0; ch1_freq_d1 <= 4'd0; ch1_freq_d2 <= 4'd0; ch1_freq_d3 <= 4'd0; ch1_freq_d4 <= 4'd0;
        ch1_amp_d0 <= 4'd0; ch1_amp_d1 <= 4'd0; ch1_amp_d2 <= 4'd0; ch1_amp_d3 <= 4'd0;
        ch1_duty_d0 <= 4'd0; ch1_duty_d1 <= 4'd0; ch1_duty_d2 <= 4'd0;
        ch1_thd_d0 <= 4'd0; ch1_thd_d1 <= 4'd0; ch1_thd_d2 <= 4'd0;
        // CH2参数
        ch2_freq_d0 <= 4'd0; ch2_freq_d1 <= 4'd0; ch2_freq_d2 <= 4'd0; ch2_freq_d3 <= 4'd0; ch2_freq_d4 <= 4'd0;
        ch2_amp_d0 <= 4'd0; ch2_amp_d1 <= 4'd0; ch2_amp_d2 <= 4'd0; ch2_amp_d3 <= 4'd0;
        ch2_duty_d0 <= 4'd0; ch2_duty_d1 <= 4'd0; ch2_duty_d2 <= 4'd0;
        ch2_thd_d0 <= 4'd0; ch2_thd_d1 <= 4'd0; ch2_thd_d2 <= 4'd0;
        // 相位�?
        phase_d0 <= 4'd0; phase_d1 <= 4'd0; phase_d2 <= 4'd0; phase_d3 <= 4'd0;
    end else begin
        // 在场消隐期间更新（v_cnt == 0, h_cnt == 0），有充足时间计�?
        if (v_cnt == 12'd0 && h_cnt == 12'd0) begin
            // CH1频率�?位数字）
            ch1_freq_d0 <= ch1_freq % 10;
            ch1_freq_d1 <= (ch1_freq / 10) % 10;
            ch1_freq_d2 <= (ch1_freq / 100) % 10;
            ch1_freq_d3 <= (ch1_freq / 1000) % 10;
            ch1_freq_d4 <= (ch1_freq / 10000) % 10;
            
            // CH1幅度�?位数字）
            ch1_amp_d0 <= ch1_amplitude % 10;
            ch1_amp_d1 <= (ch1_amplitude / 10) % 10;
            ch1_amp_d2 <= (ch1_amplitude / 100) % 10;
            ch1_amp_d3 <= (ch1_amplitude / 1000) % 10;
            
            // CH1占空比（3位数字，0-100.0�?
            ch1_duty_d0 <= ch1_duty % 10;
            ch1_duty_d1 <= (ch1_duty / 10) % 10;
            ch1_duty_d2 <= (ch1_duty / 100) % 10;
            
            // CH1 THD�?位数字，0-100.0�?
            ch1_thd_d0 <= ch1_thd % 10;
            ch1_thd_d1 <= (ch1_thd / 10) % 10;
            ch1_thd_d2 <= (ch1_thd / 100) % 10;
            
            // CH2频率�?位数字）
            ch2_freq_d0 <= ch2_freq % 10;
            ch2_freq_d1 <= (ch2_freq / 10) % 10;
            ch2_freq_d2 <= (ch2_freq / 100) % 10;
            ch2_freq_d3 <= (ch2_freq / 1000) % 10;
            ch2_freq_d4 <= (ch2_freq / 10000) % 10;
            
            // CH2幅度�?位数字）
            ch2_amp_d0 <= ch2_amplitude % 10;
            ch2_amp_d1 <= (ch2_amplitude / 10) % 10;
            ch2_amp_d2 <= (ch2_amplitude / 100) % 10;
            ch2_amp_d3 <= (ch2_amplitude / 1000) % 10;
            
            // CH2占空比（3位数字，0-100.0�?
            ch2_duty_d0 <= ch2_duty % 10;
            ch2_duty_d1 <= (ch2_duty / 10) % 10;
            ch2_duty_d2 <= (ch2_duty / 100) % 10;
            
            // CH2 THD�?位数字，0-100.0�?
            ch2_thd_d0 <= ch2_thd % 10;
            ch2_thd_d1 <= (ch2_thd / 10) % 10;
            ch2_thd_d2 <= (ch2_thd / 100) % 10;
            
            // 相位差（4位数字，0-359.9�?
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
        // 延迟3拍（匹配字符ROM�?
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
        
        // �?流水线优化：Stage 4延迟
        grid_x_flag_d4 <= grid_x_flag_d3;
        grid_y_flag_d4 <= grid_y_flag_d3;
        work_mode_d4 <= work_mode_d3;
        pixel_x_d4 <= pixel_x_d3;
        pixel_y_d4 <= pixel_y_d3;
        ch1_enable_d4 <= ch1_enable;
        ch2_enable_d4 <= ch2_enable;
        
        // �?双通道数据采样�?级流水线匹配显示延迟�?
        ch1_data_q <= ch1_data;
        ch2_data_q <= ch2_data;
        
        // �?流水线优化：Stage 3 - 仅计算波�?频谱高度
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
// 时域采样点X坐标映射�?920像素 -> 8192采样�?
// spectrum_addr范围0-8191，映射到0-1919
// 计算公式：x = (spectrum_addr * 1920) / 8192 �?spectrum_addr / 4.27
// 简化：x �?spectrum_addr >> 2（取�?个点�?
assign time_sample_x = {1'b0, spectrum_addr[12:2]};  // 除以4，得�?-2047范围

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
//=============================================================================
ascii_rom_16x32_full u_char_rom (
    .clk        (clk_pixel),
    .char_code  (char_code),      // 直接使用ASCII�?(8�?
    .char_row   (char_row[4:0]),  // 字符行号 (0-31)
    .char_data  (char_pixel_row)  // 16位字符行数据
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
// 参数显示字符生成（流水线第一�?字符选择,打断14ns长路径）
// ⚠️ 时序优化：使用二级流水线, pixel_x_d1 �?char_code_stage1 �?char_code
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
    
    // 判断是否在参数显示区�?
    if (pixel_y_d1 >= PARAM_Y_START && pixel_y_d1 < PARAM_Y_END) begin
        
        // �?�? 频率 - 左右分栏 "CH1 Freq:05000Hz | CH2 Freq:05000Hz" (Y: 870-902)
        if (pixel_y_d1 >= PARAM_Y_START && pixel_y_d1 < PARAM_Y_START + 32) begin
            char_row <= pixel_y_d1 - PARAM_Y_START;
            
            // ===== CH1频率 (左侧 X: 40-440) =====
            // "CH1 "
            if (pixel_x_d1 >= 40 && pixel_x_d1 < 56) begin
                char_code <= 8'd67;  // 'C'
                char_col <= pixel_x_d1 - 12'd40;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 56 && pixel_x_d1 < 72) begin
                char_code <= 8'd72;  // 'H'
                char_col <= pixel_x_d1 - 12'd56;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 72 && pixel_x_d1 < 88) begin
                char_code <= 8'd49;  // '1'
                char_col <= pixel_x_d1 - 12'd72;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 88 && pixel_x_d1 < 104) begin
                char_code <= 8'd32;  // ' '
                char_col <= pixel_x_d1 - 12'd88;
                in_char_area <= 1'b1;
            end
            // "Freq:"
            else if (pixel_x_d1 >= 104 && pixel_x_d1 < 120) begin
                char_code <= 8'd70;  // 'F'
                char_col <= pixel_x_d1 - 12'd104;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 120 && pixel_x_d1 < 136) begin
                char_code <= 8'd114; // 'r'
                char_col <= pixel_x_d1 - 12'd120;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 136 && pixel_x_d1 < 152) begin
                char_code <= 8'd101; // 'e'
                char_col <= pixel_x_d1 - 12'd136;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 152 && pixel_x_d1 < 168) begin
                char_code <= 8'd113; // 'q'
                char_col <= pixel_x_d1 - 12'd152;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 168 && pixel_x_d1 < 184) begin
                char_code <= 8'd58;  // ':'
                char_col <= pixel_x_d1 - 12'd168;
                in_char_area <= 1'b1;
            end
            // CH1频率数�?(5位数)
            else if (pixel_x_d1 >= 184 && pixel_x_d1 < 200) begin
                char_code <= digit_to_ascii(ch1_freq_d4);
                char_col <= pixel_x_d1 - 12'd184;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 200 && pixel_x_d1 < 216) begin
                char_code <= digit_to_ascii(ch1_freq_d3);
                char_col <= pixel_x_d1 - 12'd200;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 216 && pixel_x_d1 < 232) begin
                char_code <= digit_to_ascii(ch1_freq_d2);
                char_col <= pixel_x_d1 - 12'd216;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 232 && pixel_x_d1 < 248) begin
                char_code <= digit_to_ascii(ch1_freq_d1);
                char_col <= pixel_x_d1 - 12'd232;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 248 && pixel_x_d1 < 264) begin
                char_code <= digit_to_ascii(ch1_freq_d0);
                char_col <= pixel_x_d1 - 12'd248;
                in_char_area <= 1'b1;
            end
            // "Hz"
            else if (pixel_x_d1 >= 264 && pixel_x_d1 < 280) begin
                char_code <= 8'd72;  // 'H'
                char_col <= pixel_x_d1 - 12'd264;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 280 && pixel_x_d1 < 296) begin
                char_code <= 8'd122; // 'z'
                char_col <= pixel_x_d1 - 12'd280;
                in_char_area <= 1'b1;
            end
            
            // 分隔�?"|"
            else if (pixel_x_d1 >= 460 && pixel_x_d1 < 476) begin
                char_code <= 8'd124; // '|'
                char_col <= pixel_x_d1 - 12'd460;
                in_char_area <= 1'b1;
            end
            
            // ===== CH2频率 (右侧 X: 500-900) =====
            // "CH2 "
            else if (pixel_x_d1 >= 500 && pixel_x_d1 < 516) begin
                char_code <= 8'd67;  // 'C'
                char_col <= pixel_x_d1 - 12'd500;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 516 && pixel_x_d1 < 532) begin
                char_code <= 8'd72;  // 'H'
                char_col <= pixel_x_d1 - 12'd516;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 532 && pixel_x_d1 < 548) begin
                char_code <= 8'd50;  // '2'
                char_col <= pixel_x_d1 - 12'd532;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 548 && pixel_x_d1 < 564) begin
                char_code <= 8'd32;  // ' '
                char_col <= pixel_x_d1 - 12'd548;
                in_char_area <= 1'b1;
            end
            // "Freq:"
            else if (pixel_x_d1 >= 564 && pixel_x_d1 < 580) begin
                char_code <= 8'd70;  // 'F'
                char_col <= pixel_x_d1 - 12'd564;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 580 && pixel_x_d1 < 596) begin
                char_code <= 8'd114; // 'r'
                char_col <= pixel_x_d1 - 12'd580;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 596 && pixel_x_d1 < 612) begin
                char_code <= 8'd101; // 'e'
                char_col <= pixel_x_d1 - 12'd596;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 612 && pixel_x_d1 < 628) begin
                char_code <= 8'd113; // 'q'
                char_col <= pixel_x_d1 - 12'd612;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 628 && pixel_x_d1 < 644) begin
                char_code <= 8'd58;  // ':'
                char_col <= pixel_x_d1 - 12'd628;
                in_char_area <= 1'b1;
            end
            // CH2频率数�?(5位数)
            else if (pixel_x_d1 >= 644 && pixel_x_d1 < 660) begin
                char_code <= digit_to_ascii(ch2_freq_d4);
                char_col <= pixel_x_d1 - 12'd644;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 660 && pixel_x_d1 < 676) begin
                char_code <= digit_to_ascii(ch2_freq_d3);
                char_col <= pixel_x_d1 - 12'd660;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 676 && pixel_x_d1 < 692) begin
                char_code <= digit_to_ascii(ch2_freq_d2);
                char_col <= pixel_x_d1 - 12'd676;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 692 && pixel_x_d1 < 708) begin
                char_code <= digit_to_ascii(ch2_freq_d1);
                char_col <= pixel_x_d1 - 12'd692;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 708 && pixel_x_d1 < 724) begin
                char_code <= digit_to_ascii(ch2_freq_d0);
                char_col <= pixel_x_d1 - 12'd708;
                in_char_area <= 1'b1;
            end
            // "Hz"
            else if (pixel_x_d1 >= 724 && pixel_x_d1 < 740) begin
                char_code <= 8'd72;  // 'H'
                char_col <= pixel_x_d1 - 12'd724;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 740 && pixel_x_d1 < 756) begin
                char_code <= 8'd122; // 'z'
                char_col <= pixel_x_d1 - 12'd740;
                in_char_area <= 1'b1;
            end
        end
        
        // �?�? 幅度 - 左右分栏 "CH1 Ampl:0051 | CH2 Ampl:0051" (Y: 905-937)
        else if (pixel_y_d1 >= PARAM_Y_START + 35 && pixel_y_d1 < PARAM_Y_START + 67) begin
            char_row <= pixel_y_d1 - PARAM_Y_START - 12'd35;
            
            // ===== CH1幅度 (左侧) =====
            // "CH1 "
            if (pixel_x_d1 >= 40 && pixel_x_d1 < 56) begin
                char_code <= 8'd67;  // 'C'
                char_col <= pixel_x_d1 - 12'd40;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 56 && pixel_x_d1 < 72) begin
                char_code <= 8'd72;  // 'H'
                char_col <= pixel_x_d1 - 12'd56;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 72 && pixel_x_d1 < 88) begin
                char_code <= 8'd49;  // '1'
                char_col <= pixel_x_d1 - 12'd72;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 88 && pixel_x_d1 < 104) begin
                char_code <= 8'd32;  // ' '
                char_col <= pixel_x_d1 - 12'd88;
                in_char_area <= 1'b1;
            end
            // "Ampl:"
            else if (pixel_x_d1 >= 104 && pixel_x_d1 < 120) begin
                char_code <= 8'd65;  // 'A'
                char_col <= pixel_x_d1 - 12'd104;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 120 && pixel_x_d1 < 136) begin
                char_code <= 8'd109; // 'm'
                char_col <= pixel_x_d1 - 12'd120;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 136 && pixel_x_d1 < 152) begin
                char_code <= 8'd112; // 'p'
                char_col <= pixel_x_d1 - 12'd136;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 152 && pixel_x_d1 < 168) begin
                char_code <= 8'd108; // 'l'
                char_col <= pixel_x_d1 - 12'd152;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 168 && pixel_x_d1 < 184) begin
                char_code <= 8'd58;  // ':'
                char_col <= pixel_x_d1 - 12'd168;
                in_char_area <= 1'b1;
            end
            // CH1幅度数�?(4位数)
            else if (pixel_x_d1 >= 184 && pixel_x_d1 < 200) begin
                char_code <= digit_to_ascii(ch1_amp_d3);
                char_col <= pixel_x_d1 - 12'd184;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 200 && pixel_x_d1 < 216) begin
                char_code <= digit_to_ascii(ch1_amp_d2);
                char_col <= pixel_x_d1 - 12'd200;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 216 && pixel_x_d1 < 232) begin
                char_code <= digit_to_ascii(ch1_amp_d1);
                char_col <= pixel_x_d1 - 12'd216;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 232 && pixel_x_d1 < 248) begin
                char_code <= digit_to_ascii(ch1_amp_d0);
                char_col <= pixel_x_d1 - 12'd232;
                in_char_area <= 1'b1;
            end
            
            // 分隔�?"|"
            else if (pixel_x_d1 >= 460 && pixel_x_d1 < 476) begin
                char_code <= 8'd124; // '|'
                char_col <= pixel_x_d1 - 12'd460;
                in_char_area <= 1'b1;
            end
            
            // ===== CH2幅度 (右侧) =====
            // "CH2 "
            else if (pixel_x_d1 >= 500 && pixel_x_d1 < 516) begin
                char_code <= 8'd67;  // 'C'
                char_col <= pixel_x_d1 - 12'd500;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 516 && pixel_x_d1 < 532) begin
                char_code <= 8'd72;  // 'H'
                char_col <= pixel_x_d1 - 12'd516;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 532 && pixel_x_d1 < 548) begin
                char_code <= 8'd50;  // '2'
                char_col <= pixel_x_d1 - 12'd532;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 548 && pixel_x_d1 < 564) begin
                char_code <= 8'd32;  // ' '
                char_col <= pixel_x_d1 - 12'd548;
                in_char_area <= 1'b1;
            end
            // "Ampl:"
            else if (pixel_x_d1 >= 564 && pixel_x_d1 < 580) begin
                char_code <= 8'd65;  // 'A'
                char_col <= pixel_x_d1 - 12'd564;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 580 && pixel_x_d1 < 596) begin
                char_code <= 8'd109; // 'm'
                char_col <= pixel_x_d1 - 12'd580;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 596 && pixel_x_d1 < 612) begin
                char_code <= 8'd112; // 'p'
                char_col <= pixel_x_d1 - 12'd596;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 612 && pixel_x_d1 < 628) begin
                char_code <= 8'd108; // 'l'
                char_col <= pixel_x_d1 - 12'd612;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 628 && pixel_x_d1 < 644) begin
                char_code <= 8'd58;  // ':'
                char_col <= pixel_x_d1 - 12'd628;
                in_char_area <= 1'b1;
            end
            // CH2幅度数�?(4位数)
            else if (pixel_x_d1 >= 644 && pixel_x_d1 < 660) begin
                char_code <= digit_to_ascii(ch2_amp_d3);
                char_col <= pixel_x_d1 - 12'd644;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 660 && pixel_x_d1 < 676) begin
                char_code <= digit_to_ascii(ch2_amp_d2);
                char_col <= pixel_x_d1 - 12'd660;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 676 && pixel_x_d1 < 692) begin
                char_code <= digit_to_ascii(ch2_amp_d1);
                char_col <= pixel_x_d1 - 12'd676;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 692 && pixel_x_d1 < 708) begin
                char_code <= digit_to_ascii(ch2_amp_d0);
                char_col <= pixel_x_d1 - 12'd692;
                in_char_area <= 1'b1;
            end
        end
        
        // �?�? 占空�?- 左右分栏 "CH1 Duty:50.0% | CH2 Duty:50.0%" (Y: 940-972)
        else if (pixel_y_d1 >= PARAM_Y_START + 70 && pixel_y_d1 < PARAM_Y_START + 102) begin
            char_row <= pixel_y_d1 - PARAM_Y_START - 12'd70;
            
            // ===== CH1占空�?(左侧) =====
            // "CH1 "
            if (pixel_x_d1 >= 40 && pixel_x_d1 < 56) begin
                char_code <= 8'd67;  // 'C'
                char_col <= pixel_x_d1 - 12'd40;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 56 && pixel_x_d1 < 72) begin
                char_code <= 8'd72;  // 'H'
                char_col <= pixel_x_d1 - 12'd56;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 72 && pixel_x_d1 < 88) begin
                char_code <= 8'd49;  // '1'
                char_col <= pixel_x_d1 - 12'd72;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 88 && pixel_x_d1 < 104) begin
                char_code <= 8'd32;  // ' '
                char_col <= pixel_x_d1 - 12'd88;
                in_char_area <= 1'b1;
            end
            // "Duty:"
            else if (pixel_x_d1 >= 104 && pixel_x_d1 < 120) begin
                char_code <= 8'd68;  // 'D'
                char_col <= pixel_x_d1 - 12'd104;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 120 && pixel_x_d1 < 136) begin
                char_code <= 8'd117; // 'u'
                char_col <= pixel_x_d1 - 12'd120;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 136 && pixel_x_d1 < 152) begin
                char_code <= 8'd116; // 't'
                char_col <= pixel_x_d1 - 12'd136;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 152 && pixel_x_d1 < 168) begin
                char_code <= 8'd121; // 'y'
                char_col <= pixel_x_d1 - 12'd152;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 168 && pixel_x_d1 < 184) begin
                char_code <= 8'd58;  // ':'
                char_col <= pixel_x_d1 - 12'd168;
                in_char_area <= 1'b1;
            end
            // CH1占空比数�?(格式: 50.0%)
            else if (pixel_x_d1 >= 184 && pixel_x_d1 < 200) begin
                char_code <= digit_to_ascii(ch1_duty_d2);
                char_col <= pixel_x_d1 - 12'd184;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 200 && pixel_x_d1 < 216) begin
                char_code <= digit_to_ascii(ch1_duty_d1);
                char_col <= pixel_x_d1 - 12'd200;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 216 && pixel_x_d1 < 232) begin
                char_code <= 8'd46;  // '.'
                char_col <= pixel_x_d1 - 12'd216;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 232 && pixel_x_d1 < 248) begin
                char_code <= digit_to_ascii(ch1_duty_d0);
                char_col <= pixel_x_d1 - 12'd232;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 248 && pixel_x_d1 < 264) begin
                char_code <= 8'd37;  // '%'
                char_col <= pixel_x_d1 - 12'd248;
                in_char_area <= 1'b1;
            end
            
            // 分隔�?"|"
            else if (pixel_x_d1 >= 460 && pixel_x_d1 < 476) begin
                char_code <= 8'd124; // '|'
                char_col <= pixel_x_d1 - 12'd460;
                in_char_area <= 1'b1;
            end
            
            // ===== CH2占空�?(右侧) =====
            // "CH2 "
            else if (pixel_x_d1 >= 500 && pixel_x_d1 < 516) begin
                char_code <= 8'd67;  // 'C'
                char_col <= pixel_x_d1 - 12'd500;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 516 && pixel_x_d1 < 532) begin
                char_code <= 8'd72;  // 'H'
                char_col <= pixel_x_d1 - 12'd516;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 532 && pixel_x_d1 < 548) begin
                char_code <= 8'd50;  // '2'
                char_col <= pixel_x_d1 - 12'd532;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 548 && pixel_x_d1 < 564) begin
                char_code <= 8'd32;  // ' '
                char_col <= pixel_x_d1 - 12'd548;
                in_char_area <= 1'b1;
            end
            // "Duty:"
            else if (pixel_x_d1 >= 564 && pixel_x_d1 < 580) begin
                char_code <= 8'd68;  // 'D'
                char_col <= pixel_x_d1 - 12'd564;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 580 && pixel_x_d1 < 596) begin
                char_code <= 8'd117; // 'u'
                char_col <= pixel_x_d1 - 12'd580;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 596 && pixel_x_d1 < 612) begin
                char_code <= 8'd116; // 't'
                char_col <= pixel_x_d1 - 12'd596;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 612 && pixel_x_d1 < 628) begin
                char_code <= 8'd121; // 'y'
                char_col <= pixel_x_d1 - 12'd612;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 628 && pixel_x_d1 < 644) begin
                char_code <= 8'd58;  // ':'
                char_col <= pixel_x_d1 - 12'd628;
                in_char_area <= 1'b1;
            end
            // CH2占空比数�?(格式: 50.0%)
            else if (pixel_x_d1 >= 644 && pixel_x_d1 < 660) begin
                char_code <= digit_to_ascii(ch2_duty_d2);
                char_col <= pixel_x_d1 - 12'd644;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 660 && pixel_x_d1 < 676) begin
                char_code <= digit_to_ascii(ch2_duty_d1);
                char_col <= pixel_x_d1 - 12'd660;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 676 && pixel_x_d1 < 692) begin
                char_code <= 8'd46;  // '.'
                char_col <= pixel_x_d1 - 12'd676;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 692 && pixel_x_d1 < 708) begin
                char_code <= digit_to_ascii(ch2_duty_d0);
                char_col <= pixel_x_d1 - 12'd692;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 708 && pixel_x_d1 < 724) begin
                char_code <= 8'd37;  // '%'
                char_col <= pixel_x_d1 - 12'd708;
                in_char_area <= 1'b1;
            end
        end
        
        // �?�? THD - 左右分栏 "CH1 THD:1.23% | CH2 THD:1.23%" (Y: 975-1007)
        else if (pixel_y_d1 >= PARAM_Y_START + 105 && pixel_y_d1 < PARAM_Y_START + 137) begin
            char_row <= pixel_y_d1 - PARAM_Y_START - 12'd105;
            
            // ===== CH1 THD (左侧) =====
            // "CH1 "
            if (pixel_x_d1 >= 40 && pixel_x_d1 < 56) begin
                char_code <= 8'd67;  // 'C'
                char_col <= pixel_x_d1 - 12'd40;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 56 && pixel_x_d1 < 72) begin
                char_code <= 8'd72;  // 'H'
                char_col <= pixel_x_d1 - 12'd56;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 72 && pixel_x_d1 < 88) begin
                char_code <= 8'd49;  // '1'
                char_col <= pixel_x_d1 - 12'd72;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 88 && pixel_x_d1 < 104) begin
                char_code <= 8'd32;  // ' '
                char_col <= pixel_x_d1 - 12'd88;
                in_char_area <= 1'b1;
            end
            // "THD:"
            else if (pixel_x_d1 >= 104 && pixel_x_d1 < 120) begin
                char_code <= 8'd84;  // 'T'
                char_col <= pixel_x_d1 - 12'd104;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 120 && pixel_x_d1 < 136) begin
                char_code <= 8'd72;  // 'H'
                char_col <= pixel_x_d1 - 12'd120;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 136 && pixel_x_d1 < 152) begin
                char_code <= 8'd68;  // 'D'
                char_col <= pixel_x_d1 - 12'd136;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 152 && pixel_x_d1 < 168) begin
                char_code <= 8'd58;  // ':'
                char_col <= pixel_x_d1 - 12'd152;
                in_char_area <= 1'b1;
            end
            // CH1 THD数�?(格式: 1.23%)
            else if (pixel_x_d1 >= 168 && pixel_x_d1 < 184) begin
                char_code <= digit_to_ascii(ch1_thd_d2);
                char_col <= pixel_x_d1 - 12'd168;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 184 && pixel_x_d1 < 200) begin
                char_code <= 8'd46;  // '.'
                char_col <= pixel_x_d1 - 12'd184;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 200 && pixel_x_d1 < 216) begin
                char_code <= digit_to_ascii(ch1_thd_d1);
                char_col <= pixel_x_d1 - 12'd200;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 216 && pixel_x_d1 < 232) begin
                char_code <= digit_to_ascii(ch1_thd_d0);
                char_col <= pixel_x_d1 - 12'd216;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 232 && pixel_x_d1 < 248) begin
                char_code <= 8'd37;  // '%'
                char_col <= pixel_x_d1 - 12'd232;
                in_char_area <= 1'b1;
            end
            
            // 分隔�?"|"
            else if (pixel_x_d1 >= 460 && pixel_x_d1 < 476) begin
                char_code <= 8'd124; // '|'
                char_col <= pixel_x_d1 - 12'd460;
                in_char_area <= 1'b1;
            end
            
            // ===== CH2 THD (右侧) =====
            // "CH2 "
            else if (pixel_x_d1 >= 500 && pixel_x_d1 < 516) begin
                char_code <= 8'd67;  // 'C'
                char_col <= pixel_x_d1 - 12'd500;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 516 && pixel_x_d1 < 532) begin
                char_code <= 8'd72;  // 'H'
                char_col <= pixel_x_d1 - 12'd516;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 532 && pixel_x_d1 < 548) begin
                char_code <= 8'd50;  // '2'
                char_col <= pixel_x_d1 - 12'd532;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 548 && pixel_x_d1 < 564) begin
                char_code <= 8'd32;  // ' '
                char_col <= pixel_x_d1 - 12'd548;
                in_char_area <= 1'b1;
            end
            // "THD:"
            else if (pixel_x_d1 >= 564 && pixel_x_d1 < 580) begin
                char_code <= 8'd84;  // 'T'
                char_col <= pixel_x_d1 - 12'd564;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 580 && pixel_x_d1 < 596) begin
                char_code <= 8'd72;  // 'H'
                char_col <= pixel_x_d1 - 12'd580;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 596 && pixel_x_d1 < 612) begin
                char_code <= 8'd68;  // 'D'
                char_col <= pixel_x_d1 - 12'd596;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 612 && pixel_x_d1 < 628) begin
                char_code <= 8'd58;  // ':'
                char_col <= pixel_x_d1 - 12'd612;
                in_char_area <= 1'b1;
            end
            // CH2 THD数�?(格式: 1.23%)
            else if (pixel_x_d1 >= 628 && pixel_x_d1 < 644) begin
                char_code <= digit_to_ascii(ch2_thd_d2);
                char_col <= pixel_x_d1 - 12'd628;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 644 && pixel_x_d1 < 660) begin
                char_code <= 8'd46;  // '.'
                char_col <= pixel_x_d1 - 12'd644;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 660 && pixel_x_d1 < 676) begin
                char_code <= digit_to_ascii(ch2_thd_d1);
                char_col <= pixel_x_d1 - 12'd660;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 676 && pixel_x_d1 < 692) begin
                char_code <= digit_to_ascii(ch2_thd_d0);
                char_col <= pixel_x_d1 - 12'd676;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 692 && pixel_x_d1 < 708) begin
                char_code <= 8'd37;  // '%'
                char_col <= pixel_x_d1 - 12'd692;
                in_char_area <= 1'b1;
            end
        end
        
        // �?�? "Phase:180.0" (相位差，Y: 870+140=1010)
        else if (pixel_y_d1 >= PARAM_Y_START + 140 && pixel_y_d1 < PARAM_Y_START + 172) begin
            char_row <= pixel_y_d1 - PARAM_Y_START - 12'd140;
            // "Phase:"
            if (pixel_x_d1 >= 40 && pixel_x_d1 < 56) begin
                char_code <= 8'd80;  // 'P'
                char_col <= pixel_x_d1 - 12'd40;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 56 && pixel_x_d1 < 72) begin
                char_code <= 8'd104; // 'h'
                char_col <= pixel_x_d1 - 12'd56;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 72 && pixel_x_d1 < 88) begin
                char_code <= 8'd97;  // 'a'
                char_col <= pixel_x_d1 - 12'd72;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 88 && pixel_x_d1 < 104) begin
                char_code <= 8'd115; // 's'
                char_col <= pixel_x_d1 - 12'd88;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 104 && pixel_x_d1 < 120) begin
                char_code <= 8'd101; // 'e'
                char_col <= pixel_x_d1 - 12'd104;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 120 && pixel_x_d1 < 136) begin
                char_code <= 8'd58;  // ':'
                char_col <= pixel_x_d1 - 12'd120;
                in_char_area <= 1'b1;
            end
            // 显示相位差数�?(格式: 180.0)
            else if (pixel_x_d1 >= 144 && pixel_x_d1 < 160) begin
                char_code <= digit_to_ascii(phase_d3);  // 百位
                char_col <= pixel_x_d1 - 12'd144;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 160 && pixel_x_d1 < 176) begin
                char_code <= digit_to_ascii(phase_d2);  // 十位
                char_col <= pixel_x_d1 - 12'd160;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 176 && pixel_x_d1 < 192) begin
                char_code <= digit_to_ascii(phase_d1);  // 个位
                char_col <= pixel_x_d1 - 12'd176;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 192 && pixel_x_d1 < 208) begin
                char_code <= 8'd46;  // '.'
                char_col <= pixel_x_d1 - 12'd192;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 208 && pixel_x_d1 < 224) begin
                char_code <= digit_to_ascii(phase_d0);  // 小数�?
                char_col <= pixel_x_d1 - 12'd208;
                in_char_area <= 1'b1;
            end
        end
        
        // �?�? "CH1:Sine95% CH2:Squr88%" - AI识别结果 (Y: 870+175=1045)
        else if (pixel_y_d1 >= PARAM_Y_START + 175 && pixel_y_d1 < PARAM_Y_START + 207) begin
            char_row <= pixel_y_d1 - PARAM_Y_START - 12'd175;
            
            // ========== CH1部分 (左侧) ==========
            // "CH1:"
            if (pixel_x_d1 >= 40 && pixel_x_d1 < 56) begin
                char_code <= 8'd67;  // 'C'
                char_col <= pixel_x_d1 - 12'd40;
                in_char_area <= 1'b1;  // 始终显示（调试用�?
            end
            else if (pixel_x_d1 >= 56 && pixel_x_d1 < 72) begin
                char_code <= 8'd72;  // 'H'
                char_col <= pixel_x_d1 - 12'd56;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 72 && pixel_x_d1 < 88) begin
                char_code <= 8'd49;  // '1'
                char_col <= pixel_x_d1 - 12'd72;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 88 && pixel_x_d1 < 104) begin
                char_code <= 8'd58;  // ':'
                char_col <= pixel_x_d1 - 12'd88;
                in_char_area <= 1'b1;
            end
            // CH1波形类型名称 (4个字�?
            else if (pixel_x_d1 >= 104 && pixel_x_d1 < 120) begin
                case (ch1_waveform_type)
                    3'd1: char_code <= 8'd83;  // 'S' (Sine)
                    3'd2: char_code <= 8'd83;  // 'S' (Square)
                    3'd3: char_code <= 8'd84;  // 'T' (Triangle)
                    3'd4: char_code <= 8'd83;  // 'S' (Sawtooth)
                    3'd5: char_code <= 8'd78;  // 'N' (Noise)
                    default: char_code <= 8'd85; // 'U' (Unknown)
                endcase
                char_col <= pixel_x_d1 - 12'd104;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 120 && pixel_x_d1 < 136) begin
                case (ch1_waveform_type)
                    3'd1: char_code <= 8'd105; // 'i'
                    3'd2: char_code <= 8'd113; // 'q'
                    3'd3: char_code <= 8'd114; // 'r'
                    3'd4: char_code <= 8'd97;  // 'a'
                    3'd5: char_code <= 8'd111; // 'o'
                    default: char_code <= 8'd110; // 'n'
                endcase
                char_col <= pixel_x_d1 - 12'd120;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 136 && pixel_x_d1 < 152) begin
                case (ch1_waveform_type)
                    3'd1: char_code <= 8'd110; // 'n'
                    3'd2: char_code <= 8'd117; // 'u'
                    3'd3: char_code <= 8'd105; // 'i'
                    3'd4: char_code <= 8'd119; // 'w'
                    3'd5: char_code <= 8'd105; // 'i'
                    default: char_code <= 8'd107; // 'k'
                endcase
                char_col <= pixel_x_d1 - 12'd136;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 152 && pixel_x_d1 < 168) begin
                case (ch1_waveform_type)
                    3'd1: char_code <= 8'd101; // 'e' (Sine)
                    3'd2: char_code <= 8'd114; // 'r' (Squr)
                    3'd3: char_code <= 8'd97;  // 'a' (Tria)
                    3'd4: char_code <= 8'd32;  // ' ' (Saw)
                    3'd5: char_code <= 8'd115; // 's' (Nois)
                    default: char_code <= 8'd110; // 'n' (Unkn)
                endcase
                char_col <= pixel_x_d1 - 12'd152;
                in_char_area <= 1'b1;
            end
            // CH1置信�?(两位数字 + '%')
            else if (pixel_x_d1 >= 168 && pixel_x_d1 < 184) begin
                char_code <= digit_to_ascii((ch1_confidence / 10) % 10); // 十位
                char_col <= pixel_x_d1 - 12'd168;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 184 && pixel_x_d1 < 200) begin
                char_code <= digit_to_ascii(ch1_confidence % 10); // 个位
                char_col <= pixel_x_d1 - 12'd184;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 200 && pixel_x_d1 < 216) begin
                char_code <= 8'd37; // '%'
                char_col <= pixel_x_d1 - 12'd200;
                in_char_area <= 1'b1;
            end
            
            // ========== 分隔空格 ==========
            // X: 216-280 (�?4像素空白)
            
            // ========== CH2部分 (右侧) ==========
            // "CH2:"
            else if (pixel_x_d1 >= 280 && pixel_x_d1 < 296) begin
                char_code <= 8'd67;  // 'C'
                char_col <= pixel_x_d1 - 12'd280;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 296 && pixel_x_d1 < 312) begin
                char_code <= 8'd72;  // 'H'
                char_col <= pixel_x_d1 - 12'd296;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 312 && pixel_x_d1 < 328) begin
                char_code <= 8'd50;  // '2'
                char_col <= pixel_x_d1 - 12'd312;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 328 && pixel_x_d1 < 344) begin
                char_code <= 8'd58;  // ':'
                char_col <= pixel_x_d1 - 12'd328;
                in_char_area <= 1'b1;
            end
            // CH2波形类型名称 (4个字�?
            else if (pixel_x_d1 >= 344 && pixel_x_d1 < 360) begin
                case (ch2_waveform_type)
                    3'd1: char_code <= 8'd83;  // 'S' (Sine)
                    3'd2: char_code <= 8'd83;  // 'S' (Square)
                    3'd3: char_code <= 8'd84;  // 'T' (Triangle)
                    3'd4: char_code <= 8'd83;  // 'S' (Sawtooth)
                    3'd5: char_code <= 8'd78;  // 'N' (Noise)
                    default: char_code <= 8'd85; // 'U' (Unknown)
                endcase
                char_col <= pixel_x_d1 - 12'd344;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 360 && pixel_x_d1 < 376) begin
                case (ch2_waveform_type)
                    3'd1: char_code <= 8'd105; // 'i'
                    3'd2: char_code <= 8'd113; // 'q'
                    3'd3: char_code <= 8'd114; // 'r'
                    3'd4: char_code <= 8'd97;  // 'a'
                    3'd5: char_code <= 8'd111; // 'o'
                    default: char_code <= 8'd110; // 'n'
                endcase
                char_col <= pixel_x_d1 - 12'd360;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 376 && pixel_x_d1 < 392) begin
                case (ch2_waveform_type)
                    3'd1: char_code <= 8'd110; // 'n'
                    3'd2: char_code <= 8'd117; // 'u'
                    3'd3: char_code <= 8'd105; // 'i'
                    3'd4: char_code <= 8'd119; // 'w'
                    3'd5: char_code <= 8'd105; // 'i'
                    default: char_code <= 8'd107; // 'k'
                endcase
                char_col <= pixel_x_d1 - 12'd376;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 392 && pixel_x_d1 < 408) begin
                case (ch2_waveform_type)
                    3'd1: char_code <= 8'd101; // 'e' (Sine)
                    3'd2: char_code <= 8'd114; // 'r' (Squr)
                    3'd3: char_code <= 8'd97;  // 'a' (Tria)
                    3'd4: char_code <= 8'd32;  // ' ' (Saw)
                    3'd5: char_code <= 8'd115; // 's' (Nois)
                    default: char_code <= 8'd110; // 'n' (Unkn)
                endcase
                char_col <= pixel_x_d1 - 12'd392;
                in_char_area <= 1'b1;
            end
            // CH2置信�?(两位数字 + '%')
            else if (pixel_x_d1 >= 408 && pixel_x_d1 < 424) begin
                char_code <= digit_to_ascii((ch2_confidence / 10) % 10); // 十位
                char_col <= pixel_x_d1 - 12'd408;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 424 && pixel_x_d1 < 440) begin
                char_code <= digit_to_ascii(ch2_confidence % 10); // 个位
                char_col <= pixel_x_d1 - 12'd424;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 440 && pixel_x_d1 < 456) begin
                char_code <= 8'd37; // '%'
                char_col <= pixel_x_d1 - 12'd440;
                in_char_area <= 1'b1;
            end
        end
    end  // 结束 if (pixel_y_d1 >= PARAM_Y_START && pixel_y_d1 < PARAM_Y_END)
    end  // 结束 else begin (复位�?
end  // 结束 always @(posedge clk_pixel or negedge rst_n)

//=============================================================================
// RGB数据生成（美化版 - 使用延迟后的坐标�?
//=============================================================================
always @(*) begin
    rgb_data = 24'h000000;  // 默认黑色背景
    spectrum_height_calc = 12'd0;
    char_color = 24'hFFFFFF;  // 默认白色文字
    
    // �?避免latch：为频谱高度变量赋默认�?
    ch1_spectrum_height = 12'd0;
    ch2_spectrum_height = 12'd0;
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
            
            // 左右边框
            if (pixel_x_d3 < 2 || pixel_x_d3 >= H_ACTIVE - 2) begin
                rgb_data = 24'h4080FF;  // 蓝色边框
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
                // �?双通道频谱高度计算�?x增益�?
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
                
                // 网格线（使用d4信号�?
                if (grid_x_flag_d4 || grid_y_flag_d4) begin
                    rgb_data = 24'h303030;
                end
                else begin
                    // �?流水线优化：频谱命中检测也在Stage 4完成
                    // 使用Stage 3计算的频谱高度（ch1_spectrum_calc_d1, ch2_spectrum_calc_d1�?
                    
                    // �?方案3优化：简化频谱RGB选择（减少嵌套if�?
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
            end  // 结束 work_mode_d4 else �?
        end
        
        // ========== 中间分隔�?==========
        else if (pixel_y_d3 >= SPECTRUM_Y_END && pixel_y_d3 < PARAM_Y_START) begin
            // 左右边框
            if (pixel_x_d3 < 2 || pixel_x_d3 >= H_ACTIVE - 2) begin
                rgb_data = 24'h4080FF;  // 蓝色边框
            end
            else if (pixel_y_d3 == SPECTRUM_Y_END || pixel_y_d3 == PARAM_Y_START - 1) begin
                rgb_data = 24'h4080FF;  // 蓝色分隔�?
            end else begin
                rgb_data = 24'h0F0F23;  // 深色背景
            end
        end
        
        // ========== 参数显示区域 ==========
        else if (pixel_y_d3 >= PARAM_Y_START && pixel_y_d3 < PARAM_Y_END) begin
            // 左右边框�?像素宽）
            if (pixel_x_d3 < 2 || pixel_x_d3 >= H_ACTIVE - 2) begin
                rgb_data = 24'h4080FF;  // 蓝色边框
            end
            // 背景渐变
            else begin
                rgb_data = {8'd15, 8'd15, 8'd30};  // 深蓝色背�?
            end
            
            // 字符显示（使用延迟后的ROM数据�?
            // �?修正：char_col需要模16以获取正确的列索引（0-15�?
            if (in_char_area && char_pixel_row[15 - char_col[3:0]]) begin
                // 根据参数行位置设置不同颜色（紧凑布局�?px间距�?
                if (pixel_y_d3 < PARAM_Y_START + 35)           // Y < 905: �?�?(频率)
                    char_color = 24'h00FFFF;  // 青色 - 频率
                else if (pixel_y_d3 < PARAM_Y_START + 70)      // Y < 940: �?�?(幅度)
                    char_color = 24'hFFFF00;  // 黄色 - 幅度
                else if (pixel_y_d3 < PARAM_Y_START + 105)     // Y < 975: �?�?(占空�?
                    char_color = 24'h00FF00;  // 绿色 - 占空�?
                else if (pixel_y_d3 < PARAM_Y_START + 140)     // Y < 1010: �?�?(THD)
                    char_color = 24'hFF8800;  // 橙色 - THD
                else if (pixel_y_d3 < PARAM_Y_START + 175)     // Y < 1045: �?�?(相位�?
                    char_color = 24'hFF00FF;  // 洋红�?- 相位�?
                else                                           // Y >= 1045: �?�?(AI识别)
                    char_color = 24'hFFFFFF;  // 白色 - AI识别结果
                
                rgb_data = char_color;
            end
        end
        
        // ========== 底部边框 ==========
        else if (pixel_y_d3 >= PARAM_Y_END) begin
            // 左右边框
            if (pixel_x_d3 < 2 || pixel_x_d3 >= H_ACTIVE - 2) begin
                rgb_data = 24'h4080FF;  // 蓝色边框
            end
            else if (pixel_y_d3 >= V_ACTIVE - 2) begin
                rgb_data = 24'h4080FF;  // 蓝色底边
            end else begin
                rgb_data = 24'h000000;  // 黑色
            end
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
