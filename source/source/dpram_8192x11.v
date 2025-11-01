//=============================================================================
// 文件名: dpram_8192x11.v
// 描述: 双口RAM封装 - 用于频谱数据存储（8192深度，10位数据）
// 功能: 封装DPRAM_8192x11 IP核，提供简化的接口
// 注意: 模块名保持为dpram_8192x11（与IP核名称一致），但实际配置为10位
//=============================================================================

module dpram_8192x11 (
    // Port A - 写端口 (FFT时钟域)
    input  wire         clka,
    input  wire         wea,            // 写使能
    input  wire [12:0]  addra,          // 写地址（8192需要13位）
    input  wire [9:0]   dina,           // 写数据（10位）
    
    // Port B - 读端口 (HDMI时钟域)
    input  wire         clkb,
    input  wire [12:0]  addrb,          // 读地址（8192需要13位）
    output wire [10:0]  doutb           // 读数据（11位，最高位填0）
);

//=============================================================================
// DRM Based Dual Port RAM IP核实例化 - 8192x10配置
//=============================================================================
wire [9:0] doutb_10bit;  // 10位输出

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
    .b_wr_data  (10'h000),              // 不使用
    .b_wr_en    (1'b0),                 // 只读端口
    .b_rd_data  (doutb_10bit)
);

// 扩展到11位（高位补0，保持接口兼容性）
assign doutb = {1'b0, doutb_10bit};

endmodule
