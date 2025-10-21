//=============================================================================
// 文件名: fifo_async.v
// 描述: 异步FIFO封装 - 用于跨时钟域数据传输
//=============================================================================

module fifo_async #(
    parameter DATA_WIDTH = 16,
    parameter FIFO_DEPTH = 2048
)(
    // 写端口 (ADC时钟域)
    input  wire                     wr_clk,
    input  wire                     wr_rst_n,
    input  wire                     wr_en,
    input  wire [DATA_WIDTH-1:0]    wr_data,
    output wire                     full,
    output wire                     almost_full,
    output wire [11:0]              wr_water_level,     // 新增
    
    // 读端口 (FFT时钟域)
    input  wire                     rd_clk,
    input  wire                     rd_rst_n,
    input  wire                     rd_en,
    output wire [DATA_WIDTH-1:0]    rd_data,
    output wire                     empty,
    output wire                     almost_empty,
    output wire [11:0]              rd_water_level      // 新增
);

//=============================================================================
// 异步FIFO IP核实例化
//=============================================================================
fifo_async_ip u_fifo_ip (
    // 写端口
    .wr_clk         (wr_clk),
    .wr_rst         (~wr_rst_n),            // 注意：IP核是高有效复位
    .wr_en          (wr_en),
    .wr_data        (wr_data),
    .wr_full        (full),
    .almost_full    (almost_full),
    .wr_water_level (wr_water_level),       // 写水位
    
    // 读端口
    .rd_clk         (rd_clk),
    .rd_rst         (~rd_rst_n),            // 注意：IP核是高有效复位
    .rd_en          (rd_en),
    .rd_data        (rd_data),
    .rd_empty       (empty),
    .almost_empty   (almost_empty),
    .rd_water_level (rd_water_level)        // 读水位
);

endmodule