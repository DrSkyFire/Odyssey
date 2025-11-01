//=============================================================================
// 文件名: bin_to_bcd_pipelined.v
// 描述: 流水线二进制到BCD转换器
// 功能: 将16位二进制数转换为5位BCD码（最大99999）
// 优化: 使用流水线架构避免时序违例
//=============================================================================

module bin_to_bcd_pipelined #(
    parameter INPUT_WIDTH = 16,
    parameter BCD_DIGITS = 5
)(
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire [INPUT_WIDTH-1:0]       bin_in,
    input  wire                         convert_en,    // 转换使能
    output reg  [3:0]                   bcd_d0,        // 个位
    output reg  [3:0]                   bcd_d1,        // 十位
    output reg  [3:0]                   bcd_d2,        // 百位
    output reg  [3:0]                   bcd_d3,        // 千位
    output reg  [3:0]                   bcd_d4,        // 万位
    output reg                          valid          // 输出有效
);

// 流水线寄存器
reg [INPUT_WIDTH-1:0] bin_stage1;
reg [INPUT_WIDTH-1:0] bin_stage2;
reg [INPUT_WIDTH-1:0] bin_stage3;

// 中间结果
reg [INPUT_WIDTH-1:0] temp1, temp2, temp3, temp4;
reg [3:0] d0_s1, d1_s1, d2_s1, d3_s1, d4_s1;
reg [3:0] d0_s2, d1_s2, d2_s2, d3_s2, d4_s2;
reg [3:0] d0_s3, d1_s3, d2_s3, d3_s3, d4_s3;

// 有效信号流水线
reg valid_s1, valid_s2, valid_s3;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        // 第1级
        bin_stage1 <= 0;
        d0_s1 <= 0;
        d1_s1 <= 0;
        temp1 <= 0;
        valid_s1 <= 0;
        
        // 第2级
        bin_stage2 <= 0;
        d0_s2 <= 0;
        d1_s2 <= 0;
        d2_s2 <= 0;
        temp2 <= 0;
        valid_s2 <= 0;
        
        // 第3级
        bin_stage3 <= 0;
        d0_s3 <= 0;
        d1_s3 <= 0;
        d2_s3 <= 0;
        d3_s3 <= 0;
        temp3 <= 0;
        valid_s3 <= 0;
        
        // 输出
        bcd_d0 <= 0;
        bcd_d1 <= 0;
        bcd_d2 <= 0;
        bcd_d3 <= 0;
        bcd_d4 <= 0;
        valid <= 0;
    end else begin
        //=============================================================
        // 流水线第1级：计算个位和十位
        //=============================================================
        if (convert_en) begin
            bin_stage1 <= bin_in;
            d0_s1 <= bin_in % 10;           // 个位（优化：使用查找表）
            temp1 <= bin_in / 10;
            valid_s1 <= 1'b1;
        end else begin
            valid_s1 <= 1'b0;
        end
        
        //=============================================================
        // 流水线第2级：计算十位和百位
        //=============================================================
        if (valid_s1) begin
            bin_stage2 <= bin_stage1;
            d0_s2 <= d0_s1;
            d1_s2 <= temp1 % 10;            // 十位
            d2_s2 <= (temp1 / 10) % 10;     // 百位
            temp2 <= temp1 / 100;
            valid_s2 <= 1'b1;
        end else begin
            valid_s2 <= 1'b0;
        end
        
        //=============================================================
        // 流水线第3级：计算千位和万位
        //=============================================================
        if (valid_s2) begin
            bin_stage3 <= bin_stage2;
            d0_s3 <= d0_s2;
            d1_s3 <= d1_s2;
            d2_s3 <= d2_s2;
            d3_s3 <= temp2 % 10;            // 千位
            d4_s3 <= (temp2 / 10) % 10;     // 万位
            valid_s3 <= 1'b1;
        end else begin
            valid_s3 <= 1'b0;
        end
        
        //=============================================================
        // 输出级
        //=============================================================
        if (valid_s3) begin
            bcd_d0 <= d0_s3;
            bcd_d1 <= d1_s3;
            bcd_d2 <= d2_s3;
            bcd_d3 <= d3_s3;
            bcd_d4 <= d4_s3;
            valid <= 1'b1;
        end else begin
            valid <= 1'b0;
        end
    end
end

endmodule
