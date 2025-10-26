//=============================================================================
// 文件名: ai_recognizer_testbench.v
// 描述: AI信号识别器仿真测试台
// 功能: 测试不同波形的识别准确性
//=============================================================================

`timescale 1ns/1ps

module ai_recognizer_testbench;

//=============================================================================
// 参数定义
//=============================================================================
parameter CLK_PERIOD = 10;  // 100MHz时钟
parameter DATA_WIDTH = 11;
parameter WINDOW_SIZE = 1024;

//=============================================================================
// 信号定义
//=============================================================================
reg                         clk;
reg                         rst_n;
reg signed [DATA_WIDTH-1:0] signal_in;
reg                         signal_valid;
reg [15:0]                  fft_magnitude;
reg [9:0]                   fft_bin_index;
reg                         fft_valid;
reg                         ai_enable;

wire [2:0]                  waveform_type;
wire [7:0]                  confidence;
wire                        result_valid;
wire [15:0]                 dbg_zcr;
wire [15:0]                 dbg_crest_factor;
wire [15:0]                 dbg_thd;

//=============================================================================
// 测试变量
//=============================================================================
integer i;
integer test_count;
integer correct_count;
real phase;
real amplitude;
integer freq_bin;

//=============================================================================
// DUT实例化
//=============================================================================
ai_signal_recognizer #(
    .DATA_WIDTH   (DATA_WIDTH),
    .WINDOW_SIZE  (WINDOW_SIZE),
    .FFT_BINS     (512)
) dut (
    .clk              (clk),
    .rst_n            (rst_n),
    .signal_in        (signal_in),
    .signal_valid     (signal_valid),
    .fft_magnitude    (fft_magnitude),
    .fft_bin_index    (fft_bin_index),
    .fft_valid        (fft_valid),
    .ai_enable        (ai_enable),
    .waveform_type    (waveform_type),
    .confidence       (confidence),
    .result_valid     (result_valid),
    .dbg_zcr          (dbg_zcr),
    .dbg_crest_factor (dbg_crest_factor),
    .dbg_thd          (dbg_thd)
);

//=============================================================================
// 时钟生成
//=============================================================================
initial begin
    clk = 0;
    forever #(CLK_PERIOD/2) clk = ~clk;
end

//=============================================================================
// 波形生成函数
//=============================================================================

// 正弦波生成
task generate_sine_wave;
    input real freq;      // 归一化频率 (0-0.5)
    input real amp;       // 幅度 (0-1023)
    integer idx;
    begin
        $display("\n[TEST] Generating SINE wave: freq=%f, amp=%f", freq, amp);
        phase = 0;
        freq_bin = freq * 1024;  // FFT频点
        
        for (idx = 0; idx < WINDOW_SIZE; idx = idx + 1) begin
            @(posedge clk);
            signal_in = $rtoi(amp * $sin(2 * 3.14159 * freq * idx));
            signal_valid = 1'b1;
        end
        
        // 生成FFT数据（模拟纯净正弦波：单一频点）
        for (idx = 0; idx < 512; idx = idx + 1) begin
            @(posedge clk);
            fft_bin_index = idx;
            if (idx == freq_bin)
                fft_magnitude = amp * 512;  // 基波幅度
            else if (idx == freq_bin*2 || idx == freq_bin*3)
                fft_magnitude = amp * 10;   // 微小谐波（THD<2%）
            else
                fft_magnitude = 16'd50;     // 噪声底
            fft_valid = 1'b1;
        end
        
        signal_valid = 1'b0;
        fft_valid = 1'b0;
        
        // 等待结果
        wait(result_valid);
        @(posedge clk);
        check_result(3'd1, "SINE");  // 期望识别为正弦波
    end
endtask

// 方波生成
task generate_square_wave;
    input real freq;
    input real amp;
    integer idx;
    begin
        $display("\n[TEST] Generating SQUARE wave: freq=%f, amp=%f", freq, amp);
        freq_bin = freq * 1024;
        
        for (idx = 0; idx < WINDOW_SIZE; idx = idx + 1) begin
            @(posedge clk);
            // 方波：50%占空比
            if ((idx % $rtoi(1.0/freq)) < $rtoi(0.5/freq))
                signal_in = amp;
            else
                signal_in = -amp;
            signal_valid = 1'b1;
        end
        
        // FFT数据（方波：强奇次谐波）
        for (idx = 0; idx < 512; idx = idx + 1) begin
            @(posedge clk);
            fft_bin_index = idx;
            if (idx == freq_bin)
                fft_magnitude = amp * 512;       // 基波
            else if (idx == freq_bin*3)
                fft_magnitude = amp * 170;       // 3次谐波(1/3)
            else if (idx == freq_bin*5)
                fft_magnitude = amp * 102;       // 5次谐波(1/5)
            else
                fft_magnitude = 16'd80;
            fft_valid = 1'b1;
        end
        
        signal_valid = 1'b0;
        fft_valid = 1'b0;
        
        wait(result_valid);
        @(posedge clk);
        check_result(3'd2, "SQUARE");
    end
endtask

// 三角波生成
task generate_triangle_wave;
    input real freq;
    input real amp;
    integer idx;
    real period;
    begin
        $display("\n[TEST] Generating TRIANGLE wave: freq=%f, amp=%f", freq, amp);
        freq_bin = freq * 1024;
        period = 1.0 / freq;
        
        for (idx = 0; idx < WINDOW_SIZE; idx = idx + 1) begin
            @(posedge clk);
            // 三角波：线性上升下降
            if ((idx % $rtoi(period)) < $rtoi(period/2))
                signal_in = -amp + (4*amp*idx % $rtoi(period)) / $rtoi(period);
            else
                signal_in = 3*amp - (4*amp*idx % $rtoi(period)) / $rtoi(period);
            signal_valid = 1'b1;
        end
        
        // FFT数据（三角波：中等谐波）
        for (idx = 0; idx < 512; idx = idx + 1) begin
            @(posedge clk);
            fft_bin_index = idx;
            if (idx == freq_bin)
                fft_magnitude = amp * 512;
            else if (idx == freq_bin*3)
                fft_magnitude = amp * 56;   // 3次谐波(1/9)
            else if (idx == freq_bin*5)
                fft_magnitude = amp * 20;   // 5次谐波(1/25)
            else
                fft_magnitude = 16'd60;
            fft_valid = 1'b1;
        end
        
        signal_valid = 1'b0;
        fft_valid = 1'b0;
        
        wait(result_valid);
        @(posedge clk);
        check_result(3'd3, "TRIANGLE");
    end
endtask

// 噪声生成
task generate_noise;
    input real amp;
    integer idx;
    integer seed;
    begin
        $display("\n[TEST] Generating NOISE signal: amp=%f", amp);
        seed = 12345;
        
        for (idx = 0; idx < WINDOW_SIZE; idx = idx + 1) begin
            @(posedge clk);
            signal_in = $random(seed) % $rtoi(amp);
            signal_valid = 1'b1;
        end
        
        // FFT数据（噪声：均匀分布）
        for (idx = 0; idx < 512; idx = idx + 1) begin
            @(posedge clk);
            fft_bin_index = idx;
            fft_magnitude = amp * 2 + ($random(seed) % $rtoi(amp));
            fft_valid = 1'b1;
        end
        
        signal_valid = 1'b0;
        fft_valid = 1'b0;
        
        wait(result_valid);
        @(posedge clk);
        check_result(3'd5, "NOISE");
    end
endtask

//=============================================================================
// 结果检查
//=============================================================================
task check_result;
    input [2:0] expected_type;
    input [8*20:1] type_name;
    begin
        test_count = test_count + 1;
        
        $display("----------------------------------------");
        $display("Expected: %s (type=%d)", type_name, expected_type);
        
        case (waveform_type)
            3'd0: $display("Detected: UNKNOWN");
            3'd1: $display("Detected: SINE");
            3'd2: $display("Detected: SQUARE");
            3'd3: $display("Detected: TRIANGLE");
            3'd4: $display("Detected: SAWTOOTH");
            3'd5: $display("Detected: NOISE");
            default: $display("Detected: INVALID");
        endcase
        
        $display("Confidence: %d%%", confidence);
        $display("Debug Features:");
        $display("  ZCR: %d", dbg_zcr);
        $display("  Crest Factor: %d (Q8.8)", dbg_crest_factor);
        $display("  THD: %d%%", dbg_thd);
        
        if (waveform_type == expected_type) begin
            $display("✓ PASS - Correct identification");
            correct_count = correct_count + 1;
        end else begin
            $display("✗ FAIL - Misidentification");
        end
        
        $display("----------------------------------------\n");
    end
endtask

//=============================================================================
// 测试序列
//=============================================================================
initial begin
    $display("\n===========================================");
    $display("   AI Signal Recognizer Testbench");
    $display("===========================================\n");
    
    // 初始化
    rst_n = 0;
    signal_in = 0;
    signal_valid = 0;
    fft_magnitude = 0;
    fft_bin_index = 0;
    fft_valid = 0;
    ai_enable = 1;
    test_count = 0;
    correct_count = 0;
    
    #(CLK_PERIOD * 10);
    rst_n = 1;
    #(CLK_PERIOD * 10);
    
    // 测试1: 正弦波（不同频率）
    generate_sine_wave(0.01, 800);  // 1% Nyquist, 高幅度
    #1000;
    generate_sine_wave(0.05, 500);  // 5% Nyquist, 中幅度
    #1000;
    
    // 测试2: 方波
    generate_square_wave(0.02, 700);
    #1000;
    
    // 测试3: 三角波
    generate_triangle_wave(0.03, 600);
    #1000;
    
    // 测试4: 噪声
    generate_noise(400);
    #1000;
    
    // 测试5: 低幅度正弦波（挑战）
    generate_sine_wave(0.02, 200);  // 低幅度
    #1000;
    
    // 统计结果
    $display("\n===========================================");
    $display("   Test Summary");
    $display("===========================================");
    $display("Total Tests:    %d", test_count);
    $display("Passed:         %d", correct_count);
    $display("Failed:         %d", test_count - correct_count);
    $display("Accuracy:       %0.1f%%", (100.0 * correct_count) / test_count);
    $display("===========================================\n");
    
    #1000;
    $finish;
end

//=============================================================================
// 波形转储
//=============================================================================
initial begin
    $dumpfile("ai_recognizer_tb.vcd");
    $dumpvars(0, ai_recognizer_testbench);
end

endmodule
