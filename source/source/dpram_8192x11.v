//=============================================================================
// 文件名: dpram_8192x11.v
// 描述: 双口RAM封装 - 用于频谱数据存储（8192深度，11位数据）
// 功能: 封装DPRAM_8192x11 IP核，提供简化的接口
//=============================================================================

module dpram_8192x11 (
    // Port A - 写端口 (FFT时钟域)
    input  wire         clka,
    input  wire         wea,            // 写使能
    input  wire [12:0]  addra,          // 写地址（8192需要13位）
    input  wire [10:0]  dina,           // 写数据（11位）
    
    // Port B - 读端口 (HDMI时钟域)
    input  wire         clkb,
    input  wire [12:0]  addrb,          // 读地址（8192需要13位）
    output wire [10:0]  doutb           // 读数据（11位）
);

//=============================================================================
// DRM Based Dual Port RAM IP核实例化 - 8192x11配置
//=============================================================================
DPRAM_8192x11 u_dpram_ip (
    // Port A (写端口)
    .a_clk      (clka),
    .a_rst      (1'b0),                 // 不使用复位
    .a_addr     (addra),
    .a_wr_data  (dina),
    .a_wr_en    (wea),
    .a_rd_data  (),                     // 不使用Port A读功能
    
    // Port B (读端口)
    .b_clk      (clkb),
    .b_rst      (1'b0),                 // 不使用复位
    .b_addr     (addrb),
    .b_wr_data  (11'h000),              // 不使用
    .b_wr_en    (1'b0),                 // 只读端口
    .b_rd_data  (doutb)
);

endmodule
