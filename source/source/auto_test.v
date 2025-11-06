//=============================================================================
// 文件名: auto_test.v
// 描述: 自动测试模块 - 参数阈值判断与LED指示
//       根据测试要求判断各参数是否合格，通过LED反馈结果
// 新增功能：
//   - 按键可调整阈值（频率、幅度、占空比、THD）
//   - LED实时显示测试结果
//   - 支持阈值保存和恢复
//=============================================================================

module auto_test (
    input  wire         clk,
    input  wire         rst_n,
    
    // 测试控制
    input  wire         test_enable,        // 测试使能（对应test_mode）
    
    // 参数输入
    input  wire [15:0]  freq,               // 频率 (Hz)
    input  wire [15:0]  amplitude,          // 幅度
    input  wire [15:0]  duty,               // 占空比 (0-1000 = 0-100%)
    input  wire [15:0]  thd,                // THD (0-1000 = 0-100%)
    input  wire [15:0]  phase_diff,         // 相位差 (0-3599 = 0-359.9°)
    input  wire         param_valid,        // 参数有效标志
    
    // 阈值配置按键（在测试模式下复用）
    input  wire         btn_freq_up,        // 频率上限增加
    input  wire         btn_freq_dn,        // 频率上限减少
    input  wire         btn_amp_up,         // 幅度上限增加
    input  wire         btn_amp_dn,         // 幅度下限减少
    input  wire         btn_duty_up,        // 占空比容差增加
    input  wire         btn_thd_adjust,     // THD阈值调整
    
    // 测试结果输出 (LED映射)
    output reg [7:0]    test_result         // 8位LED指示
    // Bit[0]: 频率测试结果 (1=合格, 0=不合格)
    // Bit[1]: 幅度测试结果
    // Bit[2]: 占空比测试结果
    // Bit[3]: THD测试结果
    // Bit[4]: 相位差测试结果
    // Bit[5]: 综合测试结果 (全部合格时为1)
    // Bit[6]: 测试运行指示 (闪烁)
    // Bit[7]: 测试模式激活指示
);

//=============================================================================
// 测试阈值定义（可通过按键调整）
//=============================================================================
// 默认阈值（可在运行时通过按键修改）
reg [15:0] freq_target;         // 目标频率
reg [15:0] freq_tolerance;      // 频率容差
reg [15:0] amp_min;             // 幅度下限
reg [15:0] amp_max;             // 幅度上限
reg [15:0] duty_target;         // 目标占空比
reg [15:0] duty_tolerance;      // 占空比容差
reg [15:0] thd_max;             // THD上限
reg [15:0] phase_tolerance;     // 相位差容差

// 初始默认值
localparam FREQ_TARGET_DEFAULT  = 16'd1000;     // 默认1kHz
localparam FREQ_TOL_DEFAULT     = 16'd50;       // ±50Hz
localparam AMP_MIN_DEFAULT      = 16'd500;      // 0.5V
localparam AMP_MAX_DEFAULT      = 16'd4000;     // 4V
localparam DUTY_TARGET_DEFAULT  = 16'd500;      // 50%
localparam DUTY_TOL_DEFAULT     = 16'd50;       // ±5%
localparam THD_MAX_DEFAULT      = 16'd50;       // 5%
localparam PHASE_TOL_DEFAULT    = 16'd100;      // ±10°

// 调整步长
localparam FREQ_STEP            = 16'd10;       // 频率调整10Hz
localparam AMP_STEP             = 16'd100;      // 幅度调整0.1V
localparam DUTY_STEP            = 16'd10;       // 占空比调整1%
localparam THD_STEP             = 16'd5;        // THD调整0.5%

//=============================================================================
// 阈值配置逻辑（按键调整）
//=============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        // 复位到默认值
        freq_target     <= FREQ_TARGET_DEFAULT;
        freq_tolerance  <= FREQ_TOL_DEFAULT;
        amp_min         <= AMP_MIN_DEFAULT;
        amp_max         <= AMP_MAX_DEFAULT;
        duty_target     <= DUTY_TARGET_DEFAULT;
        duty_tolerance  <= DUTY_TOL_DEFAULT;
        thd_max         <= THD_MAX_DEFAULT;
        phase_tolerance <= PHASE_TOL_DEFAULT;
    end else if (test_enable) begin
        // 频率目标调整
        if (btn_freq_up && freq_target < 16'd20000)  // 最大20kHz
            freq_target <= freq_target + FREQ_STEP;
        else if (btn_freq_dn && freq_target > FREQ_STEP)
            freq_target <= freq_target - FREQ_STEP;
        
        // 幅度范围调整
        if (btn_amp_up && amp_max < 16'd5000)  // 最大5V
            amp_max <= amp_max + AMP_STEP;
        else if (btn_amp_dn && amp_min > AMP_STEP)
            amp_min <= amp_min - AMP_STEP;
        
        // 占空比容差调整
        if (btn_duty_up && duty_tolerance < 16'd200)  // 最大±20%
            duty_tolerance <= duty_tolerance + DUTY_STEP;
        
        // THD阈值调整
        if (btn_thd_adjust) begin
            if (thd_max == 16'd50)
                thd_max <= 16'd100;  // 切换到10%
            else if (thd_max == 16'd100)
                thd_max <= 16'd30;   // 切换到3%
            else
                thd_max <= 16'd50;   // 切换回5%
        end
    end
end

//=============================================================================
// 阈值边界计算
//=============================================================================
wire [15:0] freq_min;
wire [15:0] freq_max;
wire [15:0] duty_min;
wire [15:0] duty_max;

assign freq_min = (freq_target > freq_tolerance) ? (freq_target - freq_tolerance) : 16'd0;
assign freq_max = freq_target + freq_tolerance;
assign duty_min = (duty_target > duty_tolerance) ? (duty_target - duty_tolerance) : 16'd0;
assign duty_max = (duty_target + duty_tolerance > 16'd1000) ? 16'd1000 : (duty_target + duty_tolerance);

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
wire blink_1hz;
assign blink_1hz = (blink_cnt >= 26'd50_000_000);  // 假设clk=100MHz

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        blink_cnt <= 26'd0;
    else if (test_enable) begin
        if (blink_1hz)
            blink_cnt <= 26'd0;
        else
            blink_cnt <= blink_cnt + 26'd1;
    end else
        blink_cnt <= 26'd0;
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
        // 1. 频率测试（使用可配置阈值）
        freq_pass <= (freq >= freq_min) && (freq <= freq_max);
        
        // 2. 幅度测试（使用可配置范围）
        amp_pass <= (amplitude >= amp_min) && (amplitude <= amp_max);
        
        // 3. 占空比测试（使用可配置目标和容差）
        duty_pass <= (duty >= duty_min) && (duty <= duty_max);
        
        // 4. THD测试（使用可配置上限）
        thd_pass <= (thd <= thd_max);
        
        // 5. 相位差测试（同相或反相都算合格）
        // 同相: 0°±tolerance
        // 反相: 180°±tolerance
        phase_pass <= ((phase_diff <= phase_tolerance) || 
                       (phase_diff >= (16'd3600 - phase_tolerance)) ||
                       ((phase_diff >= (16'd1800 - phase_tolerance)) && 
                        (phase_diff <= (16'd1800 + phase_tolerance))));
        
        // 6. 综合判断
        all_pass <= freq_pass && amp_pass && duty_pass && thd_pass && phase_pass;
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
