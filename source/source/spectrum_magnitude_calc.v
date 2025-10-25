//=============================================================================
// 文件名: spectrum_magnitude_calc.v (完全修复版)
//=============================================================================

module spectrum_magnitude_calc (
    input  wire         clk,
    input  wire         rst_n,
    
    input  wire [31:0]  fft_dout,
    input  wire         fft_valid,
    input  wire         fft_last,
    output wire         fft_ready,
    
    output reg  [15:0]  magnitude,
    output reg  [12:0]  magnitude_addr,  // 8192需要13位地址
    output reg          magnitude_valid
);

wire signed [15:0] re;
wire signed [15:0] im;

reg  [15:0] re_abs;
reg  [15:0] im_abs;
reg  [15:0] max_val;
reg  [15:0] min_val;
reg  [15:0] min_half;
reg  [15:0] mag_calc;

// ✓ 添加更多流水线寄存器
reg  [15:0] max_val_d3;  // 延迟max_val以对齐min_half
reg         valid_d1, valid_d2, valid_d3;
reg  [12:0] addr_cnt;    // 8192需要13位地址
reg  [12:0] addr_d1, addr_d2, addr_d3;  // 8192需要13位地址

assign re = fft_dout[15:0];
assign im = fft_dout[31:16];
assign fft_ready = 1'b1;

//=============================================================================
// 地址计数器（修复：在last之后复位，而不是在last时复位）
//=============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        addr_cnt <= 13'd0;
    else if (fft_valid) begin
        if (addr_cnt == 13'd8191)
            addr_cnt <= 13'd0;  // 计数到8191后回到0
        else
            addr_cnt <= addr_cnt + 1'b1;
    end
end

//=============================================================================
// 第1级：计算绝对值
//=============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        re_abs   <= 16'd0;
        im_abs   <= 16'd0;
        valid_d1 <= 1'b0;
        addr_d1  <= 10'd0;
    end else begin
        re_abs   <= (re[15]) ? (~re + 1'b1) : re;
        im_abs   <= (im[15]) ? (~im + 1'b1) : im;
        valid_d1 <= fft_valid;
        addr_d1  <= addr_cnt;
    end
end

//=============================================================================
// 第2级：找最大值和最小值
//=============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        max_val  <= 16'd0;
        min_val  <= 16'd0;
        valid_d2 <= 1'b0;
        addr_d2  <= 10'd0;
    end else begin
        if (re_abs >= im_abs) begin
            max_val <= re_abs;
            min_val <= im_abs;
        end else begin
            max_val <= im_abs;
            min_val <= re_abs;
        end
        valid_d2 <= valid_d1;
        addr_d2  <= addr_d1;
    end
end

//=============================================================================
// 第3级：计算min_half
//=============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        min_half   <= 16'd0;
        max_val_d3 <= 16'd0;
        valid_d3   <= 1'b0;
        addr_d3    <= 10'd0;
    end else begin
        min_half   <= min_val >> 1;      // ✓ 只计算min_half
        max_val_d3 <= max_val;           // ✓ 延迟max_val
        valid_d3   <= valid_d2;
        addr_d3    <= addr_d2;
    end
end

//=============================================================================
// 第4级：计算幅度
//=============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        mag_calc <= 16'd0;
    end else begin
        mag_calc <= max_val_d3 + min_half;  // ✓ 使用同步的数据
    end
end

//=============================================================================
// 第5级：输出
//=============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        magnitude       <= 16'd0;
        magnitude_addr  <= 10'd0;
        magnitude_valid <= 1'b0;
    end else begin
        magnitude       <= mag_calc;
        magnitude_addr  <= addr_d3;      // ✓ 使用延迟的地址
        magnitude_valid <= valid_d3;
    end
end

endmodule