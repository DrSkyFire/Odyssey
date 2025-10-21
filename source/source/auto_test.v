//=============================================================================
// 文件名: auto_test.v
// 描述: 自动测试模块 - 参数阈值判断与LED指示
//       根据测试要求判断各参数是否合格，通过LED反馈结果
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
// 测试阈值定义（根据实际需求调整）
//=============================================================================
// 频率测试：目标10Hz，容差±1Hz
localparam FREQ_TARGET      = 16'd10;       // 目标频率 10Hz
localparam FREQ_TOL         = 16'd1;        // 容差 ±1Hz
localparam FREQ_MIN         = FREQ_TARGET - FREQ_TOL;
localparam FREQ_MAX         = FREQ_TARGET + FREQ_TOL;

// 幅度测试：范围 500-4000 (对应ADC 0.5V-4V)
localparam AMP_MIN          = 16'd500;
localparam AMP_MAX          = 16'd4000;

// 占空比测试：目标50%，容差±5% (对应 450-550)
localparam DUTY_TARGET      = 16'd500;
localparam DUTY_TOL         = 16'd50;
localparam DUTY_MIN         = DUTY_TARGET - DUTY_TOL;
localparam DUTY_MAX         = DUTY_TARGET + DUTY_TOL;

// THD测试：要求<5% (对应值<50)
localparam THD_MAX          = 16'd50;       // 5.0%

// 相位差测试：双通道同步信号相位差应接近0° 或180°
// 容差±10° (对应 0-100 或 1700-1900 或 3500-3599)
localparam PHASE_SYNC_TOL   = 16'd100;      // ±10°容差
localparam PHASE_180        = 16'd1800;     // 180°

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
        // 1. 频率测试
        freq_pass <= (freq >= FREQ_MIN) && (freq <= FREQ_MAX);
        
        // 2. 幅度测试
        amp_pass <= (amplitude >= AMP_MIN) && (amplitude <= AMP_MAX);
        
        // 3. 占空比测试
        duty_pass <= (duty >= DUTY_MIN) && (duty <= DUTY_MAX);
        
        // 4. THD测试
        thd_pass <= (thd <= THD_MAX);
        
        // 5. 相位差测试（同相或反相都算合格）
        // 同相: 0°±10° (0-100 或 3500-3599)
        // 反相: 180°±10° (1700-1900)
        phase_pass <= ((phase_diff <= PHASE_SYNC_TOL) || 
                       (phase_diff >= (16'd3600 - PHASE_SYNC_TOL)) ||
                       ((phase_diff >= (PHASE_180 - PHASE_SYNC_TOL)) && 
                        (phase_diff <= (PHASE_180 + PHASE_SYNC_TOL))));
        
        // 6. 综合判断
        all_pass <= freq_pass && amp_pass && duty_pass && thd_pass && phase_pass;
    end else begin
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
