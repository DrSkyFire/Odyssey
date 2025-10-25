//////////////////////////////////////////////////////////////////////////////
//
// Copyright (c) 2022 PANGO MICROSYSTEMS, INC
// ALL RIGHTS REVERVED.
//
// THE SOURCE CODE CONTAINED HEREIN IS PROPRIETARY TO PANGO MICROSYSTEMS, INC.
// IT SHALL NOT BE REPRODUCED OR DISCLOSED IN WHOLE OR IN PART OR USED BY
// PARTIES WITHOUT WRITTEN AUTHORIZATION FROM THE OWNER.
//
//////////////////////////////////////////////////////////////////////////////
// Functional description: fft frame generator

module ipsxb_fft_frame_gen ( 
    i_aclk                 ,
    i_aresetn              ,
    o_aclken               ,
    
    i_axi4s_data_tready    ,
    o_axi4s_data_tvalid    ,
    o_axi4s_data_tdata     ,
    o_axi4s_data_tlast     ,
       
    o_axi4s_cfg_tvalid     ,
    o_axi4s_cfg_tdata      ,
    
    i_start_test           , // pulse
    i_chk_finished         ,
    i_stat
);

parameter   FRAME_GEN_PRINT_EN= 0       ;
parameter   CLKDIV            = 2       ;
parameter   TEST_FRAME_NUM    = 10      ;
// ------------
parameter   LOGS_FFT_LEN      = 4       ;   
parameter   INPUT_WIDTH       = 16      ;

function integer clog2;
    input integer n;
    begin
        n = n - 1;
        for (clog2=0; n>0; clog2=clog2+1)
            n = n >> 1;
    end
endfunction

localparam  DATAIN_BYTE_NUM   = ((INPUT_WIDTH%8)==0) ? INPUT_WIDTH/8 : INPUT_WIDTH/8 + 1;
localparam  DATAIN_WIDTH      = DATAIN_BYTE_NUM*8;

localparam  DIV_CNT_WIDTH     = clog2(CLKDIV);
localparam  FRM_CNT_WIDTH     = clog2(TEST_FRAME_NUM);

// for test
localparam  MAX_ANY_CNT_VAL   = 2**16 - 12345;
localparam  MAX_RST_CNT_VAL   = 1023;

input                             i_aclk             ;
input                             i_aresetn          ;
output                            o_aclken           ;
input                             i_axi4s_data_tready;
output reg                        o_axi4s_data_tvalid;
output     [DATAIN_WIDTH*2-1:0]   o_axi4s_data_tdata ;
output reg                        o_axi4s_data_tlast ;
output reg                        o_axi4s_cfg_tvalid ;
output                            o_axi4s_cfg_tdata  ;
input                             i_start_test       ;
input                             i_chk_finished     ;
input                             i_stat             ;

