//=============================================================================
// 文件名: tb_phase_diff_calc_v4.v
// 描述: 相位差计算模块v4的testbench
// 功能: 验证CORDIC算法和相位差计算的精度
//=============================================================================

`timescale 1ns / 1ps

module tb_phase_diff_calc_v4;

//=============================================================================
// 参数定义
//=============================================================================
parameter CLK_PERIOD = 10;  // 100MHz时钟，10ns周期

//=============================================================================
// 信号定义
//=============================================================================
reg                 clk;
reg                 rst_n;

// 输入信号
reg signed [15:0]   ch1_re;
reg signed [15:0]   ch1_im;
reg                 ch1_valid;

reg signed [15:0]   ch2_re;
reg signed [15:0]   ch2_im;
reg                 ch2_valid;

reg                 enable;
reg [3:0]           smooth_factor;

// 输出信号
wire signed [15:0]  phase_diff;
wire                phase_valid;
wire [7:0]          phase_confidence;

// 测试变量
integer             test_case;
real                expected_phase;
real                measured_phase;
real                error;

//=============================================================================
// 时钟生成
//=============================================================================
initial begin
    clk = 0;
    forever #(CLK_PERIOD/2) clk = ~clk;
end

//=============================================================================
// DUT例化
//=============================================================================
phase_diff_calc_v4 u_dut (
    .clk                (clk),
    .rst_n              (rst_n),
    .ch1_re             (ch1_re),
    .ch1_im             (ch1_im),
    .ch1_valid          (ch1_valid),
    .ch2_re             (ch2_re),
    .ch2_im             (ch2_im),
    .ch2_valid          (ch2_valid),
    .enable             (enable),
    .smooth_factor      (smooth_factor),
    .phase_diff         (phase_diff),
    .phase_valid        (phase_valid),
    .phase_confidence   (phase_confidence)
);

//=============================================================================
// 测试任务：生成指定相位差的复数信号
// phase_deg: 期望的相位差（度）
//=============================================================================
task test_phase_diff;
    input real phase1_deg;  // 通道1的相位（度）
    input real phase2_deg;  // 通道2的相位（度）
    input real amplitude;   // 信号幅度
    
    real phase1_rad;
    real phase2_rad;
    real expected_diff;
    
    begin
        // 转换为弧度
        phase1_rad = phase1_deg * 3.14159265 / 180.0;
        phase2_rad = phase2_deg * 3.14159265 / 180.0;
        
        // 生成通道1复数（极坐标 → 直角坐标）
        ch1_re = $rtoi(amplitude * $cos(phase1_rad));
        ch1_im = $rtoi(amplitude * $sin(phase1_rad));
        ch1_valid = 1'b1;
        
        // 生成通道2复数
        ch2_re = $rtoi(amplitude * $cos(phase2_rad));
        ch2_im = $rtoi(amplitude * $sin(phase2_rad));
        ch2_valid = 1'b1;
        
        // 计算期望的相位差
        expected_diff = phase2_deg - phase1_deg;
        if (expected_diff > 180.0)
            expected_diff = expected_diff - 360.0;
        else if (expected_diff < -180.0)
            expected_diff = expected_diff + 360.0;
        
        expected_phase = expected_diff;
        
        $display("[TEST] CH1: phase=%.1f°, CH2: phase=%.1f°, Expected diff=%.1f°",
                 phase1_deg, phase2_deg, expected_diff);
        
        // 等待一个周期
        @(posedge clk);
        ch1_valid = 1'b0;
        ch2_valid = 1'b0;
        
        // 等待输出有效
        wait(phase_valid);
        @(posedge clk);
        
        // 计算实际测量值
        measured_phase = $itor(phase_diff) / 10.0;
        error = measured_phase - expected_diff;
        
        // 处理回绕误差
        if (error > 180.0)
            error = error - 360.0;
        else if (error < -180.0)
            error = error + 360.0;
        
        // 输出结果
        $display("[RESULT] Measured=%.2f°, Error=%.3f°, Confidence=%0d/255",
                 measured_phase, error, phase_confidence);
        
        if (error < 0.2 && error > -0.2) begin
            $display("[PASS] ✓ Error within ±0.2°\n");
        end else begin
            $display("[FAIL] ✗ Error exceeds ±0.2°\n");
        end
        
        // 等待一段时间
        repeat(10) @(posedge clk);
    end
endtask

//=============================================================================
// 测试序列
//=============================================================================
initial begin
    $display("========================================");
    $display(" Phase Diff Calc v4 Testbench");
    $display(" Target Accuracy: ±0.2°");
    $display("========================================\n");
    
    // 初始化
    rst_n = 0;
    enable = 0;
    ch1_re = 0;
    ch1_im = 0;
    ch1_valid = 0;
    ch2_re = 0;
    ch2_im = 0;
    ch2_valid = 0;
    smooth_factor = 4'd0;  // 无滤波，测试原始精度
    test_case = 0;
    
    // 复位
    repeat(10) @(posedge clk);
    rst_n = 1;
    enable = 1;
    repeat(5) @(posedge clk);
    
    //=========================================================================
    // 测试用例1：基本相位差测试（0° ~ 180°）
    //=========================================================================
    $display("========================================");
    $display(" Test Case 1: Basic Phase Differences");
    $display("========================================");
    
    test_case = 1;
    test_phase_diff(0.0, 0.0, 10000);      // 0°
    test_phase_diff(0.0, 45.0, 10000);     // 45°
    test_phase_diff(0.0, 90.0, 10000);     // 90°
    test_phase_diff(0.0, 135.0, 10000);    // 135°
    test_phase_diff(0.0, 180.0, 10000);    // 180°
    
    //=========================================================================
    // 测试用例2：负相位差测试
    //=========================================================================
    $display("========================================");
    $display(" Test Case 2: Negative Phase Differences");
    $display("========================================");
    
    test_case = 2;
    test_phase_diff(0.0, -45.0, 10000);    // -45°
    test_phase_diff(0.0, -90.0, 10000);    // -90°
    test_phase_diff(0.0, -135.0, 10000);   // -135°
    test_phase_diff(45.0, -45.0, 10000);   // -90°（跨象限）
    
    //=========================================================================
    // 测试用例3：相位回绕测试
    //=========================================================================
    $display("========================================");
    $display(" Test Case 3: Phase Wrap-around");
    $display("========================================");
    
    test_case = 3;
    test_phase_diff(170.0, -170.0, 10000);  // 应该是+20°（不是-340°）
    test_phase_diff(-170.0, 170.0, 10000);  // 应该是-20°（不是+340°）
    test_phase_diff(10.0, 350.0, 10000);    // 应该是-20°
    
    //=========================================================================
    // 测试用例4：小幅度信号测试
    //=========================================================================
    $display("========================================");
    $display(" Test Case 4: Low Amplitude Signals");
    $display("========================================");
    
    test_case = 4;
    test_phase_diff(0.0, 45.0, 1000);      // 幅度降低10倍
    test_phase_diff(0.0, 90.0, 100);       // 幅度降低100倍
    
    //=========================================================================
    // 测试用例5：精细角度测试
    //=========================================================================
    $display("========================================");
    $display(" Test Case 5: Fine Angle Resolution");
    $display("========================================");
    
    test_case = 5;
    test_phase_diff(0.0, 0.5, 10000);      // 0.5°
    test_phase_diff(0.0, 1.0, 10000);      // 1.0°
    test_phase_diff(0.0, 5.0, 10000);      // 5.0°
    test_phase_diff(0.0, 10.3, 10000);     // 10.3°
    
    //=========================================================================
    // 测试用例6：IIR滤波测试
    //=========================================================================
    $display("========================================");
    $display(" Test Case 6: IIR Smoothing");
    $display("========================================");
    
    test_case = 6;
    smooth_factor = 4'd8;  // 启用中等滤波
    
    // 连续输入相同的相位差，观察收敛
    $display("Sending 10 identical samples with phase diff = 60°...");
    repeat(10) begin
        test_phase_diff(0.0, 60.0, 10000);
    end
    
    //=========================================================================
    // 测试完成
    //=========================================================================
    repeat(100) @(posedge clk);
    
    $display("========================================");
    $display(" All Tests Completed!");
    $display("========================================");
    $finish;
end

//=============================================================================
// 超时保护
//=============================================================================
initial begin
    #1000000;  // 1ms超时
    $display("[ERROR] Testbench timeout!");
    $finish;
end

endmodule
