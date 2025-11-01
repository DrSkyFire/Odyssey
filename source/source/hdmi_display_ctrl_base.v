//=============================================================================
// ????? hdmi_display_ctrl.v (????????- ????????+ ???????????)
// ???: 1080p HDMI????????
//       - ????????????/???????????????
//       - ?????????????????????
//       - ??????????????CH1(???) CH2(???)
//       - ???????????+ ?????? + ??????
//=============================================================================

module hdmi_display_ctrl (
    input  wire         clk_pixel,
    input  wire         rst_n,
    
    // ?????????????
    input  wire [15:0]  ch1_data,       // ???1????????????????
    input  wire [15:0]  ch2_data,       // ???2????????????????
    output reg  [12:0]  spectrum_addr,  // ?????13??????8192??FT
    
    // ???????????
    input  wire [15:0]  ch1_freq,           // CH1??? (Hz)
    input  wire [15:0]  ch1_amplitude,      // CH1???
    input  wire [15:0]  ch1_duty,           // CH1?????(0-1000 = 0-100%)
    input  wire [15:0]  ch1_thd,            // CH1 THD (0-1000 = 0-100%)
    input  wire [15:0]  ch2_freq,           // CH2??? (Hz)
    input  wire [15:0]  ch2_amplitude,      // CH2???
    input  wire [15:0]  ch2_duty,           // CH2?????(0-1000 = 0-100%)
    input  wire [15:0]  ch2_thd,            // CH2 THD (0-1000 = 0-100%)
    input  wire [15:0]  phase_diff,     // ?????(0-3599 = 0-359.9?)
    
    // ??AI?????????
    input  wire [2:0]   ch1_waveform_type,   // CH1??????: 0=???,1=???,2=???,3=???,4=???,5=???
    input  wire [7:0]   ch1_confidence,      // CH1?????(0-100%)
    input  wire         ch1_ai_valid,        // CH1?????????
    input  wire [2:0]   ch2_waveform_type,   // CH2??????
    input  wire [7:0]   ch2_confidence,      // CH2?????
    input  wire         ch2_ai_valid,        // CH2?????????
    
    // ??????????????????urrent_channel??
    input  wire         ch1_enable,     // ???1??????
    input  wire         ch2_enable,     // ???2??????
    
    input  wire [1:0]   work_mode,
    
    // HDMI???
    output wire [23:0]  rgb_out,
    output wire         de_out,
    output wire         hs_out,
    output wire         vs_out
);

//=============================================================================
// ?????? - 1080p@60Hz
//=============================================================================
localparam H_ACTIVE     = 1920;
localparam H_FP         = 88;
localparam H_SYNC       = 44;
localparam H_BP         = 148;
localparam H_TOTAL      = 2200;

localparam V_ACTIVE     = 1080;
localparam V_FP         = 4;
localparam V_SYNC       = 5;
localparam V_BP         = 36;
localparam V_TOTAL      = 1125;

//=============================================================================
// ????????? (1080p)
//=============================================================================
localparam SPECTRUM_Y_START = 75;       // ?????????Y
localparam SPECTRUM_Y_END   = 825;      // ?????????Y
localparam PARAM_Y_START    = 870;      // ?????????Y
localparam PARAM_Y_END      = 1080;     // ?????????Y???????????????

// ?????????????
localparam AXIS_LEFT_MARGIN = 80;       // ???Y???????????
localparam AXIS_BOTTOM_HEIGHT = 40;     // ???X???????????
localparam TICK_LENGTH = 8;             // ????????

//=============================================================================
// ??????
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

// ????????????RAM?????OM?????
reg [11:0] pixel_x_d1, pixel_x_d2, pixel_x_d3, pixel_x_d4;  // ?????d4?????????
reg [11:0] pixel_y_d1, pixel_y_d2, pixel_y_d3, pixel_y_d4;  // ?????d4?????????
reg        video_active_d1, video_active_d2, video_active_d3, video_active_d4;  // ?????d4
reg [1:0]  work_mode_d1, work_mode_d2, work_mode_d3, work_mode_d4;  // ?????d4

// ??????????????????????????
reg        grid_x_flag, grid_y_flag;

// ????????????????
reg [15:0] ch1_data_q, ch2_data_q;  // ?????????????
reg [11:0] ch1_waveform_height;     // CH1??????
reg [11:0] ch2_waveform_height;     // CH2??????

// ?????????
reg [15:0] time_data_q;             // ?????????????????
reg [15:0] spectrum_data_q;         // ?????????????????
reg [11:0] waveform_height;         // ??????????????????
wire [11:0] time_sample_x;          // ?????????????920?????192??????????????

// ?????????
localparam WAVEFORM_CENTER_Y = (SPECTRUM_Y_START + SPECTRUM_Y_END) / 2;  // ????????
reg        grid_x_flag_d1, grid_y_flag_d1;
reg        grid_x_flag_d2, grid_y_flag_d2;
reg        grid_x_flag_d3, grid_y_flag_d3;
// ?????????????????????
reg        grid_x_flag_d4, grid_y_flag_d4;

// ???????????????,???????????
reg [6:0]  grid_x_cnt;  // 0-99 ???
reg [5:0]  grid_y_cnt;  // 0-49 ???

// (??spectrum_data_q???????????????????????????????

// ???????????????????
reg        ch1_hit, ch2_hit;    // ???????????tage 4????????
reg [11:0] ch1_spectrum_height; // CH1??????
reg [11:0] ch2_spectrum_height; // CH2??????

// ???????????Stage 3????????
reg [11:0] ch1_waveform_calc_d1, ch2_waveform_calc_d1;  // ????????????
reg [11:0] ch1_spectrum_calc_d1, ch2_spectrum_calc_d1;  // ????????????
reg        ch1_enable_d4, ch2_enable_d4;                 // ?????????

// ?????3???????????????????????lways????????
reg        ch1_spec_hit, ch2_spec_hit;

// ????????????????
reg        y_axis_tick;      // Y?????????
reg        x_axis_tick;      // X?????????
reg        in_axis_label;    // ??????????????

// ???????????Y?????????????????ixel_y??????????????
reg [7:0]  y_axis_char_code; // Y????????????
reg        y_axis_char_valid; // Y??????????????
reg [4:0]  y_axis_char_row;  // Y????????
reg [11:0] y_axis_char_col;  // Y????????

reg [23:0] rgb_out_reg;
reg        de_out_reg;
reg        hs_out_reg;
reg        vs_out_reg;

reg [23:0] rgb_data;
reg [11:0] spectrum_height_calc;

// ?????????
wire [15:0] char_pixel_row;
reg [7:0]   char_code;    // ?????8??????ASCII??(0-127)
reg [4:0]   char_row;     // ?????? (0-31)
reg [11:0]  char_col;     // ??????????2??????????????????
reg         in_char_area;
reg [23:0]  char_color;

// ??????????har_code?????????
reg [7:0]   char_code_d1;
reg [4:0]   char_row_d1;
reg [11:0]  char_col_d1;
reg         in_char_area_d1;

// ??????
reg [3:0]   digit_0, digit_1, digit_2, digit_3, digit_4;

// CH1????????????????????????????????
reg [3:0]   ch1_freq_d0, ch1_freq_d1, ch1_freq_d2, ch1_freq_d3, ch1_freq_d4;
reg [3:0]   ch1_amp_d0, ch1_amp_d1, ch1_amp_d2, ch1_amp_d3;
reg [3:0]   ch1_duty_d0, ch1_duty_d1, ch1_duty_d2;
reg [3:0]   ch1_thd_d0, ch1_thd_d1, ch1_thd_d2;

// CH2?????????
reg [3:0]   ch2_freq_d0, ch2_freq_d1, ch2_freq_d2, ch2_freq_d3, ch2_freq_d4;
reg [3:0]   ch2_amp_d0, ch2_amp_d1, ch2_amp_d2, ch2_amp_d3;
reg [3:0]   ch2_duty_d0, ch2_duty_d1, ch2_duty_d2;
reg [3:0]   ch2_thd_d0, ch2_thd_d1, ch2_thd_d2;

// ?????????
reg [3:0]   phase_d0, phase_d1, phase_d2, phase_d3;

//=============================================================================
// ??????
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
// ??????
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
// ?????? (?????- ??S7210???)
// ?????????? hs = (h_cnt < H_SYNC)
//=============================================================================
always @(posedge clk_pixel or negedge rst_n) begin
    if (!rst_n)
        hs_internal <= 1'b0;
    else
        hs_internal <= (h_cnt < H_SYNC);  // ??0???????????????
end

