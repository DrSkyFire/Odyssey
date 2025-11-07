//=============================================================================
// 文件名: auto_test.v
// 描述: 自动测试模块 - 参数阈值判断与LED指示（层级化设计）
//       根据测试要求判断各参数是否合格，通过LED反馈结果
// 新功能：
//   - 层级化参数调整（上下限独立控制）
//   - 可调步进模式（细调/中调/粗调）
//   - 恢复默认值功能
//   - HDMI显示输出接口
//=============================================================================

module auto_test (
    input  wire         clk,
    input  wire         rst_n,
    
    // 测试控制
    input  wire         test_enable,        // 测试使能
    input  wire [2:0]   adjust_mode,        // 当前调整模式（0=IDLE, 1=FREQ, 2=AMP, 3=DUTY, 4=THD）
    input  wire [1:0]   step_mode,          // 步进模式（0=细调, 1=中调, 2=粗调）
    
    // 参数输入
    input  wire [31:0]  freq,               // 频率 (Hz，使用32位支持大频率值)
    input  wire [15:0]  amplitude,          // 幅度 (mV)
    input  wire [15:0]  duty,               // 占空比 (0-1000 = 0-100%)
    input  wire [15:0]  thd,                // THD (0-1000 = 0-100%)
    input  wire [15:0]  phase_diff,         // 相位差 (0-3599 = 0-359.9°)
    input  wire         param_valid,        // 参数有效标志
    
    // 层级化阈值配置按键
    input  wire         btn_limit_dn_dn,    // 下限减少
    input  wire         btn_limit_dn_up,    // 下限增加
    input  wire         btn_limit_up_dn,    // 上限减少
    input  wire         btn_limit_up_up,    // 上限增加
    input  wire         btn_reset_default,  // 恢复默认值
    
    // 测试结果输出 (LED映射)
    output reg [7:0]    test_result,        // 8位LED指示
    // Bit[0]: 频率测试结果 (1=合格, 0=不合格)
    // Bit[1]: 幅度测试结果
    // Bit[2]: 占空比测试结果
    // Bit[3]: THD测试结果
    // Bit[4]: 相位差测试结果
    // Bit[5]: 综合测试结果 (全部合格时为1)
    // Bit[7:6]: 模式指示
    
    // HDMI显示接口 - Binary格式（保留用于测试）
    output wire [31:0]  freq_min_out,       // 频率下限 (Hz)
    output wire [31:0]  freq_max_out,       // 频率上限 (Hz)
    output wire [15:0]  amp_min_out,        // 幅度下限
    output wire [15:0]  amp_max_out,        // 幅度上限
    output wire [15:0]  duty_min_out,       // 占空比下限
    output wire [15:0]  duty_max_out,       // 占空比上限
    output wire [15:0]  thd_max_out,        // THD上限
    
    // HDMI显示接口 - BCD格式（用于直接显示，无需转换）
    output wire [3:0]   freq_min_d0_out, freq_min_d1_out, freq_min_d2_out,
    output wire [3:0]   freq_min_d3_out, freq_min_d4_out, freq_min_d5_out,
    output wire [3:0]   freq_max_d0_out, freq_max_d1_out, freq_max_d2_out,
    output wire [3:0]   freq_max_d3_out, freq_max_d4_out, freq_max_d5_out,
    output wire [3:0]   amp_min_d0_out, amp_min_d1_out, amp_min_d2_out, amp_min_d3_out,
    output wire [3:0]   amp_max_d0_out, amp_max_d1_out, amp_max_d2_out, amp_max_d3_out,
    output wire [3:0]   duty_min_d0_out, duty_min_d1_out, duty_min_d2_out, duty_min_d3_out,
    output wire [3:0]   duty_max_d0_out, duty_max_d1_out, duty_max_d2_out, duty_max_d3_out,
    output wire [3:0]   thd_max_d0_out, thd_max_d1_out, thd_max_d2_out, thd_max_d3_out
);

//=============================================================================
// 调整模式定义
//=============================================================================
localparam ADJUST_IDLE   = 3'd0;
localparam ADJUST_FREQ   = 3'd1;
localparam ADJUST_AMP    = 3'd2;
localparam ADJUST_DUTY   = 3'd3;
localparam ADJUST_THD    = 3'd4;

