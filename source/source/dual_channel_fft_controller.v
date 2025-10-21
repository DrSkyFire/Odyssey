//=============================================================================
// 文件名: dual_channel_fft_controller.v
// 描述: 双通道时分复用FFT控制器
// 功能: 使用单个FFT核交替处理两个通道的数据
// 优点: 零额外APM消耗，保持1024点16位精度
//=============================================================================

module dual_channel_fft_controller #(
    parameter FFT_POINTS = 1024,
    parameter DATA_WIDTH = 16
)(
    input  wire                     clk,
    input  wire                     rst_n,
    
    // 通道1 FIFO接口
    input  wire                     ch1_fifo_empty,
    output reg                      ch1_fifo_rd_en,
    input  wire [DATA_WIDTH-1:0]    ch1_fifo_dout,
    input  wire [11:0]              ch1_fifo_rd_water_level,
    
    // 通道2 FIFO接口
    input  wire                     ch2_fifo_empty,
    output reg                      ch2_fifo_rd_en,
    input  wire [DATA_WIDTH-1:0]    ch2_fifo_dout,
    input  wire [11:0]              ch2_fifo_rd_water_level,
    
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
    output reg  [9:0]               ch1_spectrum_addr,
    output reg                      ch1_spectrum_valid,
    
    // 频谱输出 - 通道2
    output reg  [15:0]              ch2_spectrum_data,
    output reg  [9:0]               ch2_spectrum_addr,
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
reg [9:0]   send_cnt;           // 发送计数器
reg [9:0]   recv_cnt;           // 接收计数器
reg [15:0]  data_buffer;        // 数据缓存
reg         fifo_rd_en;         // 统一的FIFO读使能
wire [15:0] fifo_dout_mux;      // 多路复用后的FIFO输出

// 频谱计算相关
wire [15:0] spectrum_magnitude;
wire [9:0]  spectrum_addr;
wire        spectrum_valid;

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
            if (fft_enable && work_mode == 2'd1) begin
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
        send_cnt <= 10'd0;
    end else begin
        if (state == CH1_SEND || state == CH2_SEND) begin
            if (fft_din_valid && fft_din_ready) begin
                if (send_cnt == FFT_POINTS - 1)
                    send_cnt <= 10'd0;
                else
                    send_cnt <= send_cnt + 1'b1;
            end
        end else begin
            send_cnt <= 10'd0;
        end
    end
end

//=============================================================================
// FFT输入数据生成（参考官方例程）
//=============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        fft_din       <= 32'd0;
        fft_din_valid <= 1'b0;
        fft_din_last  <= 1'b0;
    end else begin
        if (state == CH1_SEND || state == CH2_SEND) begin
            fft_din_valid <= 1'b1;
            fft_din <= {16'd0, data_buffer};
            
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
