`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:Meyesemi 
// Engineer: Will
// 
// Create Date: 2023-01-29 20:31  
// Design Name:  
// Module Name: 
// Project Name: 
// Target Devices: Pango
// Tool Versions: 
// Description: 
//      
// Dependencies: 
// 
// Revision:
// Revision 1.0 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////
`define UD #1
module ms7210_ctl(
    input               clk,
    input               rstn,
                        
    output reg          init_over,
    output        [7:0] device_id,
    output reg          iic_trig ,
    output reg          w_r      ,
    output reg   [15:0] addr     ,
    output reg   [ 7:0] data_in  ,
    input               busy     ,
    input        [ 7:0] data_out ,
    input               byte_over 
);
    assign device_id = 8'hB2;
function [23:0] cmd_data;
input [5:0] index;
    begin
        case(index)
            // === 初始化阶段: 基础模块使能 ===
            6'd0     : cmd_data = {16'h1281,8'h04}; // PLL配置
            6'd1     : cmd_data = {16'h0016,8'h04}; // DVIN使能: dvin_en=1
            6'd2     : cmd_data = {16'h0009,8'h01}; // DVIN复位释放: dvin_sw_rstb=1
            6'd3     : cmd_data = {16'h0007,8'h09}; // 系统配置
            6'd4     : cmd_data = {16'h0008,8'hF0}; // 系统配置
            6'd5     : cmd_data = {16'h000A,8'hF0}; // 系统配置
            6'd6     : cmd_data = {16'h0006,8'h11}; // 系统配置
            6'd7     : cmd_data = {16'h0531,8'h84}; // HDCP配置
            
            // === DVIN模块配置 (基地址0x1200, 简写为0x09xx) ===
            6'd8     : cmd_data = {16'h1200,8'h01}; // dvin_sync_fmt=01: HS+VS+DE模式
            6'd9     : cmd_data = {16'h1201,8'h00}; // 标准数据映射: R[23:16], G[15:8], B[7:0]
            6'd10    : cmd_data = {16'h1202,8'h00}; // SDR模式 (148.5MHz单沿采样)
            6'd11    : cmd_data = {16'h1204,8'h00}; // dvin_mode_sel=000: 24-bit RGB444模式
            6'd12    : cmd_data = {16'h1206,8'h00}; // 极性不翻转 (HS/VS/DE正极性)
            
            // === 1080p时序参数配置 ===
            6'd13    : cmd_data = {16'h120C,8'h98}; // htotal_l = 2200 & 0xFF = 0x98
            6'd14    : cmd_data = {16'h120D,8'h08}; // htotal_h = 2200 >> 8 = 0x08
            6'd15    : cmd_data = {16'h120E,8'h65}; // vtotal_l = 1125 & 0xFF = 0x65
            6'd16    : cmd_data = {16'h120F,8'h04}; // vtotal_h = 1125 >> 8 = 0x04
            
            // === 色彩空间转换配置 (CSC基地址0x8000) ===
            6'd17    : cmd_data = {16'h8000,8'h00}; // src_csc=00: RGB输入
            
            // === HDMI TX中断使能 ===
            6'd18    : cmd_data = {16'h0920,8'h1E}; // 中断使能
            6'd19    : cmd_data = {16'h0018,8'h20}; // 中断配置
            6'd20    : cmd_data = {16'h05c0,8'hFE}; // HDMI配置
            
            // === EDID配置准备 ===
            6'd21    : cmd_data = {16'h000B,8'h00}; // EDID设置开始
            6'd22    : cmd_data = {16'h0507,8'h06}; // EDID控制
            6'd23    : cmd_data = {16'h0920,8'h5E}; // 中断使能更新
            
            // === 视频格式选择 ===
            6'd24    : cmd_data = {16'h0910,8'h10}; // 视频格式: 0x10=1080p@60Hz
            
            // === EDID RAM写入 ===
            6'd25    : cmd_data = {16'h000B,8'h11}; // EDID RAM使能
            6'd26    : cmd_data = {16'h050E,8'h00}; // EDID写入开始
            6'd27    : cmd_data = {16'h050A,8'h82}; // EDID地址
            6'd28    : cmd_data = {16'h0509,8'h02}; // EDID控制
            6'd29    : cmd_data = {16'h050B,8'h0D}; // EDID数据长度
            
            // === EDID数据块写入 (1080p EDID) ===
            6'd30    : cmd_data = {16'h050D,8'h06}; // EDID数据
            6'd31    : cmd_data = {16'h050D,8'h11}; // EDID数据
            6'd32    : cmd_data = {16'h050D,8'h58}; // EDID数据
            6'd33    : cmd_data = {16'h050D,8'h00}; // EDID数据
            6'd34    : cmd_data = {16'h050D,8'h00}; // EDID数据
            6'd35    : cmd_data = {16'h050D,8'h00}; // EDID数据
            6'd36    : cmd_data = {16'h050D,8'h00}; // EDID数据
            6'd37    : cmd_data = {16'h050D,8'h00}; // EDID数据
            6'd38    : cmd_data = {16'h050D,8'h00}; // EDID数据
            6'd39    : cmd_data = {16'h050D,8'h00}; // EDID数据
            6'd40    : cmd_data = {16'h050D,8'h00}; // EDID数据
            6'd41    : cmd_data = {16'h050D,8'h00}; // EDID数据
            6'd42    : cmd_data = {16'h050D,8'h00}; // EDID数据
            
            // === EDID写入完成 ===
            6'd43    : cmd_data = {16'h050E,8'h40}; // EDID写入结束标志
            6'd44    : cmd_data = {16'h0507,8'h00}; // EDID控制复位
       endcase 
    end