//=============================================================================
// 测试阈值寄存器（双格式存储：Binary用于测试，BCD用于显示）
//=============================================================================
// Binary格式（用于实际测试比较）
reg [31:0] freq_min;            // 频率下限 (Hz，32位)
reg [31:0] freq_max;            // 频率上限 (Hz，32位)
reg [15:0] amp_min;             // 幅度下限
reg [15:0] amp_max;             // 幅度上限
reg [15:0] duty_min;            // 占空比下限
reg [15:0] duty_max;            // 占空比上限
reg [15:0] thd_max;             // THD上限（无下限）

// BCD格式（用于HDMI显示，避免除法运算）
// 频率：6位BCD (0-999999 Hz)
reg [3:0] freq_min_d0, freq_min_d1, freq_min_d2, freq_min_d3, freq_min_d4, freq_min_d5;
reg [3:0] freq_max_d0, freq_max_d1, freq_max_d2, freq_max_d3, freq_max_d4, freq_max_d5;
// 幅度：4位BCD (0-9999 mV = 0-9.999V)
reg [3:0] amp_min_d0, amp_min_d1, amp_min_d2, amp_min_d3;
reg [3:0] amp_max_d0, amp_max_d1, amp_max_d2, amp_max_d3;
// 占空比：4位BCD (0-1000 = 0-100.0%)
reg [3:0] duty_min_d0, duty_min_d1, duty_min_d2, duty_min_d3;
reg [3:0] duty_max_d0, duty_max_d1, duty_max_d2, duty_max_d3;
// THD：4位BCD
reg [3:0] thd_max_d0, thd_max_d1, thd_max_d2, thd_max_d3;

// 默认阈值（用户指定）
// 频率: 100kHz ± 容差
localparam FREQ_DEFAULT      = 32'd100000;   // 100kHz (单位:Hz)
localparam FREQ_TOL_DEFAULT  = 32'd5000;     // ±5kHz容差 (单位:Hz)
// 幅度: 3V ± 容差
localparam AMP_DEFAULT       = 16'd3000;     // 3000mV = 3V
localparam AMP_TOL_DEFAULT   = 16'd500;      // ±500mV容差
// 占空比: 60% ± 容差
localparam DUTY_DEFAULT      = 16'd600;      // 60%
localparam DUTY_TOL_DEFAULT  = 16'd50;       // ±5%容差
// THD: 最大60%
localparam THD_MAX_DEFAULT   = 16'd600;      // 60%

// 步进值（3档：细调/中调/粗调）
localparam FREQ_STEP_FINE    = 32'd1;        // 1Hz
localparam FREQ_STEP_MID     = 32'd100;      // 100Hz
localparam FREQ_STEP_COARSE  = 32'd100000;   // 100kHz

localparam AMP_STEP_FINE     = 16'd1;        // 1mV
localparam AMP_STEP_MID      = 16'd100;      // 100mV
localparam AMP_STEP_COARSE   = 16'd1000;     // 1V = 1000mV

localparam DUTY_STEP_FINE    = 16'd1;        // 0.1%
localparam DUTY_STEP_MID     = 16'd10;       // 1%
localparam DUTY_STEP_COARSE  = 16'd100;      // 10%

localparam THD_STEP_FINE     = 16'd1;        // 0.1%
localparam THD_STEP_MID      = 16'd10;       // 1%
localparam THD_STEP_COARSE   = 16'd100;      // 10%

//=============================================================================
// BCD辅助函数（仅保留BCD→Binary，Binary→BCD使用状态机）
//=============================================================================

// BCD转Binary（6位BCD → 32位）
function automatic [31:0] bcd6_to_bin32;
    input [23:0] bcd;
    begin
        bcd6_to_bin32 = bcd[3:0] + 
                       bcd[7:4] * 10 +
                       bcd[11:8] * 100 +
                       bcd[15:12] * 1000 +
                       bcd[19:16] * 10000 +
                       bcd[23:20] * 100000;
    end
endfunction

// BCD转Binary（4位BCD → 16位）
function automatic [15:0] bcd4_to_bin16;
    input [15:0] bcd;
    begin
        bcd4_to_bin16 = bcd[3:0] + 
                       bcd[7:4] * 10 +
                       bcd[11:8] * 100 +
                       bcd[15:12] * 1000;
    end