always @(posedge clk_pixel or negedge rst_n) begin
    if (!rst_n)
        vs_internal <= 1'b0;
    else begin
        if (v_cnt == 12'd0)
            vs_internal <= 1'b1;        // ???????????VS???
        else if (v_cnt == V_SYNC)
            vs_internal <= 1'b0;        // V_SYNC????????S???
        else
            vs_internal <= vs_internal; // ???????????????
    end
end

//=============================================================================
// ????????? (?????? - ???????????
//=============================================================================
wire h_active_comb = (h_cnt >= (H_SYNC + H_BP)) && (h_cnt <= (H_TOTAL - H_FP - 1));
wire v_active_comb = (v_cnt >= (V_SYNC + V_BP)) && (v_cnt <= (V_TOTAL - V_FP - 1));
assign video_active = h_active_comb && v_active_comb;

// ?????????????????????????????
always @(posedge clk_pixel or negedge rst_n) begin
    if (!rst_n) begin
        h_active <= 1'b0;
        v_active <= 1'b0;
    end else begin
        h_active <= h_active_comb;
        v_active <= v_active_comb;
    end
end

//=============================================================================
// ?????? (?????????????????
//=============================================================================
always @(posedge clk_pixel or negedge rst_n) begin
    if (!rst_n) begin
        pixel_x <= 12'd0;
        pixel_y <= 12'd0;
    end else begin
        // ?????YNC+BP???????
        if (h_cnt >= (H_SYNC + H_BP))
            pixel_x <= h_cnt - (H_SYNC + H_BP);
        else
            pixel_x <= 12'd0;
            
        if (v_cnt >= (V_SYNC + V_BP))
            pixel_y <= v_cnt - (V_SYNC + V_BP);
        else
            pixel_y <= 12'd0;
    end
end

//=============================================================================
// ?????????????????????????????
//=============================================================================
always @(posedge clk_pixel or negedge rst_n) begin
    if (!rst_n) begin
        grid_x_cnt <= 7'd0;
        grid_x_flag <= 1'b0;
    end else begin
        if (h_cnt == H_TOTAL - 1) begin
            grid_x_cnt <= 7'd0;
            grid_x_flag <= 1'b1;
        end else if (grid_x_cnt == 7'd99) begin
            grid_x_cnt <= 7'd0;
            grid_x_flag <= 1'b1;
        end else begin
            grid_x_cnt <= grid_x_cnt + 1'b1;
            grid_x_flag <= 1'b0;
        end
    end
end

always @(posedge clk_pixel or negedge rst_n) begin
    if (!rst_n) begin
        grid_y_cnt <= 6'd0;
        grid_y_flag <= 1'b0;
    end else begin
        if (h_cnt == H_TOTAL - 1) begin
            if (v_cnt == V_TOTAL - 1) begin
                grid_y_cnt <= 6'd0;
                grid_y_flag <= 1'b1;
            end else if (grid_y_cnt == 6'd49) begin
                grid_y_cnt <= 6'd0;
                grid_y_flag <= 1'b1;
            end else begin
                grid_y_cnt <= grid_y_cnt + 1'b1;
                grid_y_flag <= (grid_y_cnt + 1'b1 == 6'd49);
            end
        end
    end
end

//=============================================================================
// ??????????????????
// ?????????????????????s/2???4096??in??
// ???????5MHz???????????7.5MHz
// ?????????1840?????0-1919??????4096??????
// ????????pectrum_addr = ((h_cnt - 80) * 4096) / 1840 ??(h_cnt - 80) * 2.227
//=============================================================================
reg [11:0] h_offset;  // ?????????h_cnt - AXIS_LEFT_MARGIN??

always @(posedge clk_pixel or negedge rst_n) begin
    if (!rst_n) begin
        spectrum_addr <= 13'd0;
        h_offset <= 12'd0;
    end
    else begin
        if (h_cnt < AXIS_LEFT_MARGIN) begin
            // ???Y??????????????
            spectrum_addr <= 13'd0;
            h_offset <= 12'd0;
        end
        else if (h_cnt < H_ACTIVE) begin
            // ??????????? = 80-1919
            h_offset <= h_cnt - AXIS_LEFT_MARGIN;
            // spectrum_addr = h_offset * 2 + h_offset / 4 ??h_offset * 2.25
            spectrum_addr <= (h_offset << 1) + {2'b00, h_offset[11:2]};
        end
        else begin
            spectrum_addr <= 13'd4095;  // ?????????????????????
            h_offset <= 12'd0;
        end
    end
end

//=============================================================================
// ????????????????????????????????????????
//=============================================================================
always @(posedge clk_pixel or negedge rst_n) begin
    if (!rst_n) begin
        ch1_freq_d0 <= 4'd0; ch1_freq_d1 <= 4'd0; ch1_freq_d2 <= 4'd0; ch1_freq_d3 <= 4'd0; ch1_freq_d4 <= 4'd0;
        ch1_amp_d0 <= 4'd0; ch1_amp_d1 <= 4'd0; ch1_amp_d2 <= 4'd0; ch1_amp_d3 <= 4'd0;
        ch1_duty_d0 <= 4'd0; ch1_duty_d1 <= 4'd0; ch1_duty_d2 <= 4'd0;
        ch1_thd_d0 <= 4'd0; ch1_thd_d1 <= 4'd0; ch1_thd_d2 <= 4'd0;
        ch2_freq_d0 <= 4'd0; ch2_freq_d1 <= 4'd0; ch2_freq_d2 <= 4'd0; ch2_freq_d3 <= 4'd0; ch2_freq_d4 <= 4'd0;
        ch2_amp_d0 <= 4'd0; ch2_amp_d1 <= 4'd0; ch2_amp_d2 <= 4'd0; ch2_amp_d3 <= 4'd0;
        ch2_duty_d0 <= 4'd0; ch2_duty_d1 <= 4'd0; ch2_duty_d2 <= 4'd0;
        ch2_thd_d0 <= 4'd0; ch2_thd_d1 <= 4'd0; ch2_thd_d2 <= 4'd0;
        phase_d0 <= 4'd0; phase_d1 <= 4'd0; phase_d2 <= 4'd0; phase_d3 <= 4'd0;
    end else begin
        // ??????????????_cnt == 0, h_cnt == 0??????????????
        if (v_cnt == 12'd0 && h_cnt == 12'd0) begin
            // CH1???????????
            ch1_freq_d0 <= ch1_freq % 10;
            ch1_freq_d1 <= (ch1_freq / 10) % 10;
            ch1_freq_d2 <= (ch1_freq / 100) % 10;
            ch1_freq_d3 <= (ch1_freq / 1000) % 10;
            ch1_freq_d4 <= (ch1_freq / 10000) % 10;
            
            // CH1???????????
            ch1_amp_d0 <= ch1_amplitude % 10;
            ch1_amp_d1 <= (ch1_amplitude / 10) % 10;
            ch1_amp_d2 <= (ch1_amplitude / 100) % 10;
            ch1_amp_d3 <= (ch1_amplitude / 1000) % 10;
            
            // CH1??????3??????0-100.0??
            ch1_duty_d0 <= ch1_duty % 10;
            ch1_duty_d1 <= (ch1_duty / 10) % 10;
            ch1_duty_d2 <= (ch1_duty / 100) % 10;
            
            // CH1 THD????????0-100.0??
            ch1_thd_d0 <= ch1_thd % 10;
            ch1_thd_d1 <= (ch1_thd / 10) % 10;
            ch1_thd_d2 <= (ch1_thd / 100) % 10;
            
            // CH2???????????
            ch2_freq_d0 <= ch2_freq % 10;
            ch2_freq_d1 <= (ch2_freq / 10) % 10;
            ch2_freq_d2 <= (ch2_freq / 100) % 10;
            ch2_freq_d3 <= (ch2_freq / 1000) % 10;
            ch2_freq_d4 <= (ch2_freq / 10000) % 10;
            
            // CH2???????????
            ch2_amp_d0 <= ch2_amplitude % 10;
            ch2_amp_d1 <= (ch2_amplitude / 10) % 10;
            ch2_amp_d2 <= (ch2_amplitude / 100) % 10;
            ch2_amp_d3 <= (ch2_amplitude / 1000) % 10;
            
            // CH2??????3??????0-100.0??
            ch2_duty_d0 <= ch2_duty % 10;
            ch2_duty_d1 <= (ch2_duty / 10) % 10;
            ch2_duty_d2 <= (ch2_duty / 100) % 10;
            
            // CH2 THD????????0-100.0??
            ch2_thd_d0 <= ch2_thd % 10;
            ch2_thd_d1 <= (ch2_thd / 10) % 10;
            ch2_thd_d2 <= (ch2_thd / 100) % 10;
            
            // ??????4??????0-359.9??
            phase_d0 <= phase_diff % 10;
            phase_d1 <= (phase_diff / 10) % 10;
            phase_d2 <= (phase_diff / 100) % 10;
            phase_d3 <= (phase_diff / 1000) % 10;
        end
    end
end

//=============================================================================
// ??????????????????RAM??????
//=============================================================================
always @(posedge clk_pixel or negedge rst_n) begin
    if (!rst_n) begin
        pixel_x_d1 <= 12'd0;
        pixel_x_d2 <= 12'd0;
        pixel_x_d3 <= 12'd0;
        pixel_x_d4 <= 12'd0;  // ?????
        pixel_y_d1 <= 12'd0;
        pixel_y_d2 <= 12'd0;
        pixel_y_d3 <= 12'd0;
        pixel_y_d4 <= 12'd0;  // ?????
        video_active_d1 <= 1'b0;
        video_active_d2 <= 1'b0;
        video_active_d3 <= 1'b0;
        video_active_d4 <= 1'b0;  // ?????
        work_mode_d1 <= 2'd0;
        work_mode_d2 <= 2'd0;
        work_mode_d3 <= 2'd0;
        work_mode_d4 <= 2'd0;  // ?????
        grid_x_flag_d1 <= 1'b0;
        grid_x_flag_d2 <= 1'b0;
        grid_x_flag_d3 <= 1'b0;
        grid_y_flag_d1 <= 1'b0;
        grid_y_flag_d2 <= 1'b0;
        grid_y_flag_d3 <= 1'b0;
        spectrum_data_q <= 16'd0;
        
        // ??????????har_code????????
        char_code_d1 <= 8'd32;
        char_row_d1 <= 5'd0;
        char_col_d1 <= 12'd0;
        in_char_area_d1 <= 1'b0;
    end else begin
        // ???4?????????????????
        pixel_x_d1 <= pixel_x;
        pixel_x_d2 <= pixel_x_d1;
        pixel_x_d3 <= pixel_x_d2;
        pixel_x_d4 <= pixel_x_d3;  // ?????
        pixel_y_d1 <= pixel_y;
        pixel_y_d2 <= pixel_y_d1;
        pixel_y_d3 <= pixel_y_d2;
        pixel_y_d4 <= pixel_y_d3;  // ?????
        video_active_d1 <= video_active;
        video_active_d2 <= video_active_d1;
        video_active_d3 <= video_active_d2;
        video_active_d4 <= video_active_d3;  // ?????
        work_mode_d1 <= work_mode;
        work_mode_d2 <= work_mode_d1;
        work_mode_d3 <= work_mode_d2;
        work_mode_d4 <= work_mode_d3;  // ?????
        
        // ??????????har_code??????????
        char_code_d1 <= char_code;
        char_row_d1 <= char_row;
        char_col_d1 <= char_col;
        in_char_area_d1 <= in_char_area;
        grid_x_flag_d1 <= grid_x_flag;
        grid_x_flag_d2 <= grid_x_flag_d1;
        grid_x_flag_d3 <= grid_x_flag_d2;
        grid_y_flag_d1 <= grid_y_flag;
        grid_y_flag_d2 <= grid_y_flag_d1;
        grid_y_flag_d3 <= grid_y_flag_d2;
        
        // ???????????Stage 4???
        grid_x_flag_d4 <= grid_x_flag_d3;
        grid_y_flag_d4 <= grid_y_flag_d3;
        work_mode_d4 <= work_mode_d3;
        pixel_x_d4 <= pixel_x_d3;
        pixel_y_d4 <= pixel_y_d3;
        ch1_enable_d4 <= ch1_enable;
        ch2_enable_d4 <= ch2_enable;
        
        // ????????????????????????????????
        ch1_data_q <= ch1_data;
        ch2_data_q <= ch2_data;
        
        // ???????????Stage 3 - ??????????????
        ch1_waveform_calc_d1 <= ch1_waveform_height;
        ch2_waveform_calc_d1 <= ch2_waveform_height;
        ch1_spectrum_calc_d1 <= ch1_spectrum_height;
        ch2_spectrum_calc_d1 <= ch2_spectrum_height;
        
        // ?????????????????????
        spectrum_data_q <= ch1_enable ? ch1_data : ch2_data;
        time_data_q <= ch1_enable ? ch1_data : ch2_data;
    end
end

//=============================================================================
// ???????????Y???????????????????ixel_y????????
//=============================================================================
always @(posedge clk_pixel or negedge rst_n) begin
    if (!rst_n) begin
        y_axis_char_code <= 8'd32;
        y_axis_char_valid <= 1'b0;
        y_axis_char_row <= 5'd0;
        y_axis_char_col <= 12'd0;
    end else begin
        // ?????
        y_axis_char_code <= 8'd32;  // ???
        y_axis_char_valid <= 1'b0;
        y_axis_char_row <= 5'd0;
        y_axis_char_col <= 12'd0;
        
        // ???Y???????????????
        if (pixel_x >= 8 && pixel_x < AXIS_LEFT_MARGIN - TICK_LENGTH - 4) begin
            // 100% (Y: 75-107)
            if (pixel_y >= 75 && pixel_y < 107) begin
                y_axis_char_row <= pixel_y - 12'd75;
                y_axis_char_valid <= 1'b1;
                if (pixel_x >= 8 && pixel_x < 24) begin
                    y_axis_char_code <= 8'd49;  // '1'
                    y_axis_char_col <= pixel_x - 12'd8;
                end
                else if (pixel_x >= 24 && pixel_x < 40) begin
                    y_axis_char_code <= 8'd48;  // '0'
                    y_axis_char_col <= pixel_x - 12'd24;
                end
                else if (pixel_x >= 40 && pixel_x < 56) begin
                    y_axis_char_code <= 8'd48;  // '0'
                    y_axis_char_col <= pixel_x - 12'd40;
                end
                else if (pixel_x >= 56 && pixel_x < 72) begin
                    y_axis_char_code <= 8'd37;  // '%'
                    y_axis_char_col <= pixel_x - 12'd56;
                end
                else begin
                    y_axis_char_valid <= 1'b0;
                end
            end
            // 75% (Y: 262-294)
            else if (pixel_y >= 262 && pixel_y < 294) begin
                y_axis_char_row <= pixel_y - 12'd262;
                y_axis_char_valid <= 1'b1;
                if (pixel_x >= 24 && pixel_x < 40) begin
                    y_axis_char_code <= 8'd55;  // '7'
                    y_axis_char_col <= pixel_x - 12'd24;
                end
                else if (pixel_x >= 40 && pixel_x < 56) begin
                    y_axis_char_code <= 8'd53;  // '5'
                    y_axis_char_col <= pixel_x - 12'd40;
                end
                else if (pixel_x >= 56 && pixel_x < 72) begin
                    y_axis_char_code <= 8'd37;  // '%'
                    y_axis_char_col <= pixel_x - 12'd56;
                end
                else begin
                    y_axis_char_valid <= 1'b0;
                end
            end
            // 50% (Y: 450-482)
            else if (pixel_y >= 450 && pixel_y < 482) begin
                y_axis_char_row <= pixel_y - 12'd450;
                y_axis_char_valid <= 1'b1;
                if (pixel_x >= 24 && pixel_x < 40) begin
                    y_axis_char_code <= 8'd53;  // '5'
                    y_axis_char_col <= pixel_x - 12'd24;
                end
                else if (pixel_x >= 40 && pixel_x < 56) begin
                    y_axis_char_code <= 8'd48;  // '0'
                    y_axis_char_col <= pixel_x - 12'd40;
                end
                else if (pixel_x >= 56 && pixel_x < 72) begin
                    y_axis_char_code <= 8'd37;  // '%'
                    y_axis_char_col <= pixel_x - 12'd56;
                end
                else begin
                    y_axis_char_valid <= 1'b0;
                end
            end
            // 25% (Y: 637-669)
            else if (pixel_y >= 637 && pixel_y < 669) begin
                y_axis_char_row <= pixel_y - 12'd637;
                y_axis_char_valid <= 1'b1;
                if (pixel_x >= 24 && pixel_x < 40) begin
                    y_axis_char_code <= 8'd50;  // '2'
                    y_axis_char_col <= pixel_x - 12'd24;
                end
                else if (pixel_x >= 40 && pixel_x < 56) begin
                    y_axis_char_code <= 8'd53;  // '5'
                    y_axis_char_col <= pixel_x - 12'd40;
                end
                else if (pixel_x >= 56 && pixel_x < 72) begin
                    y_axis_char_code <= 8'd37;  // '%'
                    y_axis_char_col <= pixel_x - 12'd56;
                end
                else begin
                    y_axis_char_valid <= 1'b0;
                end
            end
            // 0% (Y: 793-825)
            else if (pixel_y >= 793 && pixel_y < 825) begin
                y_axis_char_row <= pixel_y - 12'd793;
                y_axis_char_valid <= 1'b1;
                if (pixel_x >= 40 && pixel_x < 56) begin
                    y_axis_char_code <= 8'd48;  // '0'
                    y_axis_char_col <= pixel_x - 12'd40;
                end
                else if (pixel_x >= 56 && pixel_x < 72) begin
                    y_axis_char_code <= 8'd37;  // '%'
                    y_axis_char_col <= pixel_x - 12'd56;
                end
                else begin
                    y_axis_char_valid <= 1'b0;
                end
            end
        end
    end
end

//=============================================================================
// ????????????
//=============================================================================
// ????????????????920??? -> 8192?????
// spectrum_addr???0-8191??????0-1919
// ???????? = (spectrum_addr * 1920) / 8192 ??spectrum_addr / 4.27
// ?????x ??spectrum_addr >> 2??????????
assign time_sample_x = {1'b0, spectrum_addr[12:2]};  // ???4?????-2047???

//=============================================================================
// ??????????????????tage 3????????
//=============================================================================
always @(*) begin
    // CH1?????????
    if (ch1_data_q[15:6] > 10'd350)
        ch1_waveform_height = 12'd700;
    else
        ch1_waveform_height = {1'b0, ch1_data_q[15:6], 1'b0};  // ???2
    
    // CH2?????????
    if (ch2_data_q[15:6] > 10'd350)
        ch2_waveform_height = 12'd700;
    else
        ch2_waveform_height = {1'b0, ch2_data_q[15:6], 1'b0};  // ???2
    
    // ????????????????????
    waveform_height = ch1_enable ? ch1_waveform_height : ch2_waveform_height;
end

//=============================================================================
// ???????????Stage 4 - ??????????????????????
//=============================================================================
always @(posedge clk_pixel or negedge rst_n) begin
    if (!rst_n) begin
        ch1_hit <= 1'b0;
        ch2_hit <= 1'b0;
    end else begin
        // CH1??????????????Stage 3?????????
        if (ch1_waveform_calc_d1 >= 12'd350) begin
            // ???????????
            ch1_hit <= (pixel_y_d3 >= (WAVEFORM_CENTER_Y - (ch1_waveform_calc_d1 - 12'd350) - 12'd2)) &&
                       (pixel_y_d3 <= (WAVEFORM_CENTER_Y - (ch1_waveform_calc_d1 - 12'd350) + 12'd2));
        end else begin
            // ???????????
            ch1_hit <= (pixel_y_d3 >= (WAVEFORM_CENTER_Y + (12'd350 - ch1_waveform_calc_d1) - 12'd2)) &&
                       (pixel_y_d3 <= (WAVEFORM_CENTER_Y + (12'd350 - ch1_waveform_calc_d1) + 12'd2));
        end
        
        // CH2??????????
        if (ch2_waveform_calc_d1 >= 12'd350) begin
            ch2_hit <= (pixel_y_d3 >= (WAVEFORM_CENTER_Y - (ch2_waveform_calc_d1 - 12'd350) - 12'd2)) &&
                       (pixel_y_d3 <= (WAVEFORM_CENTER_Y - (ch2_waveform_calc_d1 - 12'd350) + 12'd2));
        end else begin
            ch2_hit <= (pixel_y_d3 >= (WAVEFORM_CENTER_Y + (12'd350 - ch2_waveform_calc_d1) - 12'd2)) &&
                       (pixel_y_d3 <= (WAVEFORM_CENTER_Y + (12'd350 - ch2_waveform_calc_d1) + 12'd2));
        end
    end
end

//=============================================================================
// ???ROM?????- ??????ASCII??????ROM
// ???????????????????har_code???
//=============================================================================
ascii_rom_16x32_full u_char_rom (
    .clk        (clk_pixel),
    .char_code  (char_code_d1),      // ????????1???char_code
    .char_row   (char_row_d1[4:0]),  // ????????1???char_row
    .char_data  (char_pixel_row)     // 16?????????
);

//=============================================================================
// ?????????
//=============================================================================
function [3:0] get_digit;
    input [15:0] number;
    input [2:0]  position;  // 0=???, 1=???, 2=???, 3=???, 4=???
    reg [15:0] temp;
    begin
        temp = number;
        case (position)
            3'd0: get_digit = temp % 10;
            3'd1: get_digit = (temp / 10) % 10;
            3'd2: get_digit = (temp / 100) % 10;
            3'd3: get_digit = (temp / 1000) % 10;
            3'd4: get_digit = (temp / 10000) % 10;
            default: get_digit = 4'd0;
        endcase
    end
endfunction

//=============================================================================
// BCD?????SCII????????
//=============================================================================
function [7:0] digit_to_ascii;
    input [3:0] digit;
    begin
        digit_to_ascii = 8'd48 + {4'd0, digit};  // ASCII '0' = 48
    end
endfunction

//=============================================================================
// ?????????????????????????OM????? ???ASCII??????
// ???????????????????????????????????1??????????
//=============================================================================
always @(posedge clk_pixel or negedge rst_n) begin
    if (!rst_n) begin
        char_code <= 8'd32;
        char_row <= 5'd0;
        char_col <= 12'd0;
        in_char_area <= 1'b0;
    end else begin
        char_code <= 8'd32;  // ?????? (ASCII 32)
        char_row <= 5'd0;
        char_col <= 12'd0;
        in_char_area <= 1'b0;
    
    // ========== ??Y??????????????????????????????????==========
    if (y_axis_char_valid) begin
        char_code <= y_axis_char_code;
        char_row <= y_axis_char_row;
        char_col <= y_axis_char_col;
        in_char_area <= 1'b1;
    end
    
    // ========== X?????????????????- ?????==========
    // ???????5MHz??FT 8192???????????= 35MHz/8192 = 4.272kHz/bin
    // ?????????? ??Fs/2 = 17.5MHz???4096??in??
    // ????????, 3.5, 7.0, 10.5, 14.0, 17.5 MHz
    // ????????, 47, 93, 140, 186, 234 us (8192??@ 35MHz = 234us)
    else if (pixel_y_d1 >= SPECTRUM_Y_END && pixel_y_d1 < SPECTRUM_Y_END + 32) begin
        char_row <= pixel_y_d1 - SPECTRUM_Y_END;
        
        // X = 80: "0"
        if (pixel_x_d1 >= 80 && pixel_x_d1 < 96) begin
            char_code <= 8'd48;  // '0'
            char_col <= pixel_x_d1 - 12'd80;
            in_char_area <= 1'b1;
        end
        // X = 444: "3.5" (???MHz) ??"47" (???us)
        else if (pixel_x_d1 >= 428 && pixel_x_d1 < 444 && work_mode_d1[0]) begin
            char_code <= 8'd51;  // '3'
            char_col <= pixel_x_d1 - 12'd428;
            in_char_area <= 1'b1;
        end
        else if (pixel_x_d1 >= 444 && pixel_x_d1 < 460) begin
            char_code <= work_mode_d1[0] ? 8'd46 : 8'd52;  // '.' or '4'
            char_col <= pixel_x_d1 - 12'd444;
            in_char_area <= 1'b1;
        end
        else if (pixel_x_d1 >= 460 && pixel_x_d1 < 476) begin
            char_code <= work_mode_d1[0] ? 8'd53 : 8'd55;  // '5' or '7'
            char_col <= pixel_x_d1 - 12'd460;
            in_char_area <= 1'b1;
        end
        // X = 808: "7.0" (???) ??"93" (???)
        else if (pixel_x_d1 >= 808 && pixel_x_d1 < 824) begin
            char_code <= work_mode_d1[0] ? 8'd55 : 8'd57;  // '7' or '9'
            char_col <= pixel_x_d1 - 12'd808;
            in_char_area <= 1'b1;
        end
        else if (pixel_x_d1 >= 824 && pixel_x_d1 < 840) begin
            char_code <= work_mode_d1[0] ? 8'd46 : 8'd51;  // '.' or '3'
            char_col <= pixel_x_d1 - 12'd824;
            in_char_area <= 1'b1;
        end
        else if (pixel_x_d1 >= 840 && pixel_x_d1 < 856 && work_mode_d1[0]) begin
            char_code <= 8'd48;  // '0' (?????????)
            char_col <= pixel_x_d1 - 12'd840;
            in_char_area <= 1'b1;
        end
        // X = 1172: "10.5" (???) ??"140" (???)
        else if (pixel_x_d1 >= 1156 && pixel_x_d1 < 1172) begin
            char_code <= 8'd49;  // '1'
            char_col <= pixel_x_d1 - 12'd1156;
            in_char_area <= 1'b1;
        end
        else if (pixel_x_d1 >= 1172 && pixel_x_d1 < 1188) begin
            char_code <= work_mode_d1[0] ? 8'd48 : 8'd52;  // '0' or '4'
            char_col <= pixel_x_d1 - 12'd1172;
            in_char_area <= 1'b1;
        end
        else if (pixel_x_d1 >= 1188 && pixel_x_d1 < 1204) begin
            char_code <= work_mode_d1[0] ? 8'd46 : 8'd48;  // '.' or '0'
            char_col <= pixel_x_d1 - 12'd1188;
            in_char_area <= 1'b1;
        end
        else if (pixel_x_d1 >= 1204 && pixel_x_d1 < 1220 && work_mode_d1[0]) begin
            char_code <= 8'd53;  // '5' (?????????)
            char_col <= pixel_x_d1 - 12'd1204;
            in_char_area <= 1'b1;
        end
        // X = 1536: "14.0" (???) ??"186" (???)
        else if (pixel_x_d1 >= 1520 && pixel_x_d1 < 1536) begin
            char_code <= 8'd49;  // '1'
            char_col <= pixel_x_d1 - 12'd1520;
            in_char_area <= 1'b1;
        end
        else if (pixel_x_d1 >= 1536 && pixel_x_d1 < 1552) begin
            char_code <= work_mode_d1[0] ? 8'd52 : 8'd56;  // '4' or '8'
            char_col <= pixel_x_d1 - 12'd1536;
            in_char_area <= 1'b1;
        end
        else if (pixel_x_d1 >= 1552 && pixel_x_d1 < 1568) begin
            char_code <= work_mode_d1[0] ? 8'd46 : 8'd54;  // '.' or '6'
            char_col <= pixel_x_d1 - 12'd1552;
            in_char_area <= 1'b1;
        end
        else if (pixel_x_d1 >= 1568 && pixel_x_d1 < 1584 && work_mode_d1[0]) begin
            char_code <= 8'd48;  // '0' (?????????)
            char_col <= pixel_x_d1 - 12'd1568;
            in_char_area <= 1'b1;
        end
        // X = 1840: "17.5" (???) ??"234" (???)
        else if (pixel_x_d1 >= 1824 && pixel_x_d1 < 1840) begin
            char_code <= work_mode_d1[0] ? 8'd49 : 8'd50;  // '1' or '2'
            char_col <= pixel_x_d1 - 12'd1824;
            in_char_area <= 1'b1;
        end
        else if (pixel_x_d1 >= 1840 && pixel_x_d1 < 1856) begin
            char_code <= work_mode_d1[0] ? 8'd55 : 8'd51;  // '7' or '3'
            char_col <= pixel_x_d1 - 12'd1840;
            in_char_area <= 1'b1;
        end
        else if (pixel_x_d1 >= 1856 && pixel_x_d1 < 1872) begin
            char_code <= work_mode_d1[0] ? 8'd46 : 8'd52;  // '.' or '4'
            char_col <= pixel_x_d1 - 12'd1856;
            in_char_area <= 1'b1;
        end
        else if (pixel_x_d1 >= 1872 && pixel_x_d1 < 1888 && work_mode_d1[0]) begin
            char_code <= 8'd53;  // '5' (?????????)
            char_col <= pixel_x_d1 - 12'd1872;
            in_char_area <= 1'b1;
        end
    end
    
    // ========== AI????????? (???????????????) ==========
    // "CH1: Sine 95%    CH2: Squr 88%" - Y: 830-862 (???32px)
    // ????????AI????????????valid?????
    if (pixel_y_d1 >= 830 && pixel_y_d1 < 862) begin
        char_row <= pixel_y_d1 - 12'd830;
        
        // ========== CH1??? (???) ==========
        // "CH1:"
        if (pixel_x_d1 >= 40 && pixel_x_d1 < 56) begin
            char_code <= 8'd67;  // 'C'
            char_col <= pixel_x_d1 - 12'd40;
            in_char_area <= 1'b1;  // ????????
        end
        else if (pixel_x_d1 >= 56 && pixel_x_d1 < 72) begin
            char_code <= 8'd72;  // 'H'
            char_col <= pixel_x_d1 - 12'd56;
            in_char_area <= 1'b1;
        end
        else if (pixel_x_d1 >= 72 && pixel_x_d1 < 88) begin
            char_code <= 8'd49;  // '1'
            char_col <= pixel_x_d1 - 12'd72;
            in_char_area <= 1'b1;
        end
        else if (pixel_x_d1 >= 88 && pixel_x_d1 < 104) begin
            char_code <= 8'd58;  // ':'
            char_col <= pixel_x_d1 - 12'd88;
            in_char_area <= 1'b1;
        end
        // CH1????????? (4?????
        else if (pixel_x_d1 >= 104 && pixel_x_d1 < 120) begin
            case (ch1_waveform_type)
                3'd1: char_code <= 8'd83;  // 'S' (Sine)
                3'd2: char_code <= 8'd83;  // 'S' (Square)
                3'd3: char_code <= 8'd84;  // 'T' (Triangle)
                3'd4: char_code <= 8'd83;  // 'S' (Sawtooth)
                3'd5: char_code <= 8'd78;  // 'N' (Noise)
                default: char_code <= 8'd85; // 'U' (Unknown)
            endcase
            char_col <= pixel_x_d1 - 12'd104;
            in_char_area <= 1'b1;
        end
        else if (pixel_x_d1 >= 120 && pixel_x_d1 < 136) begin
            case (ch1_waveform_type)
                3'd1: char_code <= 8'd105; // 'i'
                3'd2: char_code <= 8'd113; // 'q'
                3'd3: char_code <= 8'd114; // 'r'
                3'd4: char_code <= 8'd97;  // 'a'
                3'd5: char_code <= 8'd111; // 'o'
                default: char_code <= 8'd110; // 'n'
            endcase
            char_col <= pixel_x_d1 - 12'd120;
            in_char_area <= 1'b1;
        end
        else if (pixel_x_d1 >= 136 && pixel_x_d1 < 152) begin
            case (ch1_waveform_type)
                3'd1: char_code <= 8'd110; // 'n'
                3'd2: char_code <= 8'd117; // 'u'
                3'd3: char_code <= 8'd105; // 'i'
                3'd4: char_code <= 8'd119; // 'w'
                3'd5: char_code <= 8'd105; // 'i'
                default: char_code <= 8'd107; // 'k'
            endcase
            char_col <= pixel_x_d1 - 12'd136;
            in_char_area <= 1'b1;
        end
        else if (pixel_x_d1 >= 152 && pixel_x_d1 < 168) begin
            case (ch1_waveform_type)
                3'd1: char_code <= 8'd101; // 'e' (Sine)
                3'd2: char_code <= 8'd114; // 'r' (Squr)
                3'd3: char_code <= 8'd97;  // 'a' (Tria)
                3'd4: char_code <= 8'd32;  // ' ' (Saw)
                3'd5: char_code <= 8'd115; // 's' (Nois)
                default: char_code <= 8'd110; // 'n' (Unkn)
            endcase
            char_col <= pixel_x_d1 - 12'd152;
            in_char_area <= 1'b1;
        end
        // CH1?????(?????? + '%')
        else if (pixel_x_d1 >= 168 && pixel_x_d1 < 184) begin
            char_code <= digit_to_ascii((ch1_confidence / 10) % 10); // ???
            char_col <= pixel_x_d1 - 12'd168;
            in_char_area <= 1'b1;
        end
        else if (pixel_x_d1 >= 184 && pixel_x_d1 < 200) begin
            char_code <= digit_to_ascii(ch1_confidence % 10); // ???
            char_col <= pixel_x_d1 - 12'd184;
            in_char_area <= 1'b1;
        end
        else if (pixel_x_d1 >= 200 && pixel_x_d1 < 216) begin
            char_code <= 8'd37; // '%'
            char_col <= pixel_x_d1 - 12'd200;
            in_char_area <= 1'b1;
        end
        
        // ========== ?????? ==========
        // X: 216-280 (??4??????)
        
        // ========== CH2??? (??????) ==========
        // "CH2:"
        else if (pixel_x_d1 >= 280 && pixel_x_d1 < 296) begin
            char_code <= 8'd67;  // 'C'
            char_col <= pixel_x_d1 - 12'd280;
            in_char_area <= 1'b1;
        end
        else if (pixel_x_d1 >= 296 && pixel_x_d1 < 312) begin
            char_code <= 8'd72;  // 'H'
            char_col <= pixel_x_d1 - 12'd296;
            in_char_area <= 1'b1;
        end
        else if (pixel_x_d1 >= 312 && pixel_x_d1 < 328) begin
            char_code <= 8'd50;  // '2'
            char_col <= pixel_x_d1 - 12'd312;
            in_char_area <= 1'b1;
        end
        else if (pixel_x_d1 >= 328 && pixel_x_d1 < 344) begin
            char_code <= 8'd58;  // ':'
            char_col <= pixel_x_d1 - 12'd328;
            in_char_area <= 1'b1;
        end
        // CH2????????? (4?????
        else if (pixel_x_d1 >= 344 && pixel_x_d1 < 360) begin
            case (ch2_waveform_type)
                3'd1: char_code <= 8'd83;  // 'S' (Sine)
                3'd2: char_code <= 8'd83;  // 'S' (Square)
                3'd3: char_code <= 8'd84;  // 'T' (Triangle)
                3'd4: char_code <= 8'd83;  // 'S' (Sawtooth)
                3'd5: char_code <= 8'd78;  // 'N' (Noise)
                default: char_code <= 8'd85; // 'U' (Unknown)
            endcase
            char_col <= pixel_x_d1 - 12'd344;
            in_char_area <= 1'b1;
        end
        else if (pixel_x_d1 >= 360 && pixel_x_d1 < 376) begin
            case (ch2_waveform_type)
                3'd1: char_code <= 8'd105; // 'i'
                3'd2: char_code <= 8'd113; // 'q'
                3'd3: char_code <= 8'd114; // 'r'
                3'd4: char_code <= 8'd97;  // 'a'
                3'd5: char_code <= 8'd111; // 'o'
                default: char_code <= 8'd110; // 'n'
            endcase
            char_col <= pixel_x_d1 - 12'd360;
            in_char_area <= 1'b1;
        end
        else if (pixel_x_d1 >= 376 && pixel_x_d1 < 392) begin
            case (ch2_waveform_type)
                3'd1: char_code <= 8'd110; // 'n'
                3'd2: char_code <= 8'd117; // 'u'
                3'd3: char_code <= 8'd105; // 'i'
                3'd4: char_code <= 8'd119; // 'w'
                3'd5: char_code <= 8'd105; // 'i'
                default: char_code <= 8'd107; // 'k'
            endcase
            char_col <= pixel_x_d1 - 12'd376;
            in_char_area <= 1'b1;
        end
        else if (pixel_x_d1 >= 392 && pixel_x_d1 < 408) begin
            case (ch2_waveform_type)
                3'd1: char_code <= 8'd101; // 'e' (Sine)
                3'd2: char_code <= 8'd114; // 'r' (Squr)
                3'd3: char_code <= 8'd97;  // 'a' (Tria)
                3'd4: char_code <= 8'd32;  // ' ' (Saw)
                3'd5: char_code <= 8'd115; // 's' (Nois)
                default: char_code <= 8'd110; // 'n' (Unkn)
            endcase
            char_col <= pixel_x_d1 - 12'd392;
            in_char_area <= 1'b1;
        end
        // CH2?????(?????? + '%')
        else if (pixel_x_d1 >= 408 && pixel_x_d1 < 424) begin
            char_code <= digit_to_ascii((ch2_confidence / 10) % 10); // ???
            char_col <= pixel_x_d1 - 12'd408;
            in_char_area <= 1'b1;
        end
        else if (pixel_x_d1 >= 424 && pixel_x_d1 < 440) begin
            char_code <= digit_to_ascii(ch2_confidence % 10); // ???
            char_col <= pixel_x_d1 - 12'd424;
            in_char_area <= 1'b1;
        end
        else if (pixel_x_d1 >= 440 && pixel_x_d1 < 456) begin
            char_code <= 8'd37; // '%'
            char_col <= pixel_x_d1 - 12'd440;
            in_char_area <= 1'b1;
        end
    end
    
    // ?????????????????
    else if (pixel_y_d1 >= PARAM_Y_START && pixel_y_d1 < PARAM_Y_END) begin
        
        // ========== ???? ??? "CH1 Freq: 05000Hz    CH2 Freq: 05000Hz" ==========
        if (pixel_y_d1 >= PARAM_Y_START && pixel_y_d1 < PARAM_Y_START + 32) begin
            char_row <= pixel_y_d1 - PARAM_Y_START;
            
            // ----- CH1?????? (???) -----
            // "CH1 "
            if (pixel_x_d1 >= 40 && pixel_x_d1 < 56) begin
                char_code <= 8'd67;  // 'C'
                char_col <= pixel_x_d1 - 12'd40;
                in_char_area <= ch1_enable;
            end
            else if (pixel_x_d1 >= 56 && pixel_x_d1 < 72) begin
                char_code <= 8'd72;  // 'H'
                char_col <= pixel_x_d1 - 12'd56;
                in_char_area <= ch1_enable;
            end
            else if (pixel_x_d1 >= 72 && pixel_x_d1 < 88) begin
                char_code <= 8'd49;  // '1'
                char_col <= pixel_x_d1 - 12'd72;
                in_char_area <= ch1_enable;
            end
            // "Freq: "
            else if (pixel_x_d1 >= 104 && pixel_x_d1 < 120) begin
                char_code <= 8'd70;  // 'F'
                char_col <= pixel_x_d1 - 12'd104;
                in_char_area <= ch1_enable;
            end
            else if (pixel_x_d1 >= 120 && pixel_x_d1 < 136) begin
                char_code <= 8'd114; // 'r'
                char_col <= pixel_x_d1 - 12'd120;
                in_char_area <= ch1_enable;
            end
            else if (pixel_x_d1 >= 136 && pixel_x_d1 < 152) begin
                char_code <= 8'd101; // 'e'
                char_col <= pixel_x_d1 - 12'd136;
                in_char_area <= ch1_enable;
            end
            else if (pixel_x_d1 >= 152 && pixel_x_d1 < 168) begin
                char_code <= 8'd113; // 'q'
                char_col <= pixel_x_d1 - 12'd152;
                in_char_area <= ch1_enable;
            end
            else if (pixel_x_d1 >= 168 && pixel_x_d1 < 184) begin
                char_code <= 8'd58;  // ':'
                char_col <= pixel_x_d1 - 12'd168;
                in_char_area <= ch1_enable;
            end
            // CH1???????(5???)
            else if (pixel_x_d1 >= 192 && pixel_x_d1 < 208) begin
                char_code <= digit_to_ascii(ch1_freq_d4);
                char_col <= pixel_x_d1 - 12'd192;
                in_char_area <= ch1_enable;
            end
            else if (pixel_x_d1 >= 208 && pixel_x_d1 < 224) begin
                char_code <= digit_to_ascii(ch1_freq_d3);
                char_col <= pixel_x_d1 - 12'd208;
                in_char_area <= ch1_enable;
            end
            else if (pixel_x_d1 >= 224 && pixel_x_d1 < 240) begin
                char_code <= digit_to_ascii(ch1_freq_d2);
                char_col <= pixel_x_d1 - 12'd224;
                in_char_area <= ch1_enable;
            end
            else if (pixel_x_d1 >= 240 && pixel_x_d1 < 256) begin
                char_code <= digit_to_ascii(ch1_freq_d1);
                char_col <= pixel_x_d1 - 12'd240;
                in_char_area <= ch1_enable;
            end
            else if (pixel_x_d1 >= 256 && pixel_x_d1 < 272) begin
                char_code <= digit_to_ascii(ch1_freq_d0);
                char_col <= pixel_x_d1 - 12'd256;
                in_char_area <= ch1_enable;
            end
            // "Hz"
            else if (pixel_x_d1 >= 272 && pixel_x_d1 < 288) begin
                char_code <= 8'd72;  // 'H'
                char_col <= pixel_x_d1 - 12'd272;
                in_char_area <= ch1_enable;
            end
            else if (pixel_x_d1 >= 288 && pixel_x_d1 < 304) begin
                char_code <= 8'd122; // 'z'
                char_col <= pixel_x_d1 - 12'd288;
                in_char_area <= ch1_enable;
            end
            
            // ----- CH2?????? (?????: 1000???? -----
            // "CH2 "
            else if (pixel_x_d1 >= 1000 && pixel_x_d1 < 1016) begin
                char_code <= 8'd67;  // 'C'
                char_col <= pixel_x_d1 - 12'd1000;
                in_char_area <= ch2_enable;
            end
            else if (pixel_x_d1 >= 1016 && pixel_x_d1 < 1032) begin
                char_code <= 8'd72;  // 'H'
                char_col <= pixel_x_d1 - 12'd1016;
                in_char_area <= ch2_enable;
            end
            else if (pixel_x_d1 >= 1032 && pixel_x_d1 < 1048) begin
                char_code <= 8'd50;  // '2'
                char_col <= pixel_x_d1 - 12'd1032;
                in_char_area <= ch2_enable;
            end
            // "Freq: "
            else if (pixel_x_d1 >= 1064 && pixel_x_d1 < 1080) begin
                char_code <= 8'd70;  // 'F'
                char_col <= pixel_x_d1 - 12'd1064;
                in_char_area <= ch2_enable;
            end
            else if (pixel_x_d1 >= 1080 && pixel_x_d1 < 1096) begin
                char_code <= 8'd114; // 'r'
                char_col <= pixel_x_d1 - 12'd1080;
                in_char_area <= ch2_enable;
            end
            else if (pixel_x_d1 >= 1096 && pixel_x_d1 < 1112) begin
                char_code <= 8'd101; // 'e'
                char_col <= pixel_x_d1 - 12'd1096;
                in_char_area <= ch2_enable;
            end
            else if (pixel_x_d1 >= 1112 && pixel_x_d1 < 1128) begin
                char_code <= 8'd113; // 'q'
                char_col <= pixel_x_d1 - 12'd1112;
                in_char_area <= ch2_enable;
            end
            else if (pixel_x_d1 >= 1128 && pixel_x_d1 < 1144) begin
                char_code <= 8'd58;  // ':'
                char_col <= pixel_x_d1 - 12'd1128;
                in_char_area <= ch2_enable;
            end
            // CH2???????(5???)
            else if (pixel_x_d1 >= 1152 && pixel_x_d1 < 1168) begin
                char_code <= digit_to_ascii(ch2_freq_d4);
                char_col <= pixel_x_d1 - 12'd1152;
                in_char_area <= ch2_enable;
            end
            else if (pixel_x_d1 >= 1168 && pixel_x_d1 < 1184) begin
                char_code <= digit_to_ascii(ch2_freq_d3);
                char_col <= pixel_x_d1 - 12'd1168;
                in_char_area <= ch2_enable;
            end
            else if (pixel_x_d1 >= 1184 && pixel_x_d1 < 1200) begin
                char_code <= digit_to_ascii(ch2_freq_d2);
                char_col <= pixel_x_d1 - 12'd1184;
                in_char_area <= ch2_enable;
            end
            else if (pixel_x_d1 >= 1200 && pixel_x_d1 < 1216) begin
                char_code <= digit_to_ascii(ch2_freq_d1);
                char_col <= pixel_x_d1 - 12'd1200;
                in_char_area <= ch2_enable;
            end
            else if (pixel_x_d1 >= 1216 && pixel_x_d1 < 1232) begin
                char_code <= digit_to_ascii(ch2_freq_d0);
                char_col <= pixel_x_d1 - 12'd1216;
                in_char_area <= ch2_enable;
            end
            // "Hz"
            else if (pixel_x_d1 >= 1232 && pixel_x_d1 < 1248) begin
                char_code <= 8'd72;  // 'H'
                char_col <= pixel_x_d1 - 12'd1232;
                in_char_area <= ch2_enable;
            end
            else if (pixel_x_d1 >= 1248 && pixel_x_d1 < 1264) begin
                char_code <= 8'd122; // 'z'
                char_col <= pixel_x_d1 - 12'd1248;
                in_char_area <= ch2_enable;
            end
        end
        
        // ========== ???? ??? "CH1 Ampl: 0051    CH2 Ampl: 0051" ==========
        else if (pixel_y_d1 >= PARAM_Y_START + 35 && pixel_y_d1 < PARAM_Y_START + 67) begin
            char_row <= pixel_y_d1 - PARAM_Y_START - 12'd35;
            
            // ----- CH1?????? (???) -----
            // "CH1 "
            if (pixel_x_d1 >= 40 && pixel_x_d1 < 56) begin
                char_code <= 8'd67;  // 'C'
                char_col <= pixel_x_d1 - 12'd40;
                in_char_area <= ch1_enable;
            end
            else if (pixel_x_d1 >= 56 && pixel_x_d1 < 72) begin
                char_code <= 8'd72;  // 'H'
                char_col <= pixel_x_d1 - 12'd56;
                in_char_area <= ch1_enable;
            end
            else if (pixel_x_d1 >= 72 && pixel_x_d1 < 88) begin
                char_code <= 8'd49;  // '1'
                char_col <= pixel_x_d1 - 12'd72;
                in_char_area <= ch1_enable;
            end
            // "Ampl: "
            else if (pixel_x_d1 >= 104 && pixel_x_d1 < 120) begin
                char_code <= 8'd65;  // 'A'
                char_col <= pixel_x_d1 - 12'd104;
                in_char_area <= ch1_enable;
            end
            else if (pixel_x_d1 >= 120 && pixel_x_d1 < 136) begin
                char_code <= 8'd109; // 'm'
                char_col <= pixel_x_d1 - 12'd120;
                in_char_area <= ch1_enable;
            end
            else if (pixel_x_d1 >= 136 && pixel_x_d1 < 152) begin
                char_code <= 8'd112; // 'p'
                char_col <= pixel_x_d1 - 12'd136;
                in_char_area <= ch1_enable;
            end
            else if (pixel_x_d1 >= 152 && pixel_x_d1 < 168) begin
                char_code <= 8'd108; // 'l'
                char_col <= pixel_x_d1 - 12'd152;
                in_char_area <= ch1_enable;
            end
            else if (pixel_x_d1 >= 168 && pixel_x_d1 < 184) begin
                char_code <= 8'd58;  // ':'
                char_col <= pixel_x_d1 - 12'd168;
                in_char_area <= ch1_enable;
            end
            // CH1???????(4???)
            else if (pixel_x_d1 >= 192 && pixel_x_d1 < 208) begin
                char_code <= digit_to_ascii(ch1_amp_d3);
                char_col <= pixel_x_d1 - 12'd192;
                in_char_area <= ch1_enable;
            end
            else if (pixel_x_d1 >= 208 && pixel_x_d1 < 224) begin
                char_code <= digit_to_ascii(ch1_amp_d2);
                char_col <= pixel_x_d1 - 12'd208;
                in_char_area <= ch1_enable;
            end
            else if (pixel_x_d1 >= 224 && pixel_x_d1 < 240) begin
                char_code <= digit_to_ascii(ch1_amp_d1);
                char_col <= pixel_x_d1 - 12'd224;
                in_char_area <= ch1_enable;
            end
            else if (pixel_x_d1 >= 240 && pixel_x_d1 < 256) begin
                char_code <= digit_to_ascii(ch1_amp_d0);
                char_col <= pixel_x_d1 - 12'd240;
                in_char_area <= ch1_enable;
            end
            
            // ----- CH2?????? (???) -----
            // "CH2 "
            else if (pixel_x_d1 >= 1000 && pixel_x_d1 < 1016) begin
                char_code <= 8'd67;  // 'C'
                char_col <= pixel_x_d1 - 12'd1000;
                in_char_area <= ch2_enable;
            end
            else if (pixel_x_d1 >= 1016 && pixel_x_d1 < 1032) begin
                char_code <= 8'd72;  // 'H'
                char_col <= pixel_x_d1 - 12'd1016;
                in_char_area <= ch2_enable;
            end
            else if (pixel_x_d1 >= 1032 && pixel_x_d1 < 1048) begin
                char_code <= 8'd50;  // '2'
                char_col <= pixel_x_d1 - 12'd1032;
                in_char_area <= ch2_enable;
            end
            // "Ampl: "
            else if (pixel_x_d1 >= 1064 && pixel_x_d1 < 1080) begin
                char_code <= 8'd65;  // 'A'
                char_col <= pixel_x_d1 - 12'd1064;
                in_char_area <= ch2_enable;
            end
            else if (pixel_x_d1 >= 1080 && pixel_x_d1 < 1096) begin
                char_code <= 8'd109; // 'm'
                char_col <= pixel_x_d1 - 12'd1080;
                in_char_area <= ch2_enable;
            end
            else if (pixel_x_d1 >= 1096 && pixel_x_d1 < 1112) begin
                char_code <= 8'd112; // 'p'
                char_col <= pixel_x_d1 - 12'd1096;
                in_char_area <= ch2_enable;
            end
            else if (pixel_x_d1 >= 1112 && pixel_x_d1 < 1128) begin
                char_code <= 8'd108; // 'l'
                char_col <= pixel_x_d1 - 12'd1112;
                in_char_area <= ch2_enable;
            end
            else if (pixel_x_d1 >= 1128 && pixel_x_d1 < 1144) begin
                char_code <= 8'd58;  // ':'
                char_col <= pixel_x_d1 - 12'd1128;
                in_char_area <= ch2_enable;
            end
            // CH2???????(4???)
            else if (pixel_x_d1 >= 1152 && pixel_x_d1 < 1168) begin
                char_code <= digit_to_ascii(ch2_amp_d3);
                char_col <= pixel_x_d1 - 12'd1152;
                in_char_area <= ch2_enable;
            end
            else if (pixel_x_d1 >= 1168 && pixel_x_d1 < 1184) begin
                char_code <= digit_to_ascii(ch2_amp_d2);
                char_col <= pixel_x_d1 - 12'd1168;
                in_char_area <= ch2_enable;
            end
            else if (pixel_x_d1 >= 1184 && pixel_x_d1 < 1200) begin
                char_code <= digit_to_ascii(ch2_amp_d1);
                char_col <= pixel_x_d1 - 12'd1184;
                in_char_area <= ch2_enable;
            end
            else if (pixel_x_d1 >= 1200 && pixel_x_d1 < 1216) begin
                char_code <= digit_to_ascii(ch2_amp_d0);
                char_col <= pixel_x_d1 - 12'd1200;
                in_char_area <= ch2_enable;
            end
        end
        
        // ========== ???? ?????"CH1 Duty: 50.0%    CH2 Duty: 50.0%" ==========
        else if (pixel_y_d1 >= PARAM_Y_START + 70 && pixel_y_d1 < PARAM_Y_START + 102) begin
            char_row <= pixel_y_d1 - PARAM_Y_START - 12'd70;
            
            // ----- CH1?????(???) -----
            // "CH1 "
            if (pixel_x_d1 >= 40 && pixel_x_d1 < 56) begin
                char_code <= 8'd67;  // 'C'
                char_col <= pixel_x_d1 - 12'd40;
                in_char_area <= ch1_enable;
            end
            else if (pixel_x_d1 >= 56 && pixel_x_d1 < 72) begin
                char_code <= 8'd72;  // 'H'
                char_col <= pixel_x_d1 - 12'd56;
                in_char_area <= ch1_enable;
            end
            else if (pixel_x_d1 >= 72 && pixel_x_d1 < 88) begin
                char_code <= 8'd49;  // '1'
                char_col <= pixel_x_d1 - 12'd72;
                in_char_area <= ch1_enable;
            end
            // "Duty: "
            else if (pixel_x_d1 >= 104 && pixel_x_d1 < 120) begin
                char_code <= 8'd68;  // 'D'
                char_col <= pixel_x_d1 - 12'd104;
                in_char_area <= ch1_enable;
            end
            else if (pixel_x_d1 >= 120 && pixel_x_d1 < 136) begin
                char_code <= 8'd117; // 'u'
                char_col <= pixel_x_d1 - 12'd120;
                in_char_area <= ch1_enable;
            end
            else if (pixel_x_d1 >= 136 && pixel_x_d1 < 152) begin
                char_code <= 8'd116; // 't'
                char_col <= pixel_x_d1 - 12'd136;
                in_char_area <= ch1_enable;
            end
            else if (pixel_x_d1 >= 152 && pixel_x_d1 < 168) begin
                char_code <= 8'd121; // 'y'
                char_col <= pixel_x_d1 - 12'd152;
                in_char_area <= ch1_enable;
            end
            else if (pixel_x_d1 >= 168 && pixel_x_d1 < 184) begin
                char_code <= 8'd58;  // ':'
                char_col <= pixel_x_d1 - 12'd168;
                in_char_area <= ch1_enable;
            end
            // CH1????????(???: 50.0%)
            else if (pixel_x_d1 >= 192 && pixel_x_d1 < 208) begin
                char_code <= digit_to_ascii(ch1_duty_d2);
                char_col <= pixel_x_d1 - 12'd192;
                in_char_area <= ch1_enable;
            end
            else if (pixel_x_d1 >= 208 && pixel_x_d1 < 224) begin
                char_code <= digit_to_ascii(ch1_duty_d1);
                char_col <= pixel_x_d1 - 12'd208;
                in_char_area <= ch1_enable;
            end
            else if (pixel_x_d1 >= 224 && pixel_x_d1 < 240) begin
                char_code <= 8'd46;  // '.'
                char_col <= pixel_x_d1 - 12'd224;
                in_char_area <= ch1_enable;
            end
            else if (pixel_x_d1 >= 240 && pixel_x_d1 < 256) begin
                char_code <= digit_to_ascii(ch1_duty_d0);
                char_col <= pixel_x_d1 - 12'd240;
                in_char_area <= ch1_enable;
            end
            else if (pixel_x_d1 >= 256 && pixel_x_d1 < 272) begin
                char_code <= 8'd37;  // '%'
                char_col <= pixel_x_d1 - 12'd256;
                in_char_area <= ch1_enable;
            end
            
            // ----- CH2?????(???) -----
            // "CH2 "
            else if (pixel_x_d1 >= 1000 && pixel_x_d1 < 1016) begin
                char_code <= 8'd67;  // 'C'
                char_col <= pixel_x_d1 - 12'd1000;
                in_char_area <= ch2_enable;
            end
            else if (pixel_x_d1 >= 1016 && pixel_x_d1 < 1032) begin
                char_code <= 8'd72;  // 'H'
                char_col <= pixel_x_d1 - 12'd1016;
                in_char_area <= ch2_enable;
            end
            else if (pixel_x_d1 >= 1032 && pixel_x_d1 < 1048) begin
                char_code <= 8'd50;  // '2'
                char_col <= pixel_x_d1 - 12'd1032;
                in_char_area <= ch2_enable;
            end
            // "Duty: "
            else if (pixel_x_d1 >= 1064 && pixel_x_d1 < 1080) begin
                char_code <= 8'd68;  // 'D'
                char_col <= pixel_x_d1 - 12'd1064;
                in_char_area <= ch2_enable;
            end
            else if (pixel_x_d1 >= 1080 && pixel_x_d1 < 1096) begin
                char_code <= 8'd117; // 'u'
                char_col <= pixel_x_d1 - 12'd1080;
                in_char_area <= ch2_enable;
            end
            else if (pixel_x_d1 >= 1096 && pixel_x_d1 < 1112) begin
                char_code <= 8'd116; // 't'
                char_col <= pixel_x_d1 - 12'd1096;
                in_char_area <= ch2_enable;
            end
            else if (pixel_x_d1 >= 1112 && pixel_x_d1 < 1128) begin
                char_code <= 8'd121; // 'y'
                char_col <= pixel_x_d1 - 12'd1112;
                in_char_area <= ch2_enable;
            end
            else if (pixel_x_d1 >= 1128 && pixel_x_d1 < 1144) begin
                char_code <= 8'd58;  // ':'
                char_col <= pixel_x_d1 - 12'd1128;
                in_char_area <= ch2_enable;
            end
            // CH2????????(???: 50.0%)
            else if (pixel_x_d1 >= 1152 && pixel_x_d1 < 1168) begin
                char_code <= digit_to_ascii(ch2_duty_d2);
                char_col <= pixel_x_d1 - 12'd1152;
                in_char_area <= ch2_enable;
            end
            else if (pixel_x_d1 >= 1168 && pixel_x_d1 < 1184) begin
                char_code <= digit_to_ascii(ch2_duty_d1);
                char_col <= pixel_x_d1 - 12'd1168;
                in_char_area <= ch2_enable;
            end
            else if (pixel_x_d1 >= 1184 && pixel_x_d1 < 1200) begin
                char_code <= 8'd46;  // '.'
                char_col <= pixel_x_d1 - 12'd1184;
                in_char_area <= ch2_enable;
            end
            else if (pixel_x_d1 >= 1200 && pixel_x_d1 < 1216) begin
                char_code <= digit_to_ascii(ch2_duty_d0);
                char_col <= pixel_x_d1 - 12'd1200;
                in_char_area <= ch2_enable;
            end
            else if (pixel_x_d1 >= 1216 && pixel_x_d1 < 1232) begin
                char_code <= 8'd37;  // '%'
                char_col <= pixel_x_d1 - 12'd1216;
                in_char_area <= ch2_enable;
            end
        end
        
        // ========== ???? THD "CH1 THD: 1.23%    CH2 THD: 1.23%" ==========
        else if (pixel_y_d1 >= PARAM_Y_START + 105 && pixel_y_d1 < PARAM_Y_START + 137) begin
            char_row <= pixel_y_d1 - PARAM_Y_START - 12'd105;
            
            // ----- CH1 THD (???) -----
            // "CH1 "
            if (pixel_x_d1 >= 40 && pixel_x_d1 < 56) begin
                char_code <= 8'd67;  // 'C'
                char_col <= pixel_x_d1 - 12'd40;
                in_char_area <= ch1_enable;
            end
            else if (pixel_x_d1 >= 56 && pixel_x_d1 < 72) begin
                char_code <= 8'd72;  // 'H'
                char_col <= pixel_x_d1 - 12'd56;
                in_char_area <= ch1_enable;
            end
            else if (pixel_x_d1 >= 72 && pixel_x_d1 < 88) begin
                char_code <= 8'd49;  // '1'
                char_col <= pixel_x_d1 - 12'd72;
                in_char_area <= ch1_enable;
            end
            // "THD: "
            else if (pixel_x_d1 >= 104 && pixel_x_d1 < 120) begin
                char_code <= 8'd84;  // 'T'
                char_col <= pixel_x_d1 - 12'd104;
                in_char_area <= ch1_enable;
            end
            else if (pixel_x_d1 >= 120 && pixel_x_d1 < 136) begin
                char_code <= 8'd72;  // 'H'
                char_col <= pixel_x_d1 - 12'd120;
                in_char_area <= ch1_enable;
            end
            else if (pixel_x_d1 >= 136 && pixel_x_d1 < 152) begin
                char_code <= 8'd68;  // 'D'
                char_col <= pixel_x_d1 - 12'd136;
                in_char_area <= ch1_enable;
            end
            else if (pixel_x_d1 >= 152 && pixel_x_d1 < 168) begin
                char_code <= 8'd58;  // ':'
                char_col <= pixel_x_d1 - 12'd152;
                in_char_area <= ch1_enable;
            end
            // CH1 THD????(???: 1.23%)
            else if (pixel_x_d1 >= 192 && pixel_x_d1 < 208) begin
                char_code <= digit_to_ascii(ch1_thd_d2);
                char_col <= pixel_x_d1 - 12'd192;
                in_char_area <= ch1_enable;
            end
            else if (pixel_x_d1 >= 208 && pixel_x_d1 < 224) begin
                char_code <= 8'd46;  // '.'
                char_col <= pixel_x_d1 - 12'd208;
                in_char_area <= ch1_enable;
            end
            else if (pixel_x_d1 >= 224 && pixel_x_d1 < 240) begin
                char_code <= digit_to_ascii(ch1_thd_d1);
                char_col <= pixel_x_d1 - 12'd224;
                in_char_area <= ch1_enable;
            end
            else if (pixel_x_d1 >= 240 && pixel_x_d1 < 256) begin
                char_code <= digit_to_ascii(ch1_thd_d0);
                char_col <= pixel_x_d1 - 12'd240;
                in_char_area <= ch1_enable;
            end
            else if (pixel_x_d1 >= 256 && pixel_x_d1 < 272) begin
                char_code <= 8'd37;  // '%'
                char_col <= pixel_x_d1 - 12'd256;
                in_char_area <= ch1_enable;
            end
            
            // ----- CH2 THD (???) -----
            // "CH2 "
            else if (pixel_x_d1 >= 1000 && pixel_x_d1 < 1016) begin
                char_code <= 8'd67;  // 'C'
                char_col <= pixel_x_d1 - 12'd1000;
                in_char_area <= ch2_enable;
            end
            else if (pixel_x_d1 >= 1016 && pixel_x_d1 < 1032) begin
                char_code <= 8'd72;  // 'H'
                char_col <= pixel_x_d1 - 12'd1016;
                in_char_area <= ch2_enable;
            end
            else if (pixel_x_d1 >= 1032 && pixel_x_d1 < 1048) begin
                char_code <= 8'd50;  // '2'
                char_col <= pixel_x_d1 - 12'd1032;
                in_char_area <= ch2_enable;
            end
            // "THD: "
            else if (pixel_x_d1 >= 1064 && pixel_x_d1 < 1080) begin
                char_code <= 8'd84;  // 'T'
                char_col <= pixel_x_d1 - 12'd1064;
                in_char_area <= ch2_enable;
            end
            else if (pixel_x_d1 >= 1080 && pixel_x_d1 < 1096) begin
                char_code <= 8'd72;  // 'H'
                char_col <= pixel_x_d1 - 12'd1080;
                in_char_area <= ch2_enable;
            end
            else if (pixel_x_d1 >= 1096 && pixel_x_d1 < 1112) begin
                char_code <= 8'd68;  // 'D'
                char_col <= pixel_x_d1 - 12'd1096;
                in_char_area <= ch2_enable;
            end
            else if (pixel_x_d1 >= 1112 && pixel_x_d1 < 1128) begin
                char_code <= 8'd58;  // ':'
                char_col <= pixel_x_d1 - 12'd1112;
                in_char_area <= ch2_enable;
            end
            // CH2 THD????(???: 1.23%)
            else if (pixel_x_d1 >= 1152 && pixel_x_d1 < 1168) begin
                char_code <= digit_to_ascii(ch2_thd_d2);
                char_col <= pixel_x_d1 - 12'd1152;
                in_char_area <= ch2_enable;
            end
            else if (pixel_x_d1 >= 1168 && pixel_x_d1 < 1184) begin
                char_code <= 8'd46;  // '.'
                char_col <= pixel_x_d1 - 12'd1168;
                in_char_area <= ch2_enable;
            end
            else if (pixel_x_d1 >= 1184 && pixel_x_d1 < 1200) begin
                char_code <= digit_to_ascii(ch2_thd_d1);
                char_col <= pixel_x_d1 - 12'd1184;
                in_char_area <= ch2_enable;
            end
            else if (pixel_x_d1 >= 1200 && pixel_x_d1 < 1216) begin
                char_code <= digit_to_ascii(ch2_thd_d0);
                char_col <= pixel_x_d1 - 12'd1200;
                in_char_area <= ch2_enable;
            end
            else if (pixel_x_d1 >= 1216 && pixel_x_d1 < 1232) begin
                char_code <= 8'd37;  // '%'
                char_col <= pixel_x_d1 - 12'd1216;
                in_char_area <= ch2_enable;
            end
        end
        
        // ???? "Phase:180.0" (??????Y: 870+140=1010)
        else if (pixel_y_d1 >= PARAM_Y_START + 140 && pixel_y_d1 < PARAM_Y_START + 172) begin
            char_row <= pixel_y_d1 - PARAM_Y_START - 12'd140;
            // "Phase:"
            if (pixel_x_d1 >= 40 && pixel_x_d1 < 56) begin
                char_code <= 8'd80;  // 'P'
                char_col <= pixel_x_d1 - 12'd40;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 56 && pixel_x_d1 < 72) begin
                char_code <= 8'd104; // 'h'
                char_col <= pixel_x_d1 - 12'd56;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 72 && pixel_x_d1 < 88) begin
                char_code <= 8'd97;  // 'a'
                char_col <= pixel_x_d1 - 12'd72;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 88 && pixel_x_d1 < 104) begin
                char_code <= 8'd115; // 's'
                char_col <= pixel_x_d1 - 12'd88;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 104 && pixel_x_d1 < 120) begin
                char_code <= 8'd101; // 'e'
                char_col <= pixel_x_d1 - 12'd104;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 120 && pixel_x_d1 < 136) begin
                char_code <= 8'd58;  // ':'
                char_col <= pixel_x_d1 - 12'd120;
                in_char_area <= 1'b1;
            end
            // ???????????(???: 180.0)
            else if (pixel_x_d1 >= 144 && pixel_x_d1 < 160) begin
                char_code <= digit_to_ascii(phase_d3);  // ???
                char_col <= pixel_x_d1 - 12'd144;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 160 && pixel_x_d1 < 176) begin
                char_code <= digit_to_ascii(phase_d2);  // ???
                char_col <= pixel_x_d1 - 12'd160;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 176 && pixel_x_d1 < 192) begin
                char_code <= digit_to_ascii(phase_d1);  // ???
                char_col <= pixel_x_d1 - 12'd176;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 192 && pixel_x_d1 < 208) begin
                char_code <= 8'd46;  // '.'
                char_col <= pixel_x_d1 - 12'd192;
                in_char_area <= 1'b1;
            end
            else if (pixel_x_d1 >= 208 && pixel_x_d1 < 224) begin
                char_code <= digit_to_ascii(phase_d0);  // ?????
                char_col <= pixel_x_d1 - 12'd208;
                in_char_area <= 1'b1;
            end
        end
    end  // ??? if (pixel_y_d1 >= PARAM_Y_START && pixel_y_d1 < PARAM_Y_END)
    end  // ????? else begin (char_code????????
end  // ??? always @(posedge clk_pixel)

//=============================================================================
// RGB???????????? - ??????????????
//=============================================================================
always @(*) begin
    rgb_data = 24'h000000;  // ?????????
    spectrum_height_calc = 12'd0;
    char_color = 24'hFFFFFF;  // ?????????
    
    // ?????latch???????????????????
    ch1_spectrum_height = 12'd0;
    ch2_spectrum_height = 12'd0;
    
    // ??????????????????????????????
    y_axis_tick = 1'b0;
    x_axis_tick = 1'b0;
    in_axis_label = 1'b0;
    
    if (pixel_y_d3 >= SPECTRUM_Y_START && pixel_y_d3 < SPECTRUM_Y_END) begin
        // ??Y?????????????????????????????
        // ?????=75 (100%), Y=262 (75%), Y=450 (50%), Y=637 (25%), Y=825 (0%)
        if (pixel_x_d3 >= AXIS_LEFT_MARGIN - TICK_LENGTH && pixel_x_d3 < AXIS_LEFT_MARGIN) begin
            if (pixel_y_d3 == 75 || pixel_y_d3 == 262 || pixel_y_d3 == 450 || 
                pixel_y_d3 == 637 || pixel_y_d3 == 825) begin
                y_axis_tick = 1'b1;
            end
        end
        
        // ??X?????????????????????????????
        // ?????=80, 444, 808, 1172, 1536, 1840
        if (pixel_y_d3 >= SPECTRUM_Y_END - TICK_LENGTH && pixel_y_d3 < SPECTRUM_Y_END) begin
            if (pixel_x_d3 == 80 || pixel_x_d3 == 444 || pixel_x_d3 == 808 || 
                pixel_x_d3 == 1172 || pixel_x_d3 == 1536 || pixel_x_d3 == 1840) begin
                x_axis_tick = 1'b1;
            end
        end
        
        // Y??????????????????
        if (pixel_x_d3 < AXIS_LEFT_MARGIN - TICK_LENGTH - 4) begin
            in_axis_label = 1'b1;
        end
    end
    ch1_spec_hit = 1'b0;
    ch2_spec_hit = 1'b0;
    
    if (video_active_d3) begin
        // ========== ????????==========
        if (pixel_y_d3 < 50) begin
            if (pixel_x_d3 < 5 || pixel_x_d3 >= H_ACTIVE - 5 ||
                pixel_y_d3 < 2 || pixel_y_d3 >= 48) begin
                rgb_data = 24'h4080FF;  // ??????
            end else begin
                rgb_data = 24'h1A1A2E;  // ????????
            end
            
            // ????????????????????????????????
            if (pixel_y_d3 >= 15 && pixel_y_d3 < 35) begin
                // CH1???????????????????=?????
                if (pixel_x_d3 >= 20 && pixel_x_d3 < 120) begin
                    rgb_data = ch1_enable ? 24'h00FF00 : 24'h404040;
                end 
                // CH2???????????????????=?????
                else if (pixel_x_d3 >= 140 && pixel_x_d3 < 240) begin
                    rgb_data = ch2_enable ? 24'hFF0000 : 24'h404040;
                end
                // ???????????????????????????
                else if (pixel_x_d3 >= 300 && pixel_x_d3 < 500) begin
                    if (work_mode_d3 == 2'd0) begin
                        // ???????????ime_data_q????
                        rgb_data = {time_data_q[15:8], 8'h00, 8'hFF - time_data_q[15:8]};
                    end else begin
                        // ???????????pectrum_data_q????
                        rgb_data = {spectrum_data_q[15:8], spectrum_data_q[15:8], 8'h00};
                    end
                end
            end
        end
        
        // ========== ???/????????? ==========
        else if (pixel_y_d3 >= SPECTRUM_Y_START && pixel_y_d3 < SPECTRUM_Y_END) begin
            
            // ??????????????????
            // Y????????????
            if (pixel_x_d3 == AXIS_LEFT_MARGIN || pixel_x_d3 == AXIS_LEFT_MARGIN - 1) begin
                rgb_data = 24'hFFFFFF;  // ???Y??
            end
            // Y??????
            else if (y_axis_tick) begin
                rgb_data = 24'hCCCCCC;  // ?????????
            end
            // X??????
            else if (x_axis_tick) begin
                rgb_data = 24'hCCCCCC;  // ?????????
            end
            // Y?????????????????
            else if (in_axis_label) begin
                rgb_data = 24'h1A1A2E;  // ??????
                // Y???????????
                if (in_char_area_d1 && char_pixel_row[15 - char_col_d1[3:0]]) begin
                    rgb_data = 24'hFFFFFF;  // ??????
                end
            end
            
            // ========== ??????0???????????==========
            else if (work_mode_d4 == 2'd0) begin
                // ?????????d4?????
                if (grid_x_flag_d4 || grid_y_flag_d4) begin
                    rgb_data = 24'h303030;  // ??????
                end
                // ??????????V?????
                else if (pixel_y_d4 == WAVEFORM_CENTER_Y || 
                         pixel_y_d4 == WAVEFORM_CENTER_Y + 1) begin
                    rgb_data = 24'h606060;  // ????????
                end
                else begin
                    // ?????3????????GB???????????tage 4?????h1_hit/ch2_hit??
                    // ???case?????????if-else????????????????
                    case ({ch1_hit & ch1_enable_d4, ch2_hit & ch2_enable_d4})
                        2'b11: rgb_data = 24'hFFFF00;  // ??????????????
                        2'b10: rgb_data = 24'h00FF00;  // ??????CH1??
                        2'b01: rgb_data = 24'hFF0000;  // ??????CH2??
                        default: rgb_data = {8'd16, 8'd16, (8'd20 + {5'd0, pixel_y_d4[8:6]})};  // ??????
                    endcase
                end
            end
            
            // ========== ??????1???????????==========
            else begin
                // ??????????????????x?????
                // CH1??????
                if (ch1_data_q > 16'd8000)
                    ch1_spectrum_height = 12'd700;
                else if (ch1_data_q < 16'd4)
                    ch1_spectrum_height = 12'd0;
                else
                    ch1_spectrum_height = {ch1_data_q[12:0], 2'b00};
                
                // CH2??????
                if (ch2_data_q > 16'd8000)
                    ch2_spectrum_height = 12'd700;
                else if (ch2_data_q < 16'd4)
                    ch2_spectrum_height = 12'd0;
                else
                    ch2_spectrum_height = {ch2_data_q[12:0], 2'b00};
                
                // ?????????????????????
                spectrum_height_calc = ch1_enable ? ch1_spectrum_height : ch2_spectrum_height;
                
                // ?????????d4?????
                if (grid_x_flag_d4 || grid_y_flag_d4) begin
                    rgb_data = 24'h303030;
                end
                else begin
                    // ????????????????????????tage 4???
                    // ???Stage 3????????????ch1_spectrum_calc_d1, ch2_spectrum_calc_d1??
                    
                    // ?????3???????????GB???????????f??
                    ch1_spec_hit = ch1_enable_d4 && (pixel_y_d4 >= (SPECTRUM_Y_END - ch1_spectrum_calc_d1 - 10));
                    ch2_spec_hit = ch2_enable_d4 && (pixel_y_d4 >= (SPECTRUM_Y_END - ch2_spectrum_calc_d1 - 10));
                    
                    // ???????????
                    case ({ch1_spec_hit, ch2_spec_hit})
                        2'b11: begin  // ????????
                            if (ch1_spectrum_calc_d1 > ch2_spectrum_calc_d1)
                                rgb_data = (ch1_spectrum_calc_d1 > 500) ? 24'hFFFF00 : 24'h80FF80;
                            else
                                rgb_data = (ch2_spectrum_calc_d1 > 500) ? 24'hFF8000 : 24'hFF8080;
                        end
                        2'b10: begin  // ??H1
                            if (ch1_spectrum_calc_d1 > 500)      rgb_data = 24'h00FF00;
                            else if (ch1_spectrum_calc_d1 > 350) rgb_data = 24'h00DD00;
                            else if (ch1_spectrum_calc_d1 > 200) rgb_data = 24'h00BB00;
                            else                                  rgb_data = 24'h008800;
                        end
                        2'b01: begin  // ??H2
                            if (ch2_spectrum_calc_d1 > 500)      rgb_data = 24'hFF0000;
                            else if (ch2_spectrum_calc_d1 > 350) rgb_data = 24'hDD0000;
                            else if (ch2_spectrum_calc_d1 > 200) rgb_data = 24'hBB0000;
                            else                                  rgb_data = 24'h880000;
                        end
                        default: rgb_data = {8'd16, 8'd16, (8'd20 + {5'd0, pixel_y_d4[8:6]})};  // ???
                    endcase
                end
            end  // ??? work_mode_d4 else ??
        end
        
        // ========== ????????+ AI????????? ==========
        else if (pixel_y_d3 >= SPECTRUM_Y_END && pixel_y_d3 < PARAM_Y_START) begin
            // ?????
            if (pixel_y_d3 == SPECTRUM_Y_END || pixel_y_d3 == PARAM_Y_START - 1) begin
                rgb_data = 24'h4080FF;  // ????????
            end
            // ??X??????????????????32?????
            else if (pixel_y_d4 >= SPECTRUM_Y_END && pixel_y_d4 < SPECTRUM_Y_END + 32) begin
                rgb_data = 24'h1A1A2E;  // ??????
                // X???????????
                if (in_char_area_d1 && char_pixel_row[15 - char_col_d1[3:0]]) begin
                    rgb_data = 24'hFFFFFF;  // ??????
                end
            end
            // AI????????? (Y: 830-862)
            else if (pixel_y_d4 >= 830 && pixel_y_d4 < 862) begin
                rgb_data = 24'h0F0F23;  // ??????
                // AI?????????
                if (in_char_area_d1 && char_pixel_row[15 - char_col_d1[3:0]]) begin
                    rgb_data = 24'hFFFFFF;  // ??? - AI??????
                end
            end
            else begin
                rgb_data = 24'h0F0F23;  // ??????
            end
        end
        
        // ========== ????????? ==========
        // ?????????????har_code??????????????????d4???
        else if (pixel_y_d4 >= PARAM_Y_START && pixel_y_d4 < PARAM_Y_END) begin
            // ??????
            rgb_data = {8'd15, 8'd15, 8'd30};  // ????????
            
            // ?????????????????OM?????n_char_area?????
            // ???????????????????in_char_area_d1??har_col_d1
            if (in_char_area_d1 && char_pixel_row[15 - char_col_d1[3:0]]) begin
                // ?????????????????????????????px?????
                if (pixel_y_d4 < PARAM_Y_START + 35)           // Y < 905: ????(???)
                    char_color = 24'h00FFFF;  // ??? - ???
                else if (pixel_y_d4 < PARAM_Y_START + 70)      // Y < 940: ????(???)
                    char_color = 24'hFFFF00;  // ??? - ???
                else if (pixel_y_d4 < PARAM_Y_START + 105)     // Y < 975: ????(?????
                    char_color = 24'h00FF00;  // ??? - ?????
                else if (pixel_y_d4 < PARAM_Y_START + 140)     // Y < 1010: ????(THD)
                    char_color = 24'hFF8800;  // ??? - THD
                else if (pixel_y_d4 < PARAM_Y_START + 175)     // Y < 1045: ????(?????
                    char_color = 24'hFF00FF;  // ?????- ?????
                else                                           // Y >= 1045: ????(AI???)
                    char_color = 24'hFFFFFF;  // ??? - AI??????
                
                rgb_data = char_color;
            end
        end
        
        // ========== ?????? ==========
        else if (pixel_y_d3 >= PARAM_Y_END) begin
            if (pixel_y_d3 >= V_ACTIVE - 2) begin
                rgb_data = 24'h4080FF;  // ??????
            end else begin
                rgb_data = 24'h000000;  // ???
            end
        end
        
        // ========== ?????? ==========
        // ???????????????????????????
        if (pixel_x_d3 < 2) begin
            rgb_data = 24'h4080FF;  // ????????
        end 
        else if (pixel_x_d3 >= H_ACTIVE - 2) begin
            rgb_data = 24'h4080FF;  // ????????
        end
    end
end

//=============================================================================
// ????????
//=============================================================================
always @(posedge clk_pixel or negedge rst_n) begin
    if (!rst_n) begin
        rgb_out_reg <= 24'h000000;
        de_out_reg  <= 1'b0;
        hs_out_reg  <= 1'b0;  // ????????????0?????????????
        vs_out_reg  <= 1'b0;  // ????????????0?????????????
    end else begin
        rgb_out_reg <= rgb_data;
        de_out_reg  <= video_active_d4;  // ?????????????4??????????????
        hs_out_reg  <= hs_internal;
        vs_out_reg  <= vs_internal;
    end
end

assign rgb_out = rgb_out_reg;
assign de_out  = de_out_reg;
assign hs_out  = hs_out_reg;
assign vs_out  = vs_out_reg;

endmodule
