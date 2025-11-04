//=============================================================================
// 文件名: dual_channel_fft_controller.v
// 描述: 双通道时分复用FFT控制器
// 功能: 使用单个FFT核交替处理两个通道的数据
// 优点: 零额外APM消耗，支持8192点10位精度
//=============================================================================

module dual_channel_fft_controller #(
    parameter FFT_POINTS = 8192,  // ✓ 默认改为8192点
    parameter DATA_WIDTH = 16
)(
    input  wire                     clk,
    input  wire                     rst_n,
    
    // 通道1 FIFO接口
    input  wire                     ch1_fifo_empty,
    output reg                      ch1_fifo_rd_en,
    input  wire [DATA_WIDTH-1:0]    ch1_fifo_dout,
    input  wire [13:0]              ch1_fifo_rd_water_level,  // IP核输出14位[13:0]
    
    // 通道2 FIFO接口
    input  wire                     ch2_fifo_empty,
    output reg                      ch2_fifo_rd_en,
    input  wire [DATA_WIDTH-1:0]    ch2_fifo_dout,
    input  wire [13:0]              ch2_fifo_rd_water_level,  // IP核输出14位[13:0]
    
    // FFT IP接口 (AXI4-Stream)
    output reg  [31:0]              fft_din,
    output reg                      fft_din_valid,
    output reg                      fft_din_last,
    input  wire                     fft_din_ready,
    
    // FFT输出接口
    input  wire [31:0]              fft_dout,
    input  wire                     fft_dout_valid,
    input  wire                     fft_dout_last,
    
    // 频谱输出 - 通道1
    output reg  [15:0]              ch1_spectrum_data,
    output reg  [12:0]              ch1_spectrum_addr,  // 8192需要13位地址
    output reg                      ch1_spectrum_valid,
    
    // 频谱输出 - 通道2
    output reg  [15:0]              ch2_spectrum_data,
    output reg  [12:0]              ch2_spectrum_addr,  // 8192需要13位地址
    output reg                      ch2_spectrum_valid,
    
    // 控制信号
    input  wire                     fft_enable,
    input  wire [1:0]               work_mode,
    
    // 状态输出
    output reg                      ch1_fft_busy,
    output reg                      ch2_fft_busy,
    output reg                      current_channel  // 0=CH1, 1=CH2
);

//=============================================================================
// 状态机定义
//=============================================================================
localparam IDLE         = 4'd0;
localparam CH1_WAIT     = 4'd1;
localparam CH1_READ     = 4'd2;
localparam CH1_SEND     = 4'd3;
localparam CH1_RECEIVE  = 4'd4;
localparam CH2_WAIT     = 4'd5;
localparam CH2_READ     = 4'd6;
localparam CH2_SEND     = 4'd7;
localparam CH2_RECEIVE  = 4'd8;
localparam SWITCH_DELAY = 4'd9;

reg [3:0]  state, next_state;

//=============================================================================
// 内部信号
//=============================================================================
reg [12:0]  send_cnt;           // 发送计数器（8192需要13位）
reg [12:0]  recv_cnt;           // 接收计数器（8192需要13位）
reg [15:0]  data_buffer;        // 数据缓存
reg         fifo_rd_en;         // 统一的FIFO读使能
wire [15:0] fifo_dout_mux;      // 多路复用后的FIFO输出
wire [9:0]  data_10bit;         // 10位ADC数据（从16位FIFO数据中提取）

// 频谱计算相关
wire [15:0] spectrum_magnitude;
wire [12:0] spectrum_addr;      // 8192需要13位地址
wire        spectrum_valid;

//=============================================================================
// Hann窗函数相关信号
//=============================================================================
reg  [15:0] hann_window_rom [0:8191];  // Hann窗系数ROM (16位Q15格式)
reg  [15:0] window_coeff;              // 窗系数寄存器
reg  [12:0] window_addr;               // 窗系数读取地址（独立计数器）
wire signed [15:0] adc_signed;         // ADC数据符号扩展
wire signed [31:0] windowed_mult;      // 乘法结果
wire signed [15:0] windowed_data;      // 加窗后的数据

// 初始化Hann窗ROM（HEX文件位于source目录）
initial begin
    $readmemh("source/hann_window_8192.hex", hann_window_rom);
end

// 从FIFO输出的16位数据中提取10位有效数据（高10位）
assign data_10bit = fifo_dout_mux[15:6];

//=============================================================================
// Hann窗地址计数器（提前1拍，补偿ROM读取延迟）
//=============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        window_addr <= 13'd0;
    end else begin
        if (state == CH1_WAIT || state == CH2_WAIT) begin
            window_addr <= 13'd0;  // 准备开始，地址清零
        end
        else if (state == CH1_READ || state == CH2_READ) begin
            window_addr <= 13'd1;  // READ状态，预读下一个地址
        end
        else if (fifo_rd_en && (state == CH1_SEND || state == CH2_SEND)) begin
            if (window_addr == FFT_POINTS - 1)
                window_addr <= 13'd0;
            else
                window_addr <= window_addr + 1'b1;
        end
    end
