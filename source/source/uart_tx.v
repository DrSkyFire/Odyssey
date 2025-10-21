//=============================================================================
// 文件名: uart_tx.v
// 描述: 简易UART发送模块
//=============================================================================
module uart_tx #(
    parameter CLOCK_FREQ = 100_000_000,   // 系统时钟频率 (100MHz)
    parameter BAUD_RATE  = 115200        // 波特率
)(
    input  wire         clk,
    input  wire         rst_n,

    input  wire [7:0]   data_in,         // 要发送的8位数据
    input  wire         send_trigger,    // 发送触发信号（单脉冲）

    output reg          uart_tx_pin,     // 连接到FPGA的TX管脚
    output wire         busy             // 忙标志
);

    localparam CLK_DIV = CLOCK_FREQ / BAUD_RATE;

    // 状态机
    localparam IDLE      = 3'd0;
    localparam START_BIT = 3'd1;
    localparam DATA_BITS = 3'd2;
    localparam STOP_BIT  = 3'd3;

    reg [2:0]  state;
    reg [15:0] clk_cnt;
    reg [2:0]  bit_cnt;
    reg [7:0]  tx_data;

    assign busy = (state != IDLE);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= IDLE;
            clk_cnt     <= 16'd0;
            bit_cnt     <= 3'd0;
            uart_tx_pin <= 1'b1; // 空闲时为高电平
            tx_data     <= 8'd0;
        end else begin
            case (state)
                IDLE: begin
                    if (send_trigger) begin
                        state   <= START_BIT;
                        tx_data <= data_in;
                        clk_cnt <= 16'd0;
                    end
                end

                START_BIT: begin
                    uart_tx_pin <= 1'b0; // 发送起始位
                    if (clk_cnt == CLK_DIV - 1) begin
                        clk_cnt <= 16'd0;
                        state   <= DATA_BITS;
                        bit_cnt <= 3'd0;
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end

                DATA_BITS: begin
                    uart_tx_pin <= tx_data[bit_cnt]; // 从低位开始发送
                    if (clk_cnt == CLK_DIV - 1) begin
                        clk_cnt <= 16'd0;
                        if (bit_cnt == 3'd7) begin
                            state <= STOP_BIT;
                        end else begin
                            bit_cnt <= bit_cnt + 1'b1;
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end

                STOP_BIT: begin
                    uart_tx_pin <= 1'b1; // 发送停止位
                    if (clk_cnt == CLK_DIV - 1) begin
                        clk_cnt <= 16'd0;
                        state   <= IDLE;
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end
                
                default: state <= IDLE;
            endcase
        end
    end

endmodule