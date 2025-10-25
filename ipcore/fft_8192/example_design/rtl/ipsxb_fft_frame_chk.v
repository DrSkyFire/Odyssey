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
// Functional description: fft frame checker
// Note: The module only checkes the interface timing and doesn't check the frame data value.                                                          

module ipsxb_fft_frame_chk ( 
    i_aclk                 ,
    i_aclken               ,
    i_aresetn              ,
    
    i_axi4s_data_tvalid    ,
    i_axi4s_data_tdata     ,
    i_axi4s_data_tlast     ,
    i_axi4s_data_tuser     ,
    
    i_start_test           , // pulse
    o_chk_finished         ,
    o_err
);

parameter   FRAME_CHK_PRINT_EN= 0       ;
parameter   FRAME_CHK_DATA_EN = 0       ;
parameter   TEST_FRAME_NUM    = 10      ;
parameter   MAX_TIME_OF_FFT   = 21      ;
// ------------
parameter   LOGS_FFT_LEN      = 4       ;  
parameter   OUTPUT_ORDER      = 1       ; // 1: natural; 0: bit reversed   
parameter   INPUT_WIDTH       = 16      ;
parameter   SCALE_MODE        = 0       ; // 1: block floating point; 0: unscaled

function integer clog2;
    input integer n;
    begin
        n = n - 1;
        for (clog2=0; n>0; clog2=clog2+1)
            n = n >> 1;
    end
endfunction

function [LOGS_FFT_LEN-1:0] bit_rev;
    input [LOGS_FFT_LEN-1:0] din;
    integer i;
    begin
        for (i=0; i<LOGS_FFT_LEN; i=i+1)
            bit_rev[i] = din[LOGS_FFT_LEN-1-i];
    end
endfunction

localparam  UNSCALED_WIDTH    = INPUT_WIDTH + LOGS_FFT_LEN + 1;
localparam  OUTPUT_WIDTH      = SCALE_MODE ? INPUT_WIDTH : UNSCALED_WIDTH;
localparam  DATAOUT_BYTE_NUM  = ((OUTPUT_WIDTH%8)==0) ? OUTPUT_WIDTH/8 : OUTPUT_WIDTH/8 + 1;
localparam  DATAOUT_WIDTH     = DATAOUT_BYTE_NUM * 8;
localparam  USER_BYTE_NUM     = ((LOGS_FFT_LEN%8)==0) ? LOGS_FFT_LEN/8 + 1: LOGS_FFT_LEN/8 + 2; // blk_exp and index
localparam  USER_WIDTH        = USER_BYTE_NUM * 8;

localparam  FRM_CNT_WIDTH     = clog2(TEST_FRAME_NUM);
localparam  CHK_TIME_CNT_WIDTH= MAX_TIME_OF_FFT + FRM_CNT_WIDTH;

input                             i_aclk             ;
input                             i_aclken           ;
input                             i_aresetn          ;
input                             i_axi4s_data_tvalid;
input      [DATAOUT_WIDTH*2-1:0]  i_axi4s_data_tdata ;
input                             i_axi4s_data_tlast ;
input      [USER_WIDTH-1:0]       i_axi4s_data_tuser ;
input                             i_start_test       ;
output reg                        o_chk_finished = 1'b1;
output                            o_err              ;

