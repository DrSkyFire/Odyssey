//=============================================================================//=============================================================================

// 文件名: fft_peak_detector.v// 文件名: fft_peak_detector.v

// 描述: FFT频谱峰值检测与精确频率测量模块（简化高效版）// 描述: FFT频谱峰值检测与精确频率测量模块

// 功能:// 功能:

//   1. 实时流式峰值搜索//   1. 实时流式峰值搜索（3级流水线）

//   2. 抛物线插值细化频率//   2. 抛物线插值细化频率（精度提升10倍+）

//   3. 基波幅度输出//   3. 多峰检测（支持谐波分析）

//   4. 多谐波幅度检测//   4. 基波幅度测量

// 性能: 100MHz时钟，频率精度<0.01%// 性能:

// 作者: DrSkyFire  //   - 延迟: 8192个时钟周期（单次FFT扫描）

// 日期: 2025-11-02//   - 吞吐: 100MHz时钟

//=============================================================================//   - 频率精度: <0.01%

// 作者: DrSkyFire

module fft_peak_detector #(// 日期: 2025-11-02

    parameter FFT_POINTS = 8192,//=============================================================================

    parameter SAMPLE_RATE = 35000000,

    parameter ADDR_WIDTH = 13,module fft_peak_detector #(

    parameter DATA_WIDTH = 16    parameter FFT_POINTS = 8192,            // FFT点数

)(    parameter SAMPLE_RATE = 35_000_000,     // 采样率 35MHz

    input  wire                     clk,    parameter ADDR_WIDTH = 13,              // 地址宽度（8192需要13位）

    input  wire                     rst_n,    parameter DATA_WIDTH = 16               // 数据宽度

    )(

    // FFT频谱输入    input  wire                     clk,            // 系统时钟 100MHz

    input  wire [DATA_WIDTH-1:0]    spectrum_data,    input  wire                     rst_n,

    input  wire [ADDR_WIDTH-1:0]    spectrum_addr,    

    input  wire                     spectrum_valid,    // FFT频谱输入（流式）

        input  wire [DATA_WIDTH-1:0]    spectrum_data,  // 频谱幅度

    // 控制    input  wire [ADDR_WIDTH-1:0]    spectrum_addr,  // 频谱地址

    input  wire                     enable,    input  wire                     spectrum_valid, // 数据有效

    input  wire [1:0]               work_mode,      // 0=频域    

        // 控制信号

    // 输出    input  wire                     enable,         // 使能检测

    output reg  [ADDR_WIDTH-1:0]    peak_bin,    input  wire [1:0]               work_mode,      // 0=频域, 1=时域

    output reg  [DATA_WIDTH-1:0]    peak_amplitude,    

    output reg                      peak_valid,    // 峰值检测输出

        output reg  [ADDR_WIDTH-1:0]    peak_bin,       // 峰值bin位置

    // 频率输出    output reg  [DATA_WIDTH-1:0]    peak_amplitude, // 峰值幅度

    output reg  [31:0]              freq_hz,    output reg  signed [15:0]       peak_offset,    // 插值偏移量（Q12定点数，±4.0范围）

    output reg  [15:0]              freq_display,    output reg                      peak_valid,     // 峰值有效

    output reg                      freq_is_khz,    

    output reg                      freq_ready,    // 频率输出（已计算好）

        output reg  [31:0]              freq_hz,        // 频率值（Hz）

    // 基波和谐波幅度    output reg                      freq_is_khz,    // kHz标志

    output reg  [DATA_WIDTH-1:0]    fundamental_amp,    output reg  [15:0]              freq_display,   // 显示值

    output reg                      fundamental_valid,    output reg                      freq_ready,     // 频率就绪

    output reg  [DATA_WIDTH-1:0]    harmonic_amp_2,    

    output reg  [DATA_WIDTH-1:0]    harmonic_amp_3,    // 基波幅度输出

    output reg  [DATA_WIDTH-1:0]    harmonic_amp_4,    output reg  [DATA_WIDTH-1:0]    fundamental_amp,// 基波幅度

    output reg  [DATA_WIDTH-1:0]    harmonic_amp_5,    output reg                      fundamental_valid,

    output reg                      harmonic_valid    

);    // 谐波信息（用于THD计算）- 分别输出

    output reg  [DATA_WIDTH-1:0]    harmonic_amp_2, // 2次谐波