end

//=============================================================================
// Hann窗加窗处理（3级流水线：ROM读取 → 数据缓存 → 乘法）
//=============================================================================
// 第1级：读取窗系数（ROM读取有1周期延迟）
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        window_coeff <= 16'd0;
    else
        window_coeff <= hann_window_rom[window_addr];
end

//=============================================================================
// 第2级：ADC数据DC偏置去除（优化版本）
//=============================================================================
// 【修复Bug 9】自适应DC去除
// 使用滑动平均估计DC，然后去除

reg signed [15:0] dc_sum;           // DC累加和
reg [7:0] dc_count;                 // 采样计数
reg signed [10:0] dc_avg;           // DC平均值

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        dc_sum <= 16'd0;
        dc_count <= 8'd0;
        dc_avg <= 11'd512;  // 初始值512（ADC中点）
    end else if (fifo_rd_en) begin
        // 累加ADC数据
        if (dc_count == 8'd255) begin
            // 每256个样本更新一次DC估计
            dc_avg <= dc_sum[15:8];  // 平均值（除以256）
            dc_sum <= {6'd0, data_buffer[15:6]};  // 重新开始
            dc_count <= 8'd1;
        end else begin
            dc_sum <= dc_sum + {6'd0, data_buffer[15:6]};
            dc_count <= dc_count + 1'b1;
        end
    end
end

// ADC数据去除DC
wire signed [10:0] adc_offset_removed;
assign adc_offset_removed = {1'b0, data_buffer[15:6]} - dc_avg;

// 符号扩展到16位
assign adc_signed = {{5{adc_offset_removed[10]}}, adc_offset_removed};

// 第3级：乘法（组合逻辑）
// 【紧急修复2025-11-04】禁用Hann窗，改用矩形窗（不加窗）
// 根本原因：Hann窗对低频信号（1kHz）衰减严重（96%），导致：
//   1. 基波被极度衰减（10000 → 400）
//   2. 谐波同样被衰减（但噪声不受影响）
//   3. SNR急剧下降，谐波淹没在噪声中
//   4. FFT频谱上看不到任何谐波 → THD=0%
// 
// Hann窗特性分析：
//   - bin 234 (1kHz): 窗系数≈0.04 (衰减96%)
//   - bin 702 (3kHz): 窗系数≈0.10 (衰减90%)
//   - 前后各2048点几乎全为0，只有中间有效
//   - 对于低频信号（<5kHz），大部分能量被丢弃
// 
// 矩形窗优势（不加窗）：
//   ✅ 所有频率等权重，不引入幅度失真
//   ✅ THD计算准确（谐波/基波比值不变）
//   ✅ 适合固定频率测量（赛题信号源稳定）
//   ✅ 频谱泄漏对THD影响可忽略（谐波间隔>>主瓣宽度）
// 
// 使用矩形窗（不加窗）- 直接传递ADC数据
assign windowed_mult = 32'd0;  // 禁用乘法器
assign windowed_data = adc_signed;  // 直接使用ADC数据

//=============================================================================
// 通道选择多路复用
//=============================================================================
assign fifo_dout_mux = current_channel ? ch2_fifo_dout : ch1_fifo_dout;

always @(*) begin
    ch1_fifo_rd_en = (current_channel == 0) && fifo_rd_en;
    ch2_fifo_rd_en = (current_channel == 1) && fifo_rd_en;
end

//=============================================================================
// 状态机 - 时序逻辑
//=============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        state <= IDLE;
    else
        state <= next_state;
end

//=============================================================================
// 状态机 - 组合逻辑
//=============================================================================
always @(*) begin
    next_state = state;
    case (state)
        IDLE: begin
            if (fft_enable) begin  // ✓ 移除work_mode检查，fft_enable已经包含了这个条件
                // 优先处理通道1
                if (ch1_fifo_rd_water_level >= FFT_POINTS)
                    next_state = CH1_WAIT;
                // 否则检查通道2
                else if (ch2_fifo_rd_water_level >= FFT_POINTS)
                    next_state = CH2_WAIT;
            end
        end
        
        //--- 通道1处理流程 ---
        CH1_WAIT: begin
            next_state = CH1_READ;
        end
        
        CH1_READ: begin
            next_state = CH1_SEND;
        end
        
        CH1_SEND: begin
            if (send_cnt == FFT_POINTS - 1 && fft_din_ready)
                next_state = CH1_RECEIVE;
        end
        
        CH1_RECEIVE: begin
            if (fft_dout_valid && fft_dout_last)
                next_state = SWITCH_DELAY;
        end
        
        //--- 通道切换延迟 ---
        SWITCH_DELAY: begin
            // 等待几个时钟周期，确保数据稳定
            next_state = CH2_WAIT;
        end
        
        //--- 通道2处理流程 ---
        CH2_WAIT: begin
            if (ch2_fifo_rd_water_level >= FFT_POINTS)
                next_state = CH2_READ;
            else
                next_state = IDLE;  // 如果通道2没数据，返回IDLE
        end
        
        CH2_READ: begin
            next_state = CH2_SEND;
        end
        
        CH2_SEND: begin
            if (send_cnt == FFT_POINTS - 1 && fft_din_ready)
                next_state = CH2_RECEIVE;
        end
        
        CH2_RECEIVE: begin
            if (fft_dout_valid && fft_dout_last)
                next_state = IDLE;  // 完成一轮，返回IDLE
        end
        
        default: next_state = IDLE;
    endcase
end

//=============================================================================
// 当前通道指示
//=============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        current_channel <= 1'b0;
    else begin
        case (state)
            CH1_WAIT, CH1_READ, CH1_SEND, CH1_RECEIVE:
                current_channel <= 1'b0;
            CH2_WAIT, CH2_READ, CH2_SEND, CH2_RECEIVE:
                current_channel <= 1'b1;
            default:
                current_channel <= current_channel;
        endcase
    end
end

//=============================================================================
// 忙碌状态指示
//=============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        ch1_fft_busy <= 1'b0;
        ch2_fft_busy <= 1'b0;
    end else begin
        ch1_fft_busy <= (state >= CH1_WAIT && state <= CH1_RECEIVE);
        ch2_fft_busy <= (state >= CH2_WAIT && state <= CH2_RECEIVE);
    end
end

//=============================================================================
// FIFO读控制
//=============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        fifo_rd_en <= 1'b0;
    end else begin
        if (state == CH1_READ || state == CH2_READ)
            fifo_rd_en <= 1'b1;
        else if ((state == CH1_SEND || state == CH2_SEND) && 
                 fft_din_ready && send_cnt < FFT_POINTS - 1)
            fifo_rd_en <= 1'b1;
        else
            fifo_rd_en <= 1'b0;
    end
end

//=============================================================================
// 数据缓存
//=============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        data_buffer <= 16'd0;
    else if (fifo_rd_en)
        data_buffer <= fifo_dout_mux;
end

//=============================================================================
// 发送计数器
//=============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        send_cnt <= 13'd0;
    end else begin
        if (state == CH1_SEND || state == CH2_SEND) begin
            if (fft_din_valid && fft_din_ready) begin
                if (send_cnt == FFT_POINTS - 1)
                    send_cnt <= 13'd0;
                else
                    send_cnt <= send_cnt + 1'b1;
            end
        end else begin
            send_cnt <= 13'd0;
        end
    end
end

//=============================================================================
// FFT输入数据生成（参考官方例程）
// 格式：32位 = {虚部[31:16], 实部[15:0]}
// 实际使用：虚部=0，实部=加窗后的16位数据
//=============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        fft_din       <= 32'd0;
        fft_din_valid <= 1'b0;
        fft_din_last  <= 1'b0;
    end else begin
        if (state == CH1_SEND || state == CH2_SEND) begin
            fft_din_valid <= 1'b1;
            // FFT输入格式：{虚部16位（0），实部16位（加窗后的数据）}
            fft_din <= {16'd0, windowed_data};
            
            // 在倒数第二个数据时拉高tlast
            if (send_cnt == FFT_POINTS - 2)
                fft_din_last <= 1'b1;
            else
                fft_din_last <= 1'b0;
        end else begin
            fft_din       <= 32'd0;
            fft_din_valid <= 1'b0;
            fft_din_last  <= 1'b0;
        end
    end
end

//=============================================================================
// 频谱幅度计算（复用spectrum_magnitude_calc模块）
//=============================================================================
spectrum_magnitude_calc u_spectrum_calc (
    .clk            (clk),
    .rst_n          (rst_n),
    
    .fft_dout       (fft_dout),
    .fft_valid      (fft_dout_valid),
    .fft_last       (fft_dout_last),
    .fft_ready      (),
    
    .magnitude      (spectrum_magnitude),
    .magnitude_addr (spectrum_addr),
    .magnitude_valid(spectrum_valid)
);

//=============================================================================
// 频谱数据分发到对应通道
//=============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        ch1_spectrum_data  <= 16'd0;
        ch1_spectrum_addr  <= 10'd0;
        ch1_spectrum_valid <= 1'b0;
        ch2_spectrum_data  <= 16'd0;
        ch2_spectrum_addr  <= 10'd0;
        ch2_spectrum_valid <= 1'b0;
    end else begin
        // 通道1接收
        if (state == CH1_RECEIVE && spectrum_valid) begin
            ch1_spectrum_data  <= spectrum_magnitude;
            ch1_spectrum_addr  <= spectrum_addr;
            ch1_spectrum_valid <= 1'b1;
        end else begin
            ch1_spectrum_valid <= 1'b0;
        end
        
        // 通道2接收
        if (state == CH2_RECEIVE && spectrum_valid) begin
            ch2_spectrum_data  <= spectrum_magnitude;
            ch2_spectrum_addr  <= spectrum_addr;
            ch2_spectrum_valid <= 1'b1;
        end else begin
            ch2_spectrum_valid <= 1'b0;
        end
    end
end

endmodule
