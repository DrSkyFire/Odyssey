//=============================================================================
// 文件名: hdmi_display_ctrl.v (完全修复版)
//=============================================================================

module hdmi_display_ctrl (
    input  wire         clk_pixel,
    input  wire         rst_n,
    
    input  wire [15:0]  spectrum_data,
    output reg  [9:0]   spectrum_addr,
    input  wire [15:0]  time_data,
    
    input  wire [15:0]  freq,
    input  wire [15:0]  amplitude,
    input  wire [15:0]  duty,
    input  wire [15:0]  thd,
    
    input  wire [1:0]   work_mode,
    
    output wire [23:0]  rgb_out,
    output wire         de_out,
    output wire         hs_out,
    output wire         vs_out
);

//=============================================================================
// 时序参数
//=============================================================================
localparam H_ACTIVE     = 1280;
localparam H_FP         = 110;
localparam H_SYNC       = 40;
localparam H_BP         = 220;
localparam H_TOTAL      = 1650;

localparam V_ACTIVE     = 720;
localparam V_FP         = 5;
localparam V_SYNC       = 5;
localparam V_BP         = 20;
localparam V_TOTAL      = 750;

//=============================================================================
// 信号定义
//=============================================================================
reg [11:0] h_cnt;
reg [11:0] v_cnt;
reg        h_active;
reg        v_active;
wire       video_active;

reg [11:0] pixel_x;
reg [11:0] pixel_y;

reg        hs_internal;
reg        vs_internal;

// ✓ 添加延迟寄存器（关键！）
reg [11:0] pixel_x_d1, pixel_x_d2;
reg [11:0] pixel_y_d1, pixel_y_d2;
reg        video_active_d1, video_active_d2;
reg [1:0]  work_mode_d1, work_mode_d2;

reg [23:0] rgb_out_reg;
reg        de_out_reg;
reg        hs_out_reg;
reg        vs_out_reg;

reg [23:0] rgb_data;
reg [11:0] spectrum_height_calc;

//=============================================================================
// 行计数器
//=============================================================================
always @(posedge clk_pixel or negedge rst_n) begin
    if (!rst_n)
        h_cnt <= 12'd0;
    else if (h_cnt == H_TOTAL - 1)
        h_cnt <= 12'd0;
    else
        h_cnt <= h_cnt + 1'b1;
end

//=============================================================================
// 场计数器
//=============================================================================
always @(posedge clk_pixel or negedge rst_n) begin
    if (!rst_n)
        v_cnt <= 12'd0;
    else if (h_cnt == H_TOTAL - 1) begin
        if (v_cnt == V_TOTAL - 1)
            v_cnt <= 12'd0;
        else
            v_cnt <= v_cnt + 1'b1;
    end
end

//=============================================================================
// 同步信号
//=============================================================================
always @(posedge clk_pixel or negedge rst_n) begin
    if (!rst_n)
        hs_internal <= 1'b1;
    else if (h_cnt == H_ACTIVE + H_FP)
        hs_internal <= 1'b0;
    else if (h_cnt == H_ACTIVE + H_FP + H_SYNC)
        hs_internal <= 1'b1;
end

always @(posedge clk_pixel or negedge rst_n) begin
    if (!rst_n)
        vs_internal <= 1'b1;
    else if (v_cnt == V_ACTIVE + V_FP)
        vs_internal <= 1'b0;
    else if (v_cnt == V_ACTIVE + V_FP + V_SYNC)
        vs_internal <= 1'b1;
end

//=============================================================================
// 有效区域标志
//=============================================================================
always @(posedge clk_pixel or negedge rst_n) begin
    if (!rst_n) begin
        h_active <= 1'b0;
        v_active <= 1'b0;
    end else begin
        h_active <= (h_cnt < H_ACTIVE);
        v_active <= (v_cnt < V_ACTIVE);
    end
end

assign video_active = h_active && v_active;

//=============================================================================
// 像素坐标
//=============================================================================
always @(posedge clk_pixel or negedge rst_n) begin
    if (!rst_n) begin
        pixel_x <= 12'd0;
        pixel_y <= 12'd0;
    end else if (video_active) begin
        pixel_x <= h_cnt;
        pixel_y <= v_cnt;
    end else begin
        pixel_x <= 12'd0;
        pixel_y <= 12'd0;
    end