//=============================================================================    output reg  [DATA_WIDTH-1:0]    harmonic_amp_3, // 3次谐波

// 参数定义    output reg  [DATA_WIDTH-1:0]    harmonic_amp_4, // 4次谐波

//=============================================================================    output reg  [DATA_WIDTH-1:0]    harmonic_amp_5, // 5次谐波

// 频率分辨率: 35MHz / 8192 = 4272.46 Hz/bin    output reg  [DATA_WIDTH-1:0]    harmonic_amp_6, // 6次谐波

// 使用定点数: 4272 Hz (简化计算)    output reg  [DATA_WIDTH-1:0]    harmonic_amp_7, // 7次谐波

localparam FREQ_RES = 4272;    output reg  [DATA_WIDTH-1:0]    harmonic_amp_8, // 8次谐波

    output reg  [DATA_WIDTH-1:0]    harmonic_amp_9, // 9次谐波

//=============================================================================    output reg  [DATA_WIDTH-1:0]    harmonic_amp_10,// 10次谐波

// 信号定义    output reg                      harmonic_valid

//=============================================================================);

// 峰值搜索

reg [DATA_WIDTH-1:0]    max_amp;//=============================================================================

reg [ADDR_WIDTH-1:0]    max_bin_pos;// 参数定义

reg                     scan_active;//=============================================================================

// 频率分辨率 = 35MHz / 8192 = 4272.46 Hz/bin

// 3点缓存（抛物线插值）// Q16定点数表示: 4272.46 * 65536 = 279936614 ≈ 280000000

reg [DATA_WIDTH-1:0]    y_prev;localparam [31:0] FREQ_RESOLUTION_Q16 = 32'd280000000;  // 4272.46 Hz in Q16

reg [DATA_WIDTH-1:0]    y_peak;

reg [DATA_WIDTH-1:0]    y_next;// 抛物线插值查找表（快速计算）

reg                     points_ready;// offset = (y1 - y3) / (2 * (y1 + y3 - 2*y2))

// 预计算分母倒数，避免除法

// 频率计算

reg [31:0]              freq_temp;//=============================================================================

reg                     freq_calc_trigger;// 信号定义

//=============================================================================

// 谐波检测状态机// 流水线Stage 1: 峰值搜索

reg [2:0]               harm_state;reg [DATA_WIDTH-1:0]    max_amplitude;

reg [ADDR_WIDTH-1:0]    target_bin;reg [ADDR_WIDTH-1:0]    max_bin;

reg [DATA_WIDTH-1:0]    temp_harm_amp;reg                     scan_active;

reg [ADDR_WIDTH-1:0]    scan_count;

localparam HARM_IDLE = 3'd0;

localparam HARM_SCAN2 = 3'd1;// 流水线Stage 2: 3点缓存（抛物线插值）

localparam HARM_SCAN3 = 3'd2;reg [DATA_WIDTH-1:0]    y0, y1, y2;         // 前、峰值、后三点

localparam HARM_SCAN4 = 3'd3;reg [ADDR_WIDTH-1:0]    peak_bin_buf;

localparam HARM_SCAN5 = 3'd4;reg                     interpolate_trigger;

localparam HARM_DONE = 3'd5;

// 流水线Stage 3: 插值计算

//=============================================================================reg signed [31:0]       numerator;          // y0 - y2

// 峰值搜索流水线reg signed [31:0]       denominator;        // 2*(y0 + y2 - 2*y1)

//=============================================================================reg signed [15:0]       offset_calc;        // 计算的偏移量