endfunction

//=============================================================================
// BCD转换状态机（方案B：32周期分步计算，避免组合逻辑过深）
//=============================================================================
// 状态定义
localparam BCD_IDLE       = 3'd0;
localparam BCD_CONV_32    = 3'd1;  // 32位→6位BCD
localparam BCD_CONV_16    = 3'd2;  // 16位→4位BCD
localparam BCD_WAIT       = 3'd3;  // 等待完成

reg [2:0] bcd_state;
reg [5:0] bcd_cnt;          // 迭代计数器（最大32）
reg [55:0] bcd_shift_32;    // 32位转换移位寄存器
reg [31:0] bcd_shift_16;    // 16位转换移位寄存器
reg [2:0] bcd_target;       // 转换目标寄存器标识

// 目标寄存器标识
localparam BCD_TGT_FREQ_MIN  = 3'd0;
localparam BCD_TGT_FREQ_MAX  = 3'd1;
localparam BCD_TGT_AMP_MIN   = 3'd2;
localparam BCD_TGT_AMP_MAX   = 3'd3;
localparam BCD_TGT_DUTY_MIN  = 3'd4;
localparam BCD_TGT_DUTY_MAX  = 3'd5;
localparam BCD_TGT_THD_MAX   = 3'd6;

// 触发信号和临时值寄存器
reg bcd_start_32, bcd_start_16;
reg [31:0] bcd_input_32;
reg [15:0] bcd_input_16;

// 恢复默认值标志（由参数调整逻辑设置，由BCD状态机处理）
reg bcd_restore_freq, bcd_restore_amp, bcd_restore_duty, bcd_restore_thd;

// BCD转换临时变量
reg [55:0] bcd_shift_temp_32;
reg [31:0] bcd_shift_temp_16;