endfunction
    //===========================================================================
    //  MS7210 driver control FSM
    //===========================================================================
    parameter    IDLE   = 6'b00_0001;
    parameter    CONECT = 6'b00_0010;
    parameter    INIT   = 6'b00_0100;
    parameter    WAIT   = 6'b00_1000;
    parameter    SETING = 6'b01_0000;
    parameter    STA_RD = 6'b10_0000;
    reg [ 5:0]   state;
    reg [ 5:0]   state_n;
    reg [ 4:0]   dri_cnt;
    reg [21:0]   delay_cnt;
    reg [ 5:0]   cmd_index;

    reg          busy_1d;
    wire         busy_falling;
    
    assign busy_falling = ((~busy) & busy_1d);
    always @(posedge clk)
    begin
        busy_1d <= busy;
    end
    //===========================================================================
    //  MS7210 driver control FSM    First Step
    always @(posedge clk)
    begin
        if(!rstn)
            state <= IDLE;
        else
            state <= state_n;
    end
    
    //===========================================================================
    //  MS7210 driver control FSM    Second Step
    always @(*)
    begin
        state_n = state;
        case(state)
            IDLE     : begin
                state_n = CONECT;
            end
            CONECT   : begin
                if(dri_cnt == 5'd1 && busy_falling && data_out == 8'h5A)
                    state_n = INIT;
                else
                    state_n = state;
            end
            INIT     : begin
                if(dri_cnt == 5'd20 && busy_falling)  // 初始化阶段: index 0-20
                    state_n = WAIT;
                else
                    state_n = state;
            end
            WAIT     : begin
                if(delay_cnt == 22'h30D399)//)//
                    state_n = SETING;
                else
                    state_n = state;
            end
            SETING   : begin
                if(dri_cnt == 5'd24 && busy_falling)  // 设置阶段: index 21-44
                    state_n = STA_RD;
                else
                    state_n = state;
            end
            STA_RD   : begin
                state_n = state;
            end
            default  : begin
                state_n = IDLE;
            end
        endcase
    end
    
    //===========================================================================
    //  MS7210 driver control FSM    Third Step
    always @(posedge clk)
    begin
        if(!rstn)
            dri_cnt <= 5'd0;
        else
        begin
            case(state)
                IDLE     ,
                WAIT     ,
                STA_RD   : dri_cnt <= 5'd0;
                CONECT   : begin
                    if(busy_falling)
                    begin
                        if(dri_cnt == 5'd1)
                            dri_cnt <= 5'd0;
                        else
                            dri_cnt <= dri_cnt + 5'd1;
                    end
                    else
                        dri_cnt <= dri_cnt;
                end
                INIT     : begin
                    if(busy_falling)
                    begin
                        if(dri_cnt == 5'd20)  // 初始化阶段: index 0-20
                            dri_cnt <= 5'd0;
                        else
                            dri_cnt <= dri_cnt + 5'd1;
                    end
                    else
                        dri_cnt <= dri_cnt;
                end
                SETING   : begin
                    if(busy_falling)
                    begin
                        if(dri_cnt == 5'd24)  // 设置阶段: index 21-44
                            dri_cnt <= 5'd0;
                        else
                            dri_cnt <= dri_cnt + 5'd1;
                    end
                    else
                        dri_cnt <= dri_cnt;
                end
                default  : dri_cnt <= 5'd0;
            endcase
        end
    end
    
    always @(posedge clk)
    begin
        if(state == WAIT)
        begin
            if(delay_cnt == 22'h30D399)
                delay_cnt <= 22'd0;
            else
                delay_cnt <= delay_cnt + 22'd1;
        end
        else
            delay_cnt <= 22'd0;
    end
    
    always @(posedge clk)
    begin
        if(!rstn)
            iic_trig <= 1'd0;
        else
        begin
            case(state)
                IDLE     : iic_trig <= 1'b1;
                WAIT     : iic_trig <= (delay_cnt == 22'h30D399);
                CONECT   ,
                INIT     ,
                SETING   ,
                STA_RD   : iic_trig <= busy_falling;
                default  : iic_trig <= 1'd0;
            endcase
        end
    end
    
    always @(posedge clk)
    begin
        if(!rstn)
            w_r <= 1'd1;
        else
        begin
            case(state)
                IDLE     : w_r <= 1'b1;
                CONECT   : begin
                    if(dri_cnt == 5'd0 && busy_falling)
                        w_r <= 1'b0;
                    else if(dri_cnt == 5'd1 && busy_falling)
                        w_r <= 1'b1;
                    else
                        w_r <= w_r;
                end
                INIT     ,
                WAIT     ,
                STA_RD   : w_r <= w_r;
                SETING   : begin
                    if(dri_cnt == 5'd24 && busy_falling)  // 设置阶段完成后读取状态
                        w_r <= 1'b0;
                    else
                        w_r <= w_r;
                end
                default  : w_r <= 1'b1;
            endcase
        end
    end
    
    always @(posedge clk)
    begin
        if(!rstn)
            cmd_index <= 6'd0;
        else
        begin
            case(state)
                IDLE     : cmd_index <= 6'd0;
                CONECT   : cmd_index <= 6'd0;
                INIT     ,
                SETING   :begin
                    if(byte_over)
                        cmd_index <= cmd_index + 1'b1;
                    else
                        cmd_index <= cmd_index;
                end
                WAIT     ,
                STA_RD   : cmd_index <= cmd_index;
                default  : cmd_index <= 6'd0;
            endcase
        end
    end
    
    reg [23:0] cmd_iic;
    always@(posedge clk)
	begin
		if(~rstn)
			cmd_iic <= 0;
		else if(state == IDLE)
			cmd_iic <= 24'd0;
        else //if(state == WAIT || state == SETING)
            cmd_iic <= cmd_data(cmd_index);
	end
    
    always @(posedge clk)
    begin
        if(!rstn)
        begin
            addr    <= 16'd0;
            data_in <= 8'd0;
        end
        else
        begin
            case(state)
                IDLE     : begin
                    addr    <= 16'h0003;
                    data_in <= 8'h5A;
                end
                CONECT   : begin
                    if(dri_cnt == 5'd1 && busy_falling && data_out == 8'h5A)
                    begin
                        addr    <= cmd_iic[23:8];
                        data_in <= cmd_iic[ 7:0];
                    end
                    else
                    begin
                        addr    <= addr;
                        data_in <= data_in;
                    end
                end
                INIT     ,
                WAIT     ,
                SETING   :begin
                	addr    <= cmd_iic[23:8];
                    data_in <= cmd_iic[ 7:0];
                end
                STA_RD   :begin
                    addr    <= 16'h0502;
                    data_in <= 8'd0;
                end
                default  : begin
                    addr    <= 0;
                    data_in <= 0;
                end
            endcase
        end
    end

    always @(posedge clk)
    begin
    	if(!rstn)
    	    init_over <= 1'b0;
    	else if(state == STA_RD)// && busy_falling)
    	    init_over <= 1'b1;
    end

endmodule
