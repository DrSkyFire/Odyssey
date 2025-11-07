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
    
    // HDMI显示接口
    output wire [31:0]  freq_min_out,       // 频率下限 (Hz)
    output wire [31:0]  freq_max_out,       // 频率上限 (Hz)
    output wire [15:0]  amp_min_out,        // 幅度下限
    output wire [15:0]  amp_max_out,        // 幅度上限
    output wire [15:0]  duty_min_out,       // 占空比下限
    output wire [15:0]  duty_max_out,       // 占空比上限
    output wire [15:0]  thd_max_out         // THD上限
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
// 测试阈值寄存器（上下限独立可调）
//=============================================================================
reg [31:0] freq_min;            // 频率下限 (Hz，32位)
reg [31:0] freq_max;            // 频率上限 (Hz，32位)
reg [15:0] amp_min;             // 幅度下限
reg [15:0] amp_max;             // 幅度上限
reg [15:0] duty_min;            // 占空比下限
reg [15:0] duty_max;            // 占空比上限
reg [15:0] thd_max;             // THD上限（无下限）

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
// 步进值选择逻辑
//=============================================================================
reg [31:0] freq_step;
reg [15:0] amp_step, duty_step, thd_step;

always @(*) begin
    case (step_mode)
        2'd0: begin  // 细调
            freq_step = FREQ_STEP_FINE;
            amp_step  = AMP_STEP_FINE;
            duty_step = DUTY_STEP_FINE;
            thd_step  = THD_STEP_FINE;
        end
        2'd1: begin  // 中调
            freq_step = FREQ_STEP_MID;
            amp_step  = AMP_STEP_MID;
            duty_step = DUTY_STEP_MID;
            thd_step  = THD_STEP_MID;
        end
        2'd2: begin  // 粗调
            freq_step = FREQ_STEP_COARSE;
            amp_step  = AMP_STEP_COARSE;
            duty_step = DUTY_STEP_COARSE;
            thd_step  = THD_STEP_COARSE;
        end
        default: begin
            freq_step = FREQ_STEP_FINE;
            amp_step  = AMP_STEP_FINE;
            duty_step = DUTY_STEP_FINE;
            thd_step  = THD_STEP_FINE;
        end
    endcase
end

//=============================================================================
// 阈值配置逻辑（层级化按键调整）
//=============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        // 复位到默认值
        freq_min <= FREQ_DEFAULT - FREQ_TOL_DEFAULT;
        freq_max <= FREQ_DEFAULT + FREQ_TOL_DEFAULT;
        amp_min  <= AMP_DEFAULT - AMP_TOL_DEFAULT;
        amp_max  <= AMP_DEFAULT + AMP_TOL_DEFAULT;
        duty_min <= DUTY_DEFAULT - DUTY_TOL_DEFAULT;
        duty_max <= DUTY_DEFAULT + DUTY_TOL_DEFAULT;
        thd_max  <= THD_MAX_DEFAULT;
    end else if (test_enable) begin
        // 恢复默认值
        if (btn_reset_default) begin
            case (adjust_mode)
                ADJUST_FREQ: begin
                    freq_min <= FREQ_DEFAULT - FREQ_TOL_DEFAULT;
                    freq_max <= FREQ_DEFAULT + FREQ_TOL_DEFAULT;
                end
                ADJUST_AMP: begin
                    amp_min <= AMP_DEFAULT - AMP_TOL_DEFAULT;
                    amp_max <= AMP_DEFAULT + AMP_TOL_DEFAULT;
                end
                ADJUST_DUTY: begin
                    duty_min <= DUTY_DEFAULT - DUTY_TOL_DEFAULT;
                    duty_max <= DUTY_DEFAULT + DUTY_TOL_DEFAULT;
                end
                ADJUST_THD: begin
                    thd_max <= THD_MAX_DEFAULT;
                end
            endcase
        end else begin
            // 根据当前调整模式调整对应参数
            case (adjust_mode)
                ADJUST_FREQ: begin
                    // 频率下限调整
                    if (btn_limit_dn_dn && freq_min >= freq_step)
                        freq_min <= freq_min - freq_step;
                    else if (btn_limit_dn_up && freq_min + freq_step < freq_max)
                        freq_min <= freq_min + freq_step;
                    
                    // 频率上限调整
                    if (btn_limit_up_dn && freq_max > freq_min + freq_step)
                        freq_max <= freq_max - freq_step;
                    else if (btn_limit_up_up && freq_max + freq_step < 32'd500000)  // 最大500kHz
                        freq_max <= freq_max + freq_step;
                end
                
                ADJUST_AMP: begin
                    // 幅度下限调整
                    if (btn_limit_dn_dn && amp_min >= amp_step)
                        amp_min <= amp_min - amp_step;
                    else if (btn_limit_dn_up && amp_min + amp_step < amp_max)
                        amp_min <= amp_min + amp_step;
                    
                    // 幅度上限调整
                    if (btn_limit_up_dn && amp_max > amp_min + amp_step)
                        amp_max <= amp_max - amp_step;
                    else if (btn_limit_up_up && amp_max + amp_step < 16'd5000)  // 最大5V
                        amp_max <= amp_max + amp_step;
                end
                
                ADJUST_DUTY: begin
                    // 占空比下限调整
                    if (btn_limit_dn_dn && duty_min >= duty_step)
                        duty_min <= duty_min - duty_step;
                    else if (btn_limit_dn_up && duty_min + duty_step < duty_max)
                        duty_min <= duty_min + duty_step;
                    
                    // 占空比上限调整
                    if (btn_limit_up_dn && duty_max > duty_min + duty_step)
                        duty_max <= duty_max - duty_step;
                    else if (btn_limit_up_up && duty_max + duty_step < 16'd1000)  // 最大100%
                        duty_max <= duty_max + duty_step;
                end
                
                ADJUST_THD: begin
                    // THD只有上限，使用上限按键调整
                    if (btn_limit_up_dn && thd_max >= thd_step)
                        thd_max <= thd_max - thd_step;
                    else if (btn_limit_up_up && thd_max + thd_step < 16'd1000)  // 最大100%
                        thd_max <= thd_max + thd_step;
                end
            endcase
        end
    end
end

// 输出到HDMI显示
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