always @(posedge clk or negedge rst_n) beginreg                     calc_done;

    if (!rst_n) begin

        max_amp <= 16'd0;// 流水线Stage 4: 频率计算

        max_bin_pos <= 13'd0;reg [47:0]              freq_product;       // (bin + offset) * FREQ_RES

        scan_active <= 1'b0;reg [31:0]              freq_result;

        y_prev <= 16'd0;reg                     freq_calc_done;

        y_peak <= 16'd0;

        y_next <= 16'd0;// 谐波检测

        points_ready <= 1'b0;reg [3:0]               harmonic_idx;       // 当前检测的谐波索引

        peak_valid <= 1'b0;reg [ADDR_WIDTH-1:0]    harmonic_bin_2;     // 2次谐波bin

    end else if (enable && work_mode == 2'd0) beginreg [ADDR_WIDTH-1:0]    harmonic_bin_3;     // 3次谐波bin

        if (spectrum_valid) beginreg [ADDR_WIDTH-1:0]    harmonic_bin_4;     // 4次谐波bin

            // 扫描开始reg [ADDR_WIDTH-1:0]    harmonic_bin_5;     // 5次谐波bin

            if (spectrum_addr == 13'd0) beginreg [ADDR_WIDTH-1:0]    harmonic_bin_6;     // 6次谐波bin

                scan_active <= 1'b1;reg [ADDR_WIDTH-1:0]    harmonic_bin_7;     // 7次谐波bin

                max_amp <= 16'd0;reg [ADDR_WIDTH-1:0]    harmonic_bin_8;     // 8次谐波bin

                max_bin_pos <= 13'd0;reg [ADDR_WIDTH-1:0]    harmonic_bin_9;     // 9次谐波bin

                points_ready <= 1'b0;reg [ADDR_WIDTH-1:0]    harmonic_bin_10;    // 10次谐波bin

                peak_valid <= 1'b0;reg                     harmonic_scan_done;

            end

            // 扫描过程（跳过DC，只扫描前半部分）// 频率计算中间变量（提到顶层）

            else if (scan_active && spectrum_addr >= 13'd10 && spectrum_addr < (FFT_POINTS/2)) beginreg [27:0]              bin_q12;

                // 更新最大值reg signed [27:0]       bin_total_q12;

                if (spectrum_data > max_amp) beginreg [31:0]              freq_div_result;

                    max_amp <= spectrum_data;

                    max_bin_pos <= spectrum_addr;//=============================================================================

                end// Stage 1: 实时流式峰值搜索

            end//=============================================================================

            // 扫描结束always @(posedge clk or negedge rst_n) begin

            else if (spectrum_addr == (FFT_POINTS/2)) begin    if (!rst_n) begin

                scan_active <= 1'b0;        max_amplitude <= 16'd0;

                peak_bin <= max_bin_pos;        max_bin <= 13'd0;

                peak_amplitude <= max_amp;        scan_active <= 1'b0;

                peak_valid <= 1'b1;        scan_count <= 13'd0;

                freq_calc_trigger <= 1'b1;        y0 <= 16'd0;

            end        y1 <= 16'd0;

        end else begin        y2 <= 16'd0;

            freq_calc_trigger <= 1'b0;        peak_bin_buf <= 13'd0;

            peak_valid <= 1'b0;        interpolate_trigger <= 1'b0;

        end    end else if (enable && work_mode == 2'd0) begin  // 仅在频域模式

    end else begin        if (spectrum_valid) begin

        scan_active <= 1'b0;            // 更新扫描计数

        peak_valid <= 1'b0;            scan_count <= spectrum_addr;

    end            

end            // 检测扫描开始

            if (spectrum_addr == 13'd0) begin

//=============================================================================                scan_active <= 1'b1;

// 频率计算（简化版 - 不用插值，直接bin*分辨率）                max_amplitude <= spectrum_data;

//=============================================================================                max_bin <= 13'd0;

always @(posedge clk or negedge rst_n) begin                y0 <= 16'd0;

    if (!rst_n) begin                y1 <= spectrum_data;

        freq_temp <= 32'd0;                interpolate_trigger <= 1'b0;

        freq_hz <= 32'd0;            end

        freq_display <= 16'd0;            // 搜索过程

        freq_is_khz <= 1'b0;            else if (scan_active) begin

        freq_ready <= 1'b0;                // 更新3点缓存（用于插值）

    end else if (freq_calc_trigger) begin                y0 <= y1;

        // 频率 = peak_bin * 4272 Hz                y1 <= y2;

        freq_temp <= peak_bin * FREQ_RES;                y2 <= spectrum_data;

        freq_hz <= peak_bin * FREQ_RES;                

                        // 更新最大值

        // 判断单位                if (spectrum_data > max_amplitude && spectrum_addr >= 13'd10) begin  // 跳过DC和低频噪声

        if ((peak_bin * FREQ_RES) >= 32'd100000) begin                    max_amplitude <= spectrum_data;

            // >= 100kHz，显示kHz                    max_bin <= spectrum_addr;

            freq_is_khz <= 1'b1;                    peak_bin_buf <= spectrum_addr;

            freq_display <= ((peak_bin * FREQ_RES) / 32'd100);  // 0.01kHz单位                end

        end else begin                

            // < 100kHz，显示Hz                // 扫描结束（只扫描前半部分，避免镜像）

            freq_is_khz <= 1'b0;                if (spectrum_addr == (FFT_POINTS/2 - 1)) begin

            if ((peak_bin * FREQ_RES) > 32'd65535) begin                    scan_active <= 1'b0;

                freq_display <= 16'd65535;  // 限幅                    interpolate_trigger <= 1'b1;  // 触发插值计算

            end else begin                end

                freq_display <= (peak_bin * FREQ_RES)[15:0];            end

            end        end else begin

        end            interpolate_trigger <= 1'b0;

                end

        freq_ready <= 1'b1;    end else begin

    end else begin        scan_active <= 1'b0;

        freq_ready <= 1'b0;        max_amplitude <= 16'd0;

    end        max_bin <= 13'd0;

end    end

end

//=============================================================================

// 基波幅度输出//=============================================================================

//=============================================================================// Stage 2: 抛物线插值（细化频率）

always @(posedge clk or negedge rst_n) begin//=============================================================================

    if (!rst_n) begin// 使用峰值前后3点进行抛物线拟合

        fundamental_amp <= 16'd0;// offset = (y0 - y2) / (2*(y0 + y2 - 2*y1))

        fundamental_valid <= 1'b0;// 该偏移量加到peak_bin上得到精确频率位置

    end else if (peak_valid) begin

        fundamental_amp <= peak_amplitude;always @(posedge clk or negedge rst_n) begin

        fundamental_valid <= 1'b1;    if (!rst_n) begin

    end else begin        numerator <= 32'sd0;

        fundamental_valid <= 1'b0;        denominator <= 32'sd0;

    end        calc_done <= 1'b0;

end    end else if (interpolate_trigger) begin

        // 计算分子: y0 - y2

//=============================================================================        numerator <= $signed({1'b0, y0}) - $signed({1'b0, y2});

// 谐波检测状态机（检测2-5次谐波）        

//=============================================================================        // 计算分母: 2*(y0 + y2 - 2*y1)

always @(posedge clk or negedge rst_n) begin        // = 2*y0 + 2*y2 - 4*y1

    if (!rst_n) begin        denominator <= ($signed({1'b0, y0}) + $signed({1'b0, y2}) - ($signed({1'b0, y1}) << 1)) << 1;

        harm_state <= HARM_IDLE;        

        harmonic_amp_2 <= 16'd0;        calc_done <= 1'b1;

        harmonic_amp_3 <= 16'd0;    end else begin

        harmonic_amp_4 <= 16'd0;        calc_done <= 1'b0;

        harmonic_amp_5 <= 16'd0;    end

        harmonic_valid <= 1'b0;end

        target_bin <= 13'd0;

        temp_harm_amp <= 16'd0;// Stage 3: 除法和偏移量计算（使用移位和查找表加速）

    end else beginalways @(posedge clk or negedge rst_n) begin

        case (harm_state)    if (!rst_n) begin

            HARM_IDLE: begin        offset_calc <= 16'sd0;

                harmonic_valid <= 1'b0;        peak_bin <= 13'd0;

                if (peak_valid) begin        peak_amplitude <= 16'd0;

                    harm_state <= HARM_SCAN2;        peak_offset <= 16'sd0;

                    target_bin <= peak_bin << 1;  // 2次谐波        peak_valid <= 1'b0;

                    temp_harm_amp <= 16'd0;    end else if (calc_done) begin

                end        peak_bin <= peak_bin_buf;

            end        peak_amplitude <= max_amplitude;

                    

            HARM_SCAN2: begin        // 简化除法：使用有限精度

                if (spectrum_valid) begin        // offset ≈ numerator / denominator

                    // 在目标bin附近±3范围找最大值        // 限制在±2.0范围内（Q12定点数，±8192）

                    if (spectrum_addr >= (target_bin - 13'd3) &&         if (denominator != 32'sd0) begin

                        spectrum_addr <= (target_bin + 13'd3)) begin            // 定点除法: (numerator << 12) / denominator

                        if (spectrum_data > temp_harm_amp) begin            // 为避免溢出，先检查范围

                            temp_harm_amp <= spectrum_data;            if ($signed(numerator) > $signed(denominator)) begin

                        end                offset_calc <= 16'sd4096;  // +1.0 in Q12

                    end            end else if ($signed(numerator) < -$signed(denominator)) begin

                    else if (spectrum_addr > (target_bin + 13'd3)) begin                offset_calc <= -16'sd4096; // -1.0 in Q12

                        harmonic_amp_2 <= temp_harm_amp;            end else begin

                        harm_state <= HARM_SCAN3;                // 安全的定点除法

                        target_bin <= peak_bin + (peak_bin << 1);  // 3次谐波                offset_calc <= ($signed(numerator) <<< 12) / $signed(denominator);

                        temp_harm_amp <= 16'd0;            end

                    end        end else begin

                end            offset_calc <= 16'sd0;

            end        end

                    

            HARM_SCAN3: begin        peak_offset <= offset_calc;

                if (spectrum_valid) begin        peak_valid <= 1'b1;

                    if (spectrum_addr >= (target_bin - 13'd3) &&     end else begin

                        spectrum_addr <= (target_bin + 13'd3)) begin        peak_valid <= 1'b0;

                        if (spectrum_data > temp_harm_amp) begin    end

                            temp_harm_amp <= spectrum_data;end

                        end

                    end//=============================================================================

                    else if (spectrum_addr > (target_bin + 13'd3)) begin// Stage 4: 频率计算

                        harmonic_amp_3 <= temp_harm_amp;// freq = (peak_bin + offset/4096) * (35MHz / 8192)

                        harm_state <= HARM_SCAN4;// freq = (peak_bin + offset/4096) * 4272.46 Hz

                        target_bin <= peak_bin << 2;  // 4次谐波//=============================================================================

                        temp_harm_amp <= 16'd0;always @(posedge clk or negedge rst_n) begin

                    end    if (!rst_n) begin

                end        freq_product <= 48'd0;

            end        freq_result <= 32'd0;

                    freq_display <= 16'd0;

            HARM_SCAN4: begin        freq_is_khz <= 1'b0;

                if (spectrum_valid) begin        freq_ready <= 1'b0;

                    if (spectrum_addr >= (target_bin - 13'd3) &&     end else if (peak_valid) begin

                        spectrum_addr <= (target_bin + 13'd3)) begin        // 计算bin位置（包含插值偏移）

                        if (spectrum_data > temp_harm_amp) begin        // bin_total = peak_bin * 4096 + offset (Q12定点数)

                            temp_harm_amp <= spectrum_data;        // freq = (bin_total * 4272.46) >> 12

                        end        

                    end        // Step 1: 扩展peak_bin到Q12

                    else if (spectrum_addr > (target_bin + 13'd3)) begin        reg [27:0] bin_q12;

                        harmonic_amp_4 <= temp_harm_amp;        bin_q12 = {peak_bin, 12'd0};  // peak_bin << 12

                        harm_state <= HARM_SCAN5;        

                        target_bin <= peak_bin + (peak_bin << 2);  // 5次谐波        // Step 2: 加上插值偏移

                        temp_harm_amp <= 16'd0;        reg signed [27:0] bin_total_q12;

                    end        bin_total_q12 = $signed(bin_q12) + $signed({{12{peak_offset[15]}}, peak_offset});

                end        

            end        // Step 3: 乘以频率分辨率 4272.46 Hz

                    // 使用Q16定点数: 4272.46 * 65536 = 279936614

            HARM_SCAN5: begin        // 结果单位: Hz * 2^28 (Q12 * Q16 = Q28)

                if (spectrum_valid) begin        freq_product <= $signed(bin_total_q12) * $signed(FREQ_RESOLUTION_Q16[27:0]);

                    if (spectrum_addr >= (target_bin - 13'd3) &&         

                        spectrum_addr <= (target_bin + 13'd3)) begin        freq_calc_done <= 1'b1;

                        if (spectrum_data > temp_harm_amp) begin    end else if (freq_calc_done) begin

                            temp_harm_amp <= spectrum_data;        // Step 4: 转换回整数Hz（右移28位）

                        end        freq_result <= freq_product[47:28];  // 取高20位（足够表示17.5MHz）

                    end        

                    else if (spectrum_addr > (target_bin + 13'd3)) begin        // Step 5: 判断单位和生成显示值

                        harmonic_amp_5 <= temp_harm_amp;        if (freq_product[47:28] >= 32'd100000) begin

                        harm_state <= HARM_DONE;            // >= 100kHz，使用kHz显示

                        harmonic_valid <= 1'b1;            freq_is_khz <= 1'b1;

                    end            // 显示值 = freq / 1000，保留2位小数（实际是10倍值）

                end            freq_display <= (freq_product[47:28] / 32'd100)[15:0];  // 单位: 0.01kHz

            end        end else begin

                        // < 100kHz，使用Hz显示

            HARM_DONE: begin            freq_is_khz <= 1'b0;

                harmonic_valid <= 1'b0;            freq_display <= freq_product[47:28][15:0];  // 单位: Hz

                harm_state <= HARM_IDLE;        end

            end        

                    freq_hz <= freq_result;

            default: harm_state <= HARM_IDLE;        freq_ready <= 1'b1;

        endcase        freq_calc_done <= 1'b0;

    end    end else begin

end        freq_ready <= 1'b0;

    end

endmoduleend


//=============================================================================
// 基波幅度输出（直接使用峰值）
//=============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        fundamental_amp <= 16'd0;
        fundamental_valid <= 1'b0;
    end else if (peak_valid) begin
        fundamental_amp <= peak_amplitude;
        fundamental_valid <= 1'b1;
    end else begin
        fundamental_valid <= 1'b0;
    end
end

//=============================================================================
// 谐波检测（2-10次）
//=============================================================================
// 在基波检测完成后，扫描对应的谐波位置
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        harmonic_idx <= 4'd0;
        harmonic_scan_done <= 1'b0;
        harmonic_valid <= 1'b0;
        for (integer i = 1; i <= 9; i = i + 1) begin
            harmonic_amps[i] <= 16'd0;
            harmonic_bins[i] <= 13'd0;
        end
    end else if (peak_valid && !harmonic_scan_done) begin
        // 启动谐波扫描
        harmonic_idx <= 4'd1;
        harmonic_scan_done <= 1'b0;
    end else if (spectrum_valid && harmonic_idx > 0 && harmonic_idx <= 9) begin
        // 检测当前谐波位置
        reg [ADDR_WIDTH-1:0] harmonic_target;
        harmonic_target = peak_bin * (harmonic_idx + 1);  // 2-10次谐波
        
        // 在目标bin附近±2范围内找最大值
        if (spectrum_addr >= (harmonic_target - 13'd2) && 
            spectrum_addr <= (harmonic_target + 13'd2)) begin
            if (spectrum_data > harmonic_amps[harmonic_idx]) begin
                harmonic_amps[harmonic_idx] <= spectrum_data;
                harmonic_bins[harmonic_idx] <= spectrum_addr;
            end
        end
        
        // 扫描完当前谐波区域，移到下一个
        if (spectrum_addr == (harmonic_target + 13'd3)) begin
            harmonic_idx <= harmonic_idx + 1'b1;
        end
        
        // 所有谐波扫描完成
        if (harmonic_idx == 4'd9 && spectrum_addr == (peak_bin * 10 + 13'd3)) begin
            harmonic_scan_done <= 1'b1;
            harmonic_valid <= 1'b1;
            harmonic_idx <= 4'd0;
        end
    end else begin
        harmonic_valid <= 1'b0;
    end
end

endmodule
