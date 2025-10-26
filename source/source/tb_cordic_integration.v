`timescale 1ns / 1ps
//=============================================================================
// 文件名: tb_cordic_integration.v
// 描述: CORDIC集成测试平台
// 功能: 测试signal_analyzer_top中集成的CORDIC功能
// 作者: AI Assistant
// 日期: 2025-10-26
//=============================================================================

module tb_cordic_integration;

// 时钟和复位
reg         sys_clk;        // 50MHz系统时钟
reg         sys_rst_n;      // 系统复位

// ADC接口（模拟）
reg  [9:0]  adc_ch1_data;
reg  [9:0]  adc_ch2_data;

// 按键输入（模拟）
reg  [7:0]  user_button;

// UART输出
wire        uart_tx;

// HDMI输出（监控，不连接）
wire        hd_tx_pclk;
wire        hd_tx_vs;
wire        hd_tx_hs;
wire        hd_tx_de;
wire [23:0] hd_tx_data;

// IIC接口（不使用）
wire        iic_scl;
wire        iic_sda;

// LED输出
wire [7:0]  user_led;

// 测试变量
integer     test_case;
integer     i;
real        expected_sin, expected_cos;
real        adc_voltage;

//=============================================================================
// 时钟生成：50MHz系统时钟
//=============================================================================
initial begin
    sys_clk = 0;
    forever #10 sys_clk = ~sys_clk;  // 50MHz: 周期20ns
end

//=============================================================================
// 顶层模块实例化
//=============================================================================
signal_analyzer_top u_dut (
    // 时钟和复位
    .sys_clk        (sys_clk),
    .sys_rst_n      (sys_rst_n),
    
    // ADC接口
    .adc_ch1_data   (adc_ch1_data),
    .adc_ch2_data   (adc_ch2_data),
    
    // 按键输入
    .user_button    (user_button),
    
    // UART输出
    .uart_tx        (uart_tx),
    
    // HDMI输出
    .hd_tx_pclk     (hd_tx_pclk),
    .hd_tx_vs       (hd_tx_vs),
    .hd_tx_hs       (hd_tx_hs),
    .hd_tx_de       (hd_tx_de),
    .hd_tx_data     (hd_tx_data),
    
    // IIC接口
    .iic_scl        (iic_scl),
    .iic_sda        (iic_sda),
    
    // LED输出
    .user_led       (user_led)
);

//=============================================================================
// 按键按下任务
//=============================================================================
task press_button;
    input [3:0] button_num;
    begin
        $display("[%0t] 按下按键 %0d", $time, button_num);
        user_button[button_num] = 1'b0;  // 假设按键低电平有效
        #1000000;  // 按下1ms
        user_button[button_num] = 1'b1;
        #2000000;  // 释放后等待2ms（消抖）
    end
endtask

//=============================================================================
// ADC数据设置任务
//=============================================================================
task set_adc_data;
    input [9:0] ch1_val;
    input [9:0] ch2_val;
    begin
        adc_ch1_data = ch1_val;
        adc_ch2_data = ch2_val;
        #100;  // 等待数据稳定
    end
endtask

//=============================================================================
// 测试序列
//=============================================================================
initial begin
    // 初始化信号
    sys_rst_n = 0;
    user_button = 8'hFF;  // 所有按键释放（高电平）
    adc_ch1_data = 10'd512;  // 中点值
    adc_ch2_data = 10'd512;
    test_case = 0;
    
    // 打印测试开始信息
    $display("========================================");
    $display("CORDIC集成测试开始");
    $display("========================================");
    
    // 复位释放
    #100;
    sys_rst_n = 1;
    $display("[%0t] 复位释放", $time);
    
    // 等待PLL锁定和系统稳定
    #10000;
    $display("[%0t] 系统稳定", $time);
    
    //=========================================================================
    // 测试用例1: CORDIC模式切换
    //=========================================================================
    test_case = 1;
    $display("\n========================================");
    $display("测试用例1: CORDIC模式切换");
    $display("========================================");
    
    // 切换到模式1 (Sin/Cos)
    press_button(4);
    $display("[%0t] CORDIC模式应为1 (Sin/Cos)", $time);
    #1000000;
    
    // 切换到模式2 (Sinh/Cosh)
    press_button(4);
    $display("[%0t] CORDIC模式应为2 (Sinh/Cosh)", $time);
    #1000000;
    
    // 切换到模式3 (Exp)
    press_button(4);
    $display("[%0t] CORDIC模式应为3 (Exp)", $time);
    #1000000;
    
    // 切换回模式0 (禁用)
    for (i = 0; i < 3; i = i + 1) begin
        press_button(4);
        #1000000;
    end
    $display("[%0t] CORDIC模式应回到0 (禁用)", $time);
    
    //=========================================================================
    // 测试用例2: Sin/Cos计算测试
    //=========================================================================
    test_case = 2;
    $display("\n========================================");
    $display("测试用例2: Sin/Cos计算");
    $display("========================================");
    
    // 切换到Sin/Cos模式
    press_button(4);
    #1000000;
    
    // 测试几个角度
    // 0度 (ADC=512)
    $display("\n--- 测试角度: 0度 ---");
    set_adc_data(10'd512, 10'd512);
    #1000000;  // 等待计算完成
    $display("ADC输入: %0d (对应0度)", adc_ch1_data);
    $display("预期: sin(0°)=0, cos(0°)=1");
    
    // 45度 (ADC=512+128=640)
    $display("\n--- 测试角度: 45度 ---");
    set_adc_data(10'd640, 10'd512);
    #1000000;
    $display("ADC输入: %0d (对应约45度)", adc_ch1_data);
    $display("预期: sin(45°)≈0.707, cos(45°)≈0.707");
    
    // 90度 (ADC=512+256=768)
    $display("\n--- 测试角度: 90度 ---");
    set_adc_data(10'd768, 10'd512);
    #1000000;
    $display("ADC输入: %0d (对应约90度)", adc_ch1_data);
    $display("预期: sin(90°)=1, cos(90°)=0");
    
    // -90度 (ADC=512-256=256)
    $display("\n--- 测试角度: -90度 ---");
    set_adc_data(10'd256, 10'd512);
    #1000000;
    $display("ADC输入: %0d (对应约-90度)", adc_ch1_data);
    $display("预期: sin(-90°)=-1, cos(-90°)=0");
    
    //=========================================================================
    // 测试用例3: Exp计算测试
    //=========================================================================
    test_case = 3;
    $display("\n========================================");
    $display("测试用例3: 指数函数计算");
    $display("========================================");
    
    // 切换到Exp模式
    press_button(4);  // 从模式1到模式2
    press_button(4);  // 从模式2到模式3
    #2000000;
    
    // 测试e^0 (ADC=512)
    $display("\n--- 测试: e^0 ---");
    set_adc_data(10'd512, 10'd512);
    #1000000;
    $display("ADC输入: %0d (对应x=0)", adc_ch1_data);
    $display("预期: e^0 = 1.0");
    
    // 测试e^0.5 (ADC>512)
    $display("\n--- 测试: e^0.5 ---");
    set_adc_data(10'd738, 10'd512);  // 约对应x=0.5
    #1000000;
    $display("ADC输入: %0d (对应x≈0.5)", adc_ch1_data);
    $display("预期: e^0.5 ≈ 1.649");
    
    // 测试e^(-0.5) (ADC<512)
    $display("\n--- 测试: e^(-0.5) ---");
    set_adc_data(10'd286, 10'd512);  // 约对应x=-0.5
    #1000000;
    $display("ADC输入: %0d (对应x≈-0.5)", adc_ch1_data);
    $display("预期: e^(-0.5) ≈ 0.606");
    
    //=========================================================================
    // 测试用例4: 长时间运行测试
    //=========================================================================
    test_case = 4;
    $display("\n========================================");
    $display("测试用例4: 长时间运行（观察UART输出）");
    $display("========================================");
    
    // 切换回Sin/Cos模式
    for (i = 0; i < 4; i = i + 1) begin
        press_button(4);
        #1000000;
    end
    
    // 连续改变ADC输入，模拟实际采集
    $display("开始连续采集模拟...");
    for (i = 0; i < 20; i = i + 1) begin
        set_adc_data(10'd256 + i*32, 10'd512);
        #5000000;  // 每5ms改变一次
    end
    
    //=========================================================================
    // 测试结束
    //=========================================================================
    #10000000;
    $display("\n========================================");
    $display("所有测试完成！");
    $display("========================================");
    $display("注意：请通过波形查看器检查以下信号：");
    $display("1. u_dut.cordic_mode - CORDIC模式");
    $display("2. u_dut.cordic_result_1 - 计算结果1");
    $display("3. u_dut.cordic_result_2 - 计算结果2");
    $display("4. u_dut.cordic_result_valid - 结果有效标志");
    $display("5. uart_tx - UART输出");
    
    $finish;
end

//=============================================================================
// 监控CORDIC结果（可选）
//=============================================================================
always @(posedge u_dut.clk_100m) begin
    if (u_dut.cordic_result_valid) begin
        // 将定点数转换为实数（仅用于显示）
        automatic real r1 = $itor($signed(u_dut.cordic_result_1)) / 65536.0;
        automatic real r2 = $itor($signed(u_dut.cordic_result_2)) / 65536.0;
        
        $display("[%0t] CORDIC结果有效 - 模式=%0d, R1=%f, R2=%f", 
                 $time, u_dut.cordic_mode, r1, r2);
    end
end

//=============================================================================
// 波形文件生成
//=============================================================================
initial begin
    $dumpfile("tb_cordic_integration.vcd");
    $dumpvars(0, tb_cordic_integration);
end

endmodule
