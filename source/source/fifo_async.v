//=============================================================================
// 文件名: fifo_async.v
// 描述: 异步FIFO封装 - 用于跨时钟域数据传输
//=============================================================================

module fifo_async #(
    parameter DATA_WIDTH = 16,
    parameter FIFO_DEPTH = 8192  // ✓ 默认改为8192
)(
    // 写端口 (ADC时钟域)
    input  wire                     wr_clk,
    input  wire                     wr_rst_n,
    input  wire                     wr_en,
    input  wire [DATA_WIDTH-1:0]    wr_data,
    output wire                     full,
    output wire                     almost_full,
    output wire [13:0]              wr_water_level,     // ✓ 改为14位！IP核输出[DEPTH_WIDTH:0]
    
    // 读端口 (FFT时钟域)
    input  wire                     rd_clk,
    input  wire                     rd_rst_n,
    input  wire                     rd_en,
    output wire [DATA_WIDTH-1:0]    rd_data,
    output wire                     empty,
    output wire                     almost_empty,
    output wire [13:0]              rd_water_level      // ✓ 改为14位！IP核输出[DEPTH_WIDTH:0]
);

//=============================================================================
// 异步FIFO IP核实例化 - 使用8192深度11位数据宽度
//=============================================================================
wire [10:0] fifo_rd_data_11b;  // 11位FIFO输出

FIFO_ASYNC_8192x11 u_fifo_ip (
    // 写端口
    .wr_clk         (wr_clk),
    .wr_rst         (~wr_rst_n),            // 注意：IP核是高有效复位
    .wr_en          (wr_en),
    .wr_data        (wr_data[10:0]),        // 截取低11位
    .wr_full        (full),
    .almost_full    (almost_full),
    .wr_water_level (wr_water_level),       // 写水位
    
    // 读端口
    .rd_clk         (rd_clk),
    .rd_rst         (~rd_rst_n),            // 注意：IP核是高有效复位
    .rd_en          (rd_en),
    .rd_data        (fifo_rd_data_11b),     // 输出11位
    .rd_empty       (empty),
    .almost_empty   (almost_empty),
    .rd_water_level (rd_water_level)        // 读水位
);

// 扩展到DATA_WIDTH位，高位补0
assign rd_data = {{(DATA_WIDTH-11){1'b0}}, fifo_rd_data_11b};

endmodule