// BCD转换状态机（负责所有BCD寄存器的更新）
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        bcd_state <= BCD_IDLE;
        bcd_cnt <= 6'd0;
        bcd_shift_32 <= 56'd0;
        bcd_shift_16 <= 32'd0;
        // 触发信号和目标寄存器由参数调整逻辑管理，这里不初始化
        
        // 复位BCD寄存器到默认值
        {freq_min_d5, freq_min_d4, freq_min_d3, freq_min_d2, freq_min_d1, freq_min_d0} <= 24'h095000;
        {freq_max_d5, freq_max_d4, freq_max_d3, freq_max_d2, freq_max_d1, freq_max_d0} <= 24'h105000;
        {amp_min_d3, amp_min_d2, amp_min_d1, amp_min_d0} <= 16'h2500;
        {amp_max_d3, amp_max_d2, amp_max_d1, amp_max_d0} <= 16'h3500;
        {duty_min_d3, duty_min_d2, duty_min_d1, duty_min_d0} <= 16'h0450;
        {duty_max_d3, duty_max_d2, duty_max_d1, duty_max_d0} <= 16'h0550;
        {thd_max_d3, thd_max_d2, thd_max_d1, thd_max_d0} <= 16'h0600;
    end else begin
        case (bcd_state)
            BCD_IDLE: begin
                // 处理恢复默认值请求（不清除标志，由参数调整逻辑负责）
                if (bcd_restore_freq) begin
                    {freq_min_d5, freq_min_d4, freq_min_d3, freq_min_d2, freq_min_d1, freq_min_d0} <= 24'h095000;
                    {freq_max_d5, freq_max_d4, freq_max_d3, freq_max_d2, freq_max_d1, freq_max_d0} <= 24'h105000;
                end else if (bcd_restore_amp) begin
                    {amp_min_d3, amp_min_d2, amp_min_d1, amp_min_d0} <= 16'h2500;
                    {amp_max_d3, amp_max_d2, amp_max_d1, amp_max_d0} <= 16'h3500;
                end else if (bcd_restore_duty) begin
                    {duty_min_d3, duty_min_d2, duty_min_d1, duty_min_d0} <= 16'h0450;
                    {duty_max_d3, duty_max_d2, duty_max_d1, duty_max_d0} <= 16'h0550;
                end else if (bcd_restore_thd) begin
                    {thd_max_d3, thd_max_d2, thd_max_d1, thd_max_d0} <= 16'h0600;
                end else if (bcd_start_32) begin
                    // 启动32位转BCD（不清除触发信号，由参数调整逻辑负责）
                    bcd_state <= BCD_CONV_32;
                    bcd_shift_32 <= {24'd0, bcd_input_32};
                    bcd_cnt <= 6'd0;
                end else if (bcd_start_16) begin
                    // 启动16位转BCD（不清除触发信号，由参数调整逻辑负责）
                    bcd_state <= BCD_CONV_16;
                    bcd_shift_16 <= {16'd0, bcd_input_16};
                    bcd_cnt <= 6'd0;
                end
            end
            
            BCD_CONV_32: begin
                // 每周期执行1次Double Dabble迭代
                // 先读取到临时变量
                bcd_shift_temp_32 = bcd_shift_32;
                
                // BCD调整：每一位>=5则+3（在移位前）
                if (bcd_shift_temp_32[35:32] >= 5) bcd_shift_temp_32[35:32] = bcd_shift_temp_32[35:32] + 3;
                if (bcd_shift_temp_32[39:36] >= 5) bcd_shift_temp_32[39:36] = bcd_shift_temp_32[39:36] + 3;
                if (bcd_shift_temp_32[43:40] >= 5) bcd_shift_temp_32[43:40] = bcd_shift_temp_32[43:40] + 3;
                if (bcd_shift_temp_32[47:44] >= 5) bcd_shift_temp_32[47:44] = bcd_shift_temp_32[47:44] + 3;
                if (bcd_shift_temp_32[51:48] >= 5) bcd_shift_temp_32[51:48] = bcd_shift_temp_32[51:48] + 3;
                if (bcd_shift_temp_32[55:52] >= 5) bcd_shift_temp_32[55:52] = bcd_shift_temp_32[55:52] + 3;
                
                bcd_cnt <= bcd_cnt + 1;
                
                if (bcd_cnt == 31) begin
                    // 最后一次迭代：不左移，直接提取BCD结果
                    bcd_state <= BCD_WAIT;
                    case (bcd_target)
                        BCD_TGT_FREQ_MIN: {freq_min_d5, freq_min_d4, freq_min_d3, freq_min_d2, freq_min_d1, freq_min_d0} <= bcd_shift_temp_32[55:32];
                        BCD_TGT_FREQ_MAX: {freq_max_d5, freq_max_d4, freq_max_d3, freq_max_d2, freq_max_d1, freq_max_d0} <= bcd_shift_temp_32[55:32];
                    endcase
                end else begin
                    // 左移1位（前31次迭代）
                    bcd_shift_32 <= bcd_shift_temp_32 << 1;
                end
            end
            
            BCD_CONV_16: begin
                // 每周期执行1次Double Dabble迭代（16位版本）
                // 先读取到临时变量
                bcd_shift_temp_16 = bcd_shift_16;
                
                if (bcd_shift_temp_16[19:16] >= 5) bcd_shift_temp_16[19:16] = bcd_shift_temp_16[19:16] + 3;
                if (bcd_shift_temp_16[23:20] >= 5) bcd_shift_temp_16[23:20] = bcd_shift_temp_16[23:20] + 3;
                if (bcd_shift_temp_16[27:24] >= 5) bcd_shift_temp_16[27:24] = bcd_shift_temp_16[27:24] + 3;
                if (bcd_shift_temp_16[31:28] >= 5) bcd_shift_temp_16[31:28] = bcd_shift_temp_16[31:28] + 3;
                
                // 左移1位
                bcd_shift_16 <= bcd_shift_temp_16 << 1;
                bcd_cnt <= bcd_cnt + 1;
                
                if (bcd_cnt == 15) begin
                    // 转换完成，更新目标寄存器
                    bcd_state <= BCD_WAIT;
                    case (bcd_target)
                        BCD_TGT_AMP_MIN:  {amp_min_d3, amp_min_d2, amp_min_d1, amp_min_d0} <= bcd_shift_temp_16[31:16];
                        BCD_TGT_AMP_MAX:  {amp_max_d3, amp_max_d2, amp_max_d1, amp_max_d0} <= bcd_shift_temp_16[31:16];
                        BCD_TGT_DUTY_MIN: {duty_min_d3, duty_min_d2, duty_min_d1, duty_min_d0} <= bcd_shift_temp_16[31:16];
                        BCD_TGT_DUTY_MAX: {duty_max_d3, duty_max_d2, duty_max_d1, duty_max_d0} <= bcd_shift_temp_16[31:16];
                        BCD_TGT_THD_MAX:  {thd_max_d3, thd_max_d2, thd_max_d1, thd_max_d0} <= bcd_shift_temp_16[31:16];
                    endcase
                end
            end
            
            BCD_WAIT: begin
                // 等待1个周期，防止立即重新触发
                bcd_state <= BCD_IDLE;
            end
            
            default: bcd_state <= BCD_IDLE;
        endcase
    end
end

//=============================================================================
// 步进值选择逻辑（方案D：添加寄存器降低fanout）
//=============================================================================
reg [31:0] freq_step_reg;
reg [15:0] amp_step_reg, duty_step_reg, thd_step_reg;

// 组合逻辑选择步进值
wire [31:0] freq_step;
wire [15:0] amp_step, duty_step, thd_step;

assign freq_step = (step_mode == 2'd0) ? FREQ_STEP_FINE :
                   (step_mode == 2'd1) ? FREQ_STEP_MID :
                   (step_mode == 2'd2) ? FREQ_STEP_COARSE : FREQ_STEP_FINE;

assign amp_step  = (step_mode == 2'd0) ? AMP_STEP_FINE :
                   (step_mode == 2'd1) ? AMP_STEP_MID :
                   (step_mode == 2'd2) ? AMP_STEP_COARSE : AMP_STEP_FINE;

assign duty_step = (step_mode == 2'd0) ? DUTY_STEP_FINE :
                   (step_mode == 2'd1) ? DUTY_STEP_MID :
                   (step_mode == 2'd2) ? DUTY_STEP_COARSE : DUTY_STEP_FINE;

assign thd_step  = (step_mode == 2'd0) ? THD_STEP_FINE :
                   (step_mode == 2'd1) ? THD_STEP_MID :
                   (step_mode == 2'd2) ? THD_STEP_COARSE : THD_STEP_FINE;

// 注册步进值，降低fanout（方案D优化）
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        freq_step_reg <= FREQ_STEP_FINE;
        amp_step_reg  <= AMP_STEP_FINE;
        duty_step_reg <= DUTY_STEP_FINE;
        thd_step_reg  <= THD_STEP_FINE;
    end else begin
        freq_step_reg <= freq_step;
        amp_step_reg  <= amp_step;
        duty_step_reg <= duty_step;
        thd_step_reg  <= thd_step;
    end
end

//=============================================================================
// 阈值配置逻辑（使用BCD转换状态机，避免组合逻辑过深）
//=============================================================================
// 临时变量用于存储新值
reg [31:0] freq_min_new, freq_max_new;
reg [15:0] amp_min_new, amp_max_new;
reg [15:0] duty_min_new, duty_max_new;
reg [15:0] thd_max_new;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        // 复位到默认值 - Binary
        freq_min <= FREQ_DEFAULT - FREQ_TOL_DEFAULT;
        freq_max <= FREQ_DEFAULT + FREQ_TOL_DEFAULT;
        amp_min  <= AMP_DEFAULT - AMP_TOL_DEFAULT;
        amp_max  <= AMP_DEFAULT + AMP_TOL_DEFAULT;
        duty_min <= DUTY_DEFAULT - DUTY_TOL_DEFAULT;
        duty_max <= DUTY_DEFAULT + DUTY_TOL_DEFAULT;
        thd_max  <= THD_MAX_DEFAULT;
        
        // 恢复标志复位
        bcd_restore_freq <= 1'b0;
        bcd_restore_amp <= 1'b0;
        bcd_restore_duty <= 1'b0;
        bcd_restore_thd <= 1'b0;
        
        // BCD触发信号复位
        bcd_start_32 <= 1'b0;
        bcd_start_16 <= 1'b0;
        bcd_target <= 3'd0;
        
        // BCD寄存器由BCD状态机复位
        
    end else if (test_enable && bcd_state == BCD_IDLE) begin  // 只在BCD空闲时处理按键
        // 恢复默认值（设置标志，由BCD状态机处理）
        if (btn_reset_default) begin
            case (adjust_mode)
                ADJUST_FREQ: begin
                    freq_min <= FREQ_DEFAULT - FREQ_TOL_DEFAULT;
                    freq_max <= FREQ_DEFAULT + FREQ_TOL_DEFAULT;
                    bcd_restore_freq <= 1'b1;
                end
                ADJUST_AMP: begin
                    amp_min <= AMP_DEFAULT - AMP_TOL_DEFAULT;
                    amp_max <= AMP_DEFAULT + AMP_TOL_DEFAULT;
                    bcd_restore_amp <= 1'b1;
                end
                ADJUST_DUTY: begin
                    duty_min <= DUTY_DEFAULT - DUTY_TOL_DEFAULT;
                    duty_max <= DUTY_DEFAULT + DUTY_TOL_DEFAULT;
                    bcd_restore_duty <= 1'b1;
                end
                ADJUST_THD: begin
                    thd_max <= THD_MAX_DEFAULT;
                    bcd_restore_thd <= 1'b1;
                end
            endcase
        end else begin
            // 清除所有恢复标志（单周期脉冲）
            bcd_restore_freq <= 1'b0;
            bcd_restore_amp <= 1'b0;
            bcd_restore_duty <= 1'b0;
            bcd_restore_thd <= 1'b0;
            
            // 清除BCD触发信号（单周期脉冲）
            bcd_start_32 <= 1'b0;
            bcd_start_16 <= 1'b0;
            
            // 根据当前调整模式调整对应参数（使用freq_step_reg降低fanout）
            case (adjust_mode)
                ADJUST_FREQ: begin
                    // 频率下限调整
                    if (btn_limit_dn_dn && freq_min >= freq_step_reg) begin
                        freq_min_new = freq_min - freq_step_reg;
                        freq_min <= freq_min_new;
                        // 触发BCD转换状态机
                        bcd_input_32 <= freq_min_new;
                        bcd_target <= BCD_TGT_FREQ_MIN;
                        bcd_start_32 <= 1'b1;
                    end else if (btn_limit_dn_up && freq_min + freq_step_reg < freq_max) begin
                        freq_min_new = freq_min + freq_step_reg;
                        freq_min <= freq_min_new;
                        // 触发BCD转换状态机
                        bcd_input_32 <= freq_min_new;
                        bcd_target <= BCD_TGT_FREQ_MIN;
                        bcd_start_32 <= 1'b1;
                    end
                    
                    // 频率上限调整
                    if (btn_limit_up_dn && freq_max > freq_min + freq_step_reg) begin
                        freq_max_new = freq_max - freq_step_reg;
                        freq_max <= freq_max_new;
                        // 触发BCD转换状态机
                        bcd_input_32 <= freq_max_new;
                        bcd_target <= BCD_TGT_FREQ_MAX;
                        bcd_start_32 <= 1'b1;
                    end else if (btn_limit_up_up && freq_max + freq_step_reg < 32'd500000) begin  // 最大500kHz
                        freq_max_new = freq_max + freq_step_reg;
                        freq_max <= freq_max_new;
                        // 触发BCD转换状态机
                        bcd_input_32 <= freq_max_new;
                        bcd_target <= BCD_TGT_FREQ_MAX;
                        bcd_start_32 <= 1'b1;
                    end
                end
                
                ADJUST_AMP: begin
                    // 幅度下限调整（使用amp_step_reg降低fanout）
                    if (btn_limit_dn_dn && amp_min >= amp_step_reg) begin
                        amp_min_new = amp_min - amp_step_reg;
                        amp_min <= amp_min_new;
                        bcd_input_16 <= amp_min_new;
                        bcd_target <= BCD_TGT_AMP_MIN;
                        bcd_start_16 <= 1'b1;
                    end else if (btn_limit_dn_up && amp_min + amp_step_reg < amp_max) begin
                        amp_min_new = amp_min + amp_step_reg;
                        amp_min <= amp_min_new;
                        bcd_input_16 <= amp_min_new;
                        bcd_target <= BCD_TGT_AMP_MIN;
                        bcd_start_16 <= 1'b1;
                    end
                    
                    // 幅度上限调整
                    if (btn_limit_up_dn && amp_max > amp_min + amp_step_reg) begin
                        amp_max_new = amp_max - amp_step_reg;
                        amp_max <= amp_max_new;
                        bcd_input_16 <= amp_max_new;
                        bcd_target <= BCD_TGT_AMP_MAX;
                        bcd_start_16 <= 1'b1;
                    end else if (btn_limit_up_up && amp_max + amp_step_reg < 16'd5000) begin  // 最大5V
                        amp_max_new = amp_max + amp_step_reg;
                        amp_max <= amp_max_new;
                        bcd_input_16 <= amp_max_new;
                        bcd_target <= BCD_TGT_AMP_MAX;
                        bcd_start_16 <= 1'b1;
                    end
                end
                
                ADJUST_DUTY: begin
                    // 占空比下限调整（使用duty_step_reg降低fanout）
                    if (btn_limit_dn_dn && duty_min >= duty_step_reg) begin
                        duty_min_new = duty_min - duty_step_reg;
                        duty_min <= duty_min_new;
                        bcd_input_16 <= duty_min_new;
                        bcd_target <= BCD_TGT_DUTY_MIN;
                        bcd_start_16 <= 1'b1;
                    end else if (btn_limit_dn_up && duty_min + duty_step_reg < duty_max) begin
                        duty_min_new = duty_min + duty_step_reg;
                        duty_min <= duty_min_new;
                        bcd_input_16 <= duty_min_new;
                        bcd_target <= BCD_TGT_DUTY_MIN;
                        bcd_start_16 <= 1'b1;
                    end
                    
                    // 占空比上限调整
                    if (btn_limit_up_dn && duty_max > duty_min + duty_step_reg) begin
                        duty_max_new = duty_max - duty_step_reg;
                        duty_max <= duty_max_new;
                        bcd_input_16 <= duty_max_new;
                        bcd_target <= BCD_TGT_DUTY_MAX;
                        bcd_start_16 <= 1'b1;
                    end else if (btn_limit_up_up && duty_max + duty_step_reg < 16'd1000) begin  // 最大100%
                        duty_max_new = duty_max + duty_step_reg;
                        duty_max <= duty_max_new;
                        bcd_input_16 <= duty_max_new;
                        bcd_target <= BCD_TGT_DUTY_MAX;
                        bcd_start_16 <= 1'b1;
                    end
                end
                
                ADJUST_THD: begin
                    // THD只有上限，使用上限按键调整（使用thd_step_reg降低fanout）
                    if (btn_limit_up_dn && thd_max >= thd_step_reg) begin
                        thd_max_new = thd_max - thd_step_reg;
                        thd_max <= thd_max_new;
                        bcd_input_16 <= thd_max_new;
                        bcd_target <= BCD_TGT_THD_MAX;
                        bcd_start_16 <= 1'b1;
                    end else if (btn_limit_up_up && thd_max + thd_step_reg < 16'd1000) begin  // 最大100%
                        thd_max_new = thd_max + thd_step_reg;
                        thd_max <= thd_max_new;
                        bcd_input_16 <= thd_max_new;
                        bcd_target <= BCD_TGT_THD_MAX;
                        bcd_start_16 <= 1'b1;
                    end
                end
            endcase
        end
    end
end

// 输出到HDMI显示（Binary格式用于测试）
assign freq_min_out = freq_min;
assign freq_max_out = freq_max;
assign amp_min_out  = amp_min;
assign amp_max_out  = amp_max;
assign duty_min_out = duty_min;
assign duty_max_out = duty_max;
assign thd_max_out  = thd_max;

//=============================================================================
// 测试逻辑
//=============================================================================
reg freq_pass;              // 频率测试通过
reg amp_pass;               // 幅度测试通过
reg duty_pass;              // 占空比测试通过
reg thd_pass;               // THD测试通过
reg phase_pass;             // 相位差测试通过
reg all_pass;               // 全部测试通过

// 测试运行指示闪烁计数器
reg [25:0] blink_cnt;
reg blink_1hz;

// 1Hz闪烁生成（100MHz时钟，计数50M次=0.5s）
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        blink_cnt <= 26'd0;
        blink_1hz <= 1'b0;
    end else if (test_enable) begin
        if (blink_cnt >= 26'd49_999_999) begin  // 50M-1
            blink_cnt <= 26'd0;
            blink_1hz <= ~blink_1hz;  // 翻转，产生1Hz方波
        end else begin
            blink_cnt <= blink_cnt + 26'd1;
        end
    end else begin
        blink_cnt <= 26'd0;
        blink_1hz <= 1'b0;
    end
end

// 参数判断逻辑
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        freq_pass   <= 1'b0;
        amp_pass    <= 1'b0;
        duty_pass   <= 1'b0;
        thd_pass    <= 1'b0;
        phase_pass  <= 1'b0;
        all_pass    <= 1'b0;
    end else if (test_enable && param_valid) begin
        // 1. 频率测试
        freq_pass <= (freq >= freq_min) && (freq <= freq_max);
        
        // 2. 幅度测试
        amp_pass <= (amplitude >= amp_min) && (amplitude <= amp_max);
        
        // 3. 占空比测试
        duty_pass <= (duty >= duty_min) && (duty <= duty_max);
        
        // 4. THD测试（只有上限）
        thd_pass <= (thd <= thd_max);
        
        // 5. 相位差测试（暂不使用，默认通过）
        phase_pass <= 1'b1;
        
        // 6. 综合判断
        all_pass <= freq_pass && amp_pass && duty_pass && thd_pass;
    end else if (!test_enable) begin
        // 退出测试模式时清零
        freq_pass   <= 1'b0;
        amp_pass    <= 1'b0;
        duty_pass   <= 1'b0;
        thd_pass    <= 1'b0;
        phase_pass  <= 1'b0;
        all_pass    <= 1'b0;
    end
end

//=============================================================================
// BCD输出assign
//=============================================================================
assign freq_min_d0_out = freq_min_d0;
assign freq_min_d1_out = freq_min_d1;
assign freq_min_d2_out = freq_min_d2;
assign freq_min_d3_out = freq_min_d3;
assign freq_min_d4_out = freq_min_d4;
assign freq_min_d5_out = freq_min_d5;

assign freq_max_d0_out = freq_max_d0;
assign freq_max_d1_out = freq_max_d1;
assign freq_max_d2_out = freq_max_d2;
assign freq_max_d3_out = freq_max_d3;
assign freq_max_d4_out = freq_max_d4;
assign freq_max_d5_out = freq_max_d5;

assign amp_min_d0_out = amp_min_d0;
assign amp_min_d1_out = amp_min_d1;
assign amp_min_d2_out = amp_min_d2;
assign amp_min_d3_out = amp_min_d3;

assign amp_max_d0_out = amp_max_d0;
assign amp_max_d1_out = amp_max_d1;
assign amp_max_d2_out = amp_max_d2;
assign amp_max_d3_out = amp_max_d3;

assign duty_min_d0_out = duty_min_d0;
assign duty_min_d1_out = duty_min_d1;
assign duty_min_d2_out = duty_min_d2;
assign duty_min_d3_out = duty_min_d3;

assign duty_max_d0_out = duty_max_d0;
assign duty_max_d1_out = duty_max_d1;
assign duty_max_d2_out = duty_max_d2;
assign duty_max_d3_out = duty_max_d3;

assign thd_max_d0_out = thd_max_d0;
assign thd_max_d1_out = thd_max_d1;
assign thd_max_d2_out = thd_max_d2;
assign thd_max_d3_out = thd_max_d3;

//=============================================================================
// LED输出映射
//=============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        test_result <= 8'h00;
    end else begin
        test_result[0] <= freq_pass;        // 频率合格指示
        test_result[1] <= amp_pass;         // 幅度合格指示
        test_result[2] <= duty_pass;        // 占空比合格指示
        test_result[3] <= thd_pass;         // THD合格指示
        test_result[4] <= phase_pass;       // 相位差合格指示
        test_result[5] <= all_pass;         // 综合合格指示（重要）
        test_result[6] <= blink_1hz && test_enable;  // 测试运行闪烁
        test_result[7] <= test_enable;      // 测试模式激活
    end
end

endmodule