reg     [FRM_CNT_WIDTH-1:0]       frm_cnt   = {FRM_CNT_WIDTH{1'b0}}; // supports no reset
reg     [LOGS_FFT_LEN-1:0]        data_cnt  = {LOGS_FFT_LEN{1'b0}}; // supports no reset
reg     [CHK_TIME_CNT_WIDTH-1:0]  chk_time_cnt = {CHK_TIME_CNT_WIDTH{1'b0}};

reg                               frm_cnt_err    = 1'b0;
reg                               data_cnt_err   = 1'b0;

wire    [LOGS_FFT_LEN-1:0]        usr_index          ;

assign usr_index = i_axi4s_data_tuser[LOGS_FFT_LEN-1:0];

always @(posedge i_aclk or negedge i_aresetn) begin
    if (~i_aresetn)
        data_cnt <= {LOGS_FFT_LEN{1'b0}};
    else if (i_aclken) begin
        if (i_start_test)
            data_cnt <= {LOGS_FFT_LEN{1'b0}};        
        else if (i_axi4s_data_tvalid)
            data_cnt <= data_cnt + 1'b1;
    end
end

always @(posedge i_aclk or negedge i_aresetn) begin
    if (~i_aresetn)
        frm_cnt <= {FRM_CNT_WIDTH{1'b0}};     
    else if (i_aclken) begin
        if (i_start_test)
            frm_cnt <= {FRM_CNT_WIDTH{1'b0}};           
        else if (i_axi4s_data_tlast) begin
            if (frm_cnt < TEST_FRAME_NUM-1)
                frm_cnt <= frm_cnt + 1'b1;
        end
    end
end

always @(posedge i_aclk or negedge i_aresetn) begin
    if (~i_aresetn)
        data_cnt_err <= 1'b0;
    else if (i_aclken) begin
        if (i_start_test)
            data_cnt_err <= 1'b0;
        else if (i_axi4s_data_tvalid) begin
            if (OUTPUT_ORDER==1 && data_cnt!=usr_index)
                data_cnt_err <= 1'b1;
            else if (OUTPUT_ORDER==0 && data_cnt!=bit_rev(usr_index))
                data_cnt_err <= 1'b1;
            else
                data_cnt_err <= 1'b0;
        end
        else
            data_cnt_err <= 1'b0;
    end
end    
       
// -------------------------------------------------------
always @(posedge i_aclk or negedge i_aresetn) begin
    if (~i_aresetn)
        chk_time_cnt <= {CHK_TIME_CNT_WIDTH{1'b0}};      
    else if (i_aclken) begin
        if (i_start_test)
            chk_time_cnt <= {{(CHK_TIME_CNT_WIDTH-1){1'b0}}, 1'b1};          
        else if (chk_time_cnt != {CHK_TIME_CNT_WIDTH{1'b0}})
            chk_time_cnt <= chk_time_cnt + 1'b1;
    end
end

always @(posedge i_aclk or negedge i_aresetn) begin
    if (~i_aresetn)
        o_chk_finished <= 1'b1;
    else if (i_aclken) begin
        if (i_start_test)
            o_chk_finished <= 1'b0;        
        else if (chk_time_cnt == {CHK_TIME_CNT_WIDTH{1'b1}})
            o_chk_finished <= 1'b1;
    end
end

always @(posedge i_aclk or negedge i_aresetn) begin
    if (~i_aresetn)
        frm_cnt_err <= 1'b0;
    else if (i_aclken) begin
        if (i_start_test)
            frm_cnt_err <= 1'b0;
        else if (o_chk_finished) begin
            if (frm_cnt != TEST_FRAME_NUM-1)
                frm_cnt_err <= 1'b1;
            else
                frm_cnt_err <= 1'b0;
        end
        else
            frm_cnt_err <= 1'b0;
    end
end

generate
    if (FRAME_CHK_DATA_EN) begin: check_data_en
        wire    [OUTPUT_WIDTH*2-1:0] fft_exp_data        ;
        wire    [OUTPUT_WIDTH*2-1:0] ifft_exp_data       ;
        wire    [4:0]                fft_exp_blk_exp     ;
        wire    [4:0]                ifft_exp_blk_exp    ;
        reg                          fft_data_err = 1'b0 ;
        reg                          ifft_data_err = 1'b0;
        reg                          fft_blk_exp_err = 1'b0;
        reg                          ifft_blk_exp_err = 1'b0;
        reg                          axi4s_data_tvalid_d1 = 1'b0; // supports no reset
        reg                          fft_ifft            ;
        reg     [OUTPUT_WIDTH*2-1:0] fft_ip_data         ;
        reg     [4:0]                fft_ip_blk_exp      ;
        
        ipsxe_fft_exp_rom #(
            .FFT_MODE           (1              ),
            .LOGS_FFT_LEN       (LOGS_FFT_LEN   ),
            .INPUT_WIDTH        (INPUT_WIDTH    ),
            .SCALE_MODE         (SCALE_MODE     )
        ) u_fft_exp_rom (
            .i_clk              (i_aclk         ),
            .i_clken            (i_aclken       ),
            .i_rstn             (i_aresetn      ),
            .i_addr             (data_cnt       ),
            .o_rdata            (fft_exp_data   ), // delay 1
            .o_blk_exp          (fft_exp_blk_exp    )
        );

        ipsxe_fft_exp_rom #(
            .FFT_MODE           (0              ),
            .LOGS_FFT_LEN       (LOGS_FFT_LEN   ),
            .INPUT_WIDTH        (INPUT_WIDTH    ),
            .SCALE_MODE         (SCALE_MODE     )
        ) u_ifft_exp_rom (
            .i_clk              (i_aclk         ),
            .i_clken            (i_aclken       ),
            .i_rstn             (i_aresetn      ),
            .i_addr             (data_cnt       ),
            .o_rdata            (ifft_exp_data  ), // delay 1
            .o_blk_exp          (ifft_exp_blk_exp   )
        );
        
        always @(posedge i_aclk or negedge i_aresetn) begin
            if (~i_aresetn)
                fft_ip_data <= {(OUTPUT_WIDTH*2){1'b0}};
            else if (i_aclken)
                fft_ip_data <= {i_axi4s_data_tdata[DATAOUT_WIDTH+OUTPUT_WIDTH-1:DATAOUT_WIDTH], i_axi4s_data_tdata[OUTPUT_WIDTH-1:0]};
        end

        always @(posedge i_aclk or negedge i_aresetn) begin
            if (~i_aresetn)
                fft_ip_blk_exp <= 5'd0;
            else if (i_aclken)
                fft_ip_blk_exp <= i_axi4s_data_tuser[USER_WIDTH-4:USER_WIDTH-8];
        end
                
        always @(posedge i_aclk or negedge i_aresetn) begin
            if (~i_aresetn)
                axi4s_data_tvalid_d1 <= 1'b0;
            else if (i_aclken)
                axi4s_data_tvalid_d1 <= i_axi4s_data_tvalid;
        end
        
        always @(posedge i_aclk or negedge i_aresetn) begin
            if (~i_aresetn)
                fft_ifft <= 1'b0;
            else if (i_aclken) begin
                if (i_start_test)
                    fft_ifft <= 1'b0;
                else
                    fft_ifft <= ~frm_cnt[0];
            end
        end

        always @(posedge i_aclk or negedge i_aresetn) begin
            if (~i_aresetn)
                fft_data_err <= 1'b0;
            else if (i_aclken) begin
                if (fft_ifft && axi4s_data_tvalid_d1) begin
                    if (fft_ip_data == fft_exp_data)
                        fft_data_err <= 1'b0;
                    else
                        fft_data_err <= 1'b1;
                end
                else
                    fft_data_err <= 1'b0;
            end
        end
            
        always @(posedge i_aclk or negedge i_aresetn) begin
            if (~i_aresetn)
                ifft_data_err <= 1'b0;
            else if (i_aclken) begin
                if (~fft_ifft && axi4s_data_tvalid_d1) begin
                    if (fft_ip_data == ifft_exp_data)
                        ifft_data_err <= 1'b0;
                    else
                        ifft_data_err <= 1'b1;
                end
                else
                    ifft_data_err <= 1'b0;
            end
        end
        
        always @(posedge i_aclk or negedge i_aresetn) begin
            if (~i_aresetn)
                fft_blk_exp_err <= 1'b0;
            else if (i_aclken) begin
                if (fft_ifft && axi4s_data_tvalid_d1) begin
                    if (fft_ip_blk_exp == fft_exp_blk_exp)
                        fft_blk_exp_err <= 1'b0;
                    else
                        fft_blk_exp_err <= 1'b1;
                end
            else
                fft_blk_exp_err <= 1'b0;
            end
        end

        always @(posedge i_aclk or negedge i_aresetn) begin
            if (~i_aresetn)
                ifft_blk_exp_err <= 1'b0;
            else if (i_aclken) begin
                if (fft_ifft && axi4s_data_tvalid_d1) begin
                    if (fft_ip_blk_exp == ifft_exp_blk_exp)
                        ifft_blk_exp_err <= 1'b0;
                    else
                        ifft_blk_exp_err <= 1'b1;
                end
            else
                ifft_blk_exp_err <= 1'b0;
            end
        end
        
        assign o_err = data_cnt_err | frm_cnt_err | fft_data_err | ifft_data_err | fft_blk_exp_err | ifft_blk_exp_err;        
    end      
    else begin: no_check_data_en
        assign o_err = data_cnt_err | frm_cnt_err;
    end
endgenerate

generate
    if (FRAME_CHK_PRINT_EN) begin: print_input_data
        integer fp_fft_re       ;
        integer fp_fft_im       ;
        integer fp_ifft_re      ;
        integer fp_ifft_im      ;
        reg     fp_close_slot   ;
            
        initial begin
            fp_fft_re = $fopen("../../ip_file/ip_fft_xk_re.txt", "w");
            fp_fft_im = $fopen("../../ip_file/ip_fft_xk_im.txt", "w");

            fp_ifft_re = $fopen("../../ip_file/ip_ifft_xk_re.txt", "w");
            fp_ifft_im = $fopen("../../ip_file/ip_ifft_xk_im.txt", "w");
                        
            //wait (frm_cnt > {{(FRM_CNT_WIDTH-1){1'b0}}, 1'b1}) // only prints two frame data
            //
            //$fclose(fp_fft_re);
            //$fclose(fp_fft_im); 
            //$fclose(fp_ifft_re); 
            //$fclose(fp_ifft_im); 
        end 
        
        always @(posedge i_aclk) begin            
            if (i_aclken && i_axi4s_data_tvalid && frm_cnt=={FRM_CNT_WIDTH{1'b0}}) begin
                $fdisplay(fp_fft_re, "%H", i_axi4s_data_tdata[OUTPUT_WIDTH-1:0]);
                $fdisplay(fp_fft_im, "%H", i_axi4s_data_tdata[DATAOUT_WIDTH+OUTPUT_WIDTH-1:DATAOUT_WIDTH]);
            end
        end
        
        always @(posedge i_aclk) begin
            if (i_aclken && i_axi4s_data_tvalid && frm_cnt=={{(FRM_CNT_WIDTH-1){1'b0}}, 1'b1}) begin
                $fdisplay(fp_ifft_re, "%H", i_axi4s_data_tdata[OUTPUT_WIDTH-1:0]);
                $fdisplay(fp_ifft_im, "%H", i_axi4s_data_tdata[DATAOUT_WIDTH+OUTPUT_WIDTH-1:DATAOUT_WIDTH]);
            end
        end
        
        always @(posedge i_aclk) begin
            if (i_aclken) begin
                if (frm_cnt=={{(FRM_CNT_WIDTH-1){1'b0}}, 1'b1} && i_axi4s_data_tlast)
                    fp_close_slot <= 1'b1;
                else
                    fp_close_slot <= 1'b0;
            end
                
            if (i_aclken && fp_close_slot) begin// only prints one frame data
                $fclose(fp_fft_re);
                $fclose(fp_fft_im); 
                $fclose(fp_ifft_re); 
                $fclose(fp_ifft_im); 
            end
        end 
    end
endgenerate

endmodule      