end

//=============================================================================
// 频谱地址生成（提前生成）
//=============================================================================
always @(posedge clk_pixel or negedge rst_n) begin
    if (!rst_n)
        spectrum_addr <= 10'd0;
    else begin
        if (h_cnt < 1280)
            spectrum_addr <= h_cnt[11:2];
        else
            spectrum_addr <= 10'd1023;
    end
end

//=============================================================================
// 坐标和控制信号延迟（匹配RAM读延迟）
//=============================================================================
always @(posedge clk_pixel or negedge rst_n) begin
    if (!rst_n) begin
        pixel_x_d1 <= 12'd0;
        pixel_x_d2 <= 12'd0;
        pixel_y_d1 <= 12'd0;
        pixel_y_d2 <= 12'd0;
        video_active_d1 <= 1'b0;
        video_active_d2 <= 1'b0;
        work_mode_d1 <= 2'd0;
        work_mode_d2 <= 2'd0;
    end else begin
        // 延迟2拍
        pixel_x_d1 <= pixel_x;
        pixel_x_d2 <= pixel_x_d1;
        pixel_y_d1 <= pixel_y;
        pixel_y_d2 <= pixel_y_d1;
        video_active_d1 <= video_active;
        video_active_d2 <= video_active_d1;
        work_mode_d1 <= work_mode;
        work_mode_d2 <= work_mode_d1;
    end
end

//=============================================================================
// RGB数据生成（使用延迟后的坐标）
//=============================================================================
always @(*) begin
    rgb_data = 24'h000000;
    spectrum_height_calc = 12'd0;
    
    if (video_active_d2) begin  // ← 使用延迟后的video_active
        // 边框
        if (pixel_x_d2 < 5 || pixel_x_d2 >= H_ACTIVE - 5 ||  // ← 使用延迟后的坐标
            pixel_y_d2 < 5 || pixel_y_d2 >= V_ACTIVE - 5) begin
            rgb_data = 24'hFFFFFF;
        end
        // 频域模式
        else if (work_mode_d2 == 2'd1) begin  // ← 使用延迟后的work_mode
            if (pixel_y_d2 >= 100 && pixel_y_d2 < 620) begin
                // 计算频谱高度
                if (spectrum_data[15:10] > 0)
                    spectrum_height_calc = {spectrum_data[15:10], 4'b0};
                else if (spectrum_data[9:6] > 0)
                    spectrum_height_calc = {4'b0, spectrum_data[9:6], 4'b0};
                else
                    spectrum_height_calc = {8'b0, spectrum_data[5:2]};
                
                if (spectrum_height_calc > 519)
                    spectrum_height_calc = 12'd519;
                
                // 判断是否在频谱柱内
                if (pixel_y_d2 >= (620 - spectrum_height_calc)) begin
                    if (pixel_x_d2 < 426)
                        rgb_data = 24'h0000FF;
                    else if (pixel_x_d2 < 853)
                        rgb_data = 24'h00FF00;
                    else
                        rgb_data = 24'hFF0000;
                end else begin
                    rgb_data = 24'h202020;
                end
            end
            else if (pixel_y_d2 >= 650 && pixel_y_d2 < 710) begin
                rgb_data = 24'h404040;
            end
        end
        // 时域模式
        else if (work_mode_d2 == 2'd0) begin
            rgb_data = 24'h00FF00;
        end
        // 参数测量模式
        else if (work_mode_d2 == 2'd2) begin
            rgb_data = 24'h404040;
        end
    end
end

//=============================================================================
// 输出寄存器
//=============================================================================
always @(posedge clk_pixel or negedge rst_n) begin
    if (!rst_n) begin
        rgb_out_reg <= 24'h000000;
        de_out_reg  <= 1'b0;
        hs_out_reg  <= 1'b1;
        vs_out_reg  <= 1'b1;
    end else begin
        rgb_out_reg <= rgb_data;
        de_out_reg  <= video_active_d2;  // ← 使用延迟后的
        hs_out_reg  <= hs_internal;
        vs_out_reg  <= vs_internal;
    end
end

assign rgb_out = rgb_out_reg;
assign de_out  = de_out_reg;
assign hs_out  = hs_out_reg;
assign vs_out  = vs_out_reg;

endmodule