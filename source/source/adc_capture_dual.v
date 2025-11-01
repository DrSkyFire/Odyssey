//=============================================================================
// 文件名: adc_capture_dual_10bit.v
// 描述: 双通道10位ADC同步采集模块
//=============================================================================

module adc_capture_dual (
    input  wire         clk,                // ADC采样时钟 (35MHz)
    input  wire         rst_n,
    
    // 通道1接口
    input  wire [9:0]   adc_ch1_in,
    output wire         adc_ch1_clk_out,
    
    // 通道2接口
    input  wire [9:0]   adc_ch2_in,
    output wire         adc_ch2_clk_out,
    
    // 数据输出
    output reg  [9:0]   ch1_data_out,
    output reg  [9:0]   ch2_data_out,
    output reg          data_valid,
    
    // 控制
    input  wire         enable
);

// 两个通道共用时钟和使能
assign adc_ch1_clk_out = clk;
assign adc_ch2_clk_out = clk;

// 两级寄存器同步
reg [9:0] ch1_d1, ch1_d2;
reg [9:0] ch2_d1, ch2_d2;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        ch1_d1 <= 10'd0;
        ch1_d2 <= 10'd0;
        ch2_d1 <= 10'd0;
        ch2_d2 <= 10'd0;
    end else begin
        ch1_d1 <= adc_ch1_in;
        ch1_d2 <= ch1_d1;
        ch2_d1 <= adc_ch2_in;
        ch2_d2 <= ch2_d1;
    end
end

// 数据输出
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        ch1_data_out <= 10'd0;
        ch2_data_out <= 10'd0;
        data_valid   <= 1'b0;
    end else if (enable) begin
        ch1_data_out <= ch1_d2;
        ch2_data_out <= ch2_d2;
        data_valid   <= 1'b1;
    end else begin
        ch1_data_out <= 10'd0;
        ch2_data_out <= 10'd0;
        data_valid   <= 1'b0;
    end
end

endmodule