// ------------------------------------
reg        [INPUT_WIDTH-1:0]      data_re = {{(INPUT_WIDTH-1){1'b0}}, 1'b1}; // supports no reset
reg        [INPUT_WIDTH-1:0]      data_im = {{(INPUT_WIDTH-1){1'b1}}, 1'b0}; // supports no reset

reg                         fft_mode = 1'b1; // default: fft
reg     [FRM_CNT_WIDTH-1:0] frm_cnt   = {FRM_CNT_WIDTH{1'b0}}; // supports no reset

wire                        datain_frame_started     ;
wire                        frm_gen_en               ;

reg     [LOGS_FFT_LEN-1:0]  data_cnt  = {LOGS_FFT_LEN{1'b0}}; // supports no reset

reg                         test_run  = 1'b0;

// -------------------------------------------------------------------

assign datain_frame_started = i_stat;

generate
    if (CLKDIV != 1) begin: clkdiv_en
        reg     [DIV_CNT_WIDTH-1:0] div_cnt   = {DIV_CNT_WIDTH{1'b0}}; // supports no reset
        reg     clken;
        always @(posedge i_aclk or negedge i_aresetn) begin
            if (~i_aresetn)
                div_cnt <= {DIV_CNT_WIDTH{1'b0}};
            else if (div_cnt == CLKDIV-1)
                div_cnt <= {DIV_CNT_WIDTH{1'b0}};
            else
                div_cnt <= div_cnt + 1'b1;
        end

        always @(posedge i_aclk or negedge i_aresetn) begin
            if (~i_aresetn)
                clken <= 1'b0;
            else if (div_cnt == CLKDIV-1) 
                clken <= 1'b1;
            else
                clken <= 1'b0;
        end
        assign o_aclken = clken;  
    end
    else begin: no_clkdiv_en
        assign o_aclken = 1'b1;
    end
endgenerate

// ----------------------------------------------------------------------------
always @(posedge i_aclk or negedge i_aresetn) begin
    if (~i_aresetn)
        test_run <= 1'b0;
    else if (o_aclken) begin
        if (i_start_test)
            test_run <= 1'b1;
        else if (i_chk_finished)
            test_run <= 1'b0;
    end
end

// configs fft
always @(posedge i_aclk or negedge i_aresetn) begin
    if (~i_aresetn)
        fft_mode <= 1'b1;
    else if (o_aclken) begin
        if (i_start_test)
            fft_mode <= 1'b1;
        else if (datain_frame_started)  // The value is loaded into the core in this slot by FFT IP
            fft_mode <= ~fft_mode; // Alterante fft frame and ifft frame
    end
end

assign o_axi4s_cfg_tdata = fft_mode;

always @(posedge i_aclk or negedge i_aresetn) begin
    if (~i_aresetn)
        o_axi4s_cfg_tvalid <= 1'b0;
    else if (o_aclken) begin
        if (o_axi4s_cfg_tvalid)
            o_axi4s_cfg_tvalid <= 1'b0;
        else if (i_start_test || datain_frame_started)    
            o_axi4s_cfg_tvalid <= 1'b1;
        else
            o_axi4s_cfg_tvalid <= 1'b0;
    end
end

// -----------------------------------
assign frm_gen_en = i_axi4s_data_tready & o_axi4s_data_tvalid;

always @(posedge i_aclk or negedge i_aresetn) begin
    if (~i_aresetn)
        frm_cnt <= {FRM_CNT_WIDTH{1'b0}};
    else if (o_aclken) begin
        if (i_start_test)
            frm_cnt <= {FRM_CNT_WIDTH{1'b0}};
        else if (frm_gen_en && o_axi4s_data_tlast) begin
            if (frm_cnt < TEST_FRAME_NUM-1)
                frm_cnt <= frm_cnt + 1'b1;
        end
    end
end       

always @(posedge i_aclk or negedge i_aresetn) begin
    if (~i_aresetn)
        data_cnt <= {LOGS_FFT_LEN{1'b0}};
    else if (o_aclken) begin
        if (i_start_test)
            data_cnt <= {LOGS_FFT_LEN{1'b0}};        
        else if (frm_gen_en) begin
            if (frm_cnt < TEST_FRAME_NUM)
                data_cnt <= data_cnt + 1'b1;
        end
    end
end

always @(posedge i_aclk or negedge i_aresetn) begin
    if (~i_aresetn)
        o_axi4s_data_tvalid <= 1'b0;
    else if (o_aclken) begin
        if (i_start_test)
            o_axi4s_data_tvalid <= 1'b0;
        else if (i_axi4s_data_tready && frm_cnt=={FRM_CNT_WIDTH{1'b0}} && test_run) // wait ending of first configuration
            o_axi4s_data_tvalid <= 1'b1;
        else if (i_axi4s_data_tready && frm_cnt==TEST_FRAME_NUM-1 && o_axi4s_data_tlast)
            o_axi4s_data_tvalid <= 1'b0;
    end
end       

always @(posedge i_aclk or negedge i_aresetn) begin
    if (~i_aresetn)
        o_axi4s_data_tlast <= 1'b0;
    else if (o_aclken) begin     
        if (frm_gen_en) begin
            if (data_cnt == {{(LOGS_FFT_LEN-1){1'b1}}, 1'b0})
                o_axi4s_data_tlast <= 1'b1;
            else
                o_axi4s_data_tlast <= 1'b0;
        end
    end
end

always @(posedge i_aclk or negedge i_aresetn) begin
    if (~i_aresetn) begin
        data_re <= {{(INPUT_WIDTH-1){1'b0}}, 1'b1};
        data_im <= {{(INPUT_WIDTH-1){1'b1}}, 1'b0};
    end
    else if (o_aclken) begin     
        if (frm_gen_en) begin
            if (o_axi4s_data_tlast) begin
                data_re <= {{(INPUT_WIDTH-1){1'b0}}, 1'b1};
                data_im <= {{(INPUT_WIDTH-1){1'b1}}, 1'b0};
            end
            else begin
                data_re <= {data_re[INPUT_WIDTH-2:0], (data_re[INPUT_WIDTH-1] ^ data_re[0])};
                data_im <= {data_im[INPUT_WIDTH-2:0], (data_im[INPUT_WIDTH-1] ^ data_im[0])};
            end
        end
    end
end     

generate
    if (DATAIN_WIDTH == INPUT_WIDTH) begin: no_bit_ext
        assign o_axi4s_data_tdata[DATAIN_WIDTH-1:0] = data_re;
        assign o_axi4s_data_tdata[DATAIN_WIDTH*2-1:DATAIN_WIDTH] = data_im;        
    end
    else begin: en_bit_ext          
        assign o_axi4s_data_tdata[DATAIN_WIDTH-1:0] = {{(DATAIN_WIDTH-INPUT_WIDTH){data_re[INPUT_WIDTH-1]}}, data_re};
        assign o_axi4s_data_tdata[DATAIN_WIDTH*2-1:DATAIN_WIDTH] = {{(DATAIN_WIDTH-INPUT_WIDTH){data_im[INPUT_WIDTH-1]}}, data_im};
    end
endgenerate

generate 
    if (FRAME_GEN_PRINT_EN) begin: print_input_data
        integer fp_re       ;
        integer fp_im       ;
        reg     fp_close_slot;
    
        initial begin
            fp_re = $fopen("../../ip_file/ip_xn_re.txt", "w");
            fp_im = $fopen("../../ip_file/ip_xn_im.txt", "w");
            
            //wait (frm_cnt > {FRM_CNT_WIDTH{1'b0}}) // only prints one frame data
            //
            //$fclose(fp_re);
            //$fclose(fp_im);
        end 
        
        always @(posedge i_aclk) begin
            if (i_aresetn && o_aclken && frm_gen_en && frm_cnt=={FRM_CNT_WIDTH{1'b0}}) begin
                $fdisplay(fp_re, "%H", data_re);
                $fdisplay(fp_im, "%H", data_im);
            end
        end
        
        always @(posedge i_aclk or negedge i_aresetn) begin
            if (~i_aresetn)
                fp_close_slot <= 1'b0;
            else if (o_aclken) begin
                if (frm_gen_en && frm_cnt=={FRM_CNT_WIDTH{1'b0}} && o_axi4s_data_tlast)
                    fp_close_slot <= 1'b1;
                else
                    fp_close_slot <= 1'b0;
            end
        end
        
        always @(posedge i_aclk) begin        
            if (o_aclken && fp_close_slot) begin// only prints one frame data
                $fclose(fp_re);
                $fclose(fp_im);
            end
        end           
    end
endgenerate
                
endmodule