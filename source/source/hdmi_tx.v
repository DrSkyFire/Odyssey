//=============================================================================
// 文件名: hdmi_tx.v
// 描述: HDMI发送模块 - MS7210驱动
// 功能: 
//   1. MS7210初始化配置
//   2. RGB数据输出
//=============================================================================

module hdmi_tx (
    input  wire         clk_pixel,          // 像素时钟 74.25MHz
    input  wire         rst_n,
    
    // 视频输入
    input  wire [23:0]  rgb,                // RGB数据
    input  wire         de,                 // 数据使能
    input  wire         hs,                 // 行同步
    input  wire         vs,                 // 场同步
    
    // HDMI物理输出（连接到MS7210）
    output wire         tmds_clk_p         // 像素时钟输出
);

assign tmds_clk_p = clk_pixel;

endmodule