
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

module ipsxb_fft_onboard_top ( 
    input      i_clk                 ,
    input      i_rstn                ,
    input      i_start_test          , 
    output     o_err                 ,
    output     o_chk_finished
);
localparam  FRAME_GEN_PRINT_EN= 0       ;
localparam  FRAME_CHK_PRINT_EN= 0       ;
localparam  FRAME_CHK_DATA_EN = 0       ;
localparam  TEST_FRAME_NUM    = 4       ;

localparam  CLKDIV            = ("FALSE" == "TRUE" ) ? 3  : 1;

localparam  FFT_ARCH          = ("Pipeline" == "Radix-2 Burst") ? 1 : 0; 

localparam  LOGS_FFT_LEN      = ("8192" == "8"    ) ? 3  :
                                ("8192" == "16"   ) ? 4  :
                                ("8192" == "32"   ) ? 5  :
                                ("8192" == "64"   ) ? 6  :
                                ("8192" == "128"  ) ? 7  :
                                ("8192" == "256"  ) ? 8  :
                                ("8192" == "512"  ) ? 9  :
                                ("8192" == "1024" ) ? 10 :
                                ("8192" == "2048" ) ? 11 :
                                ("8192" == "4096" ) ? 12 :
                                ("8192" == "8192" ) ? 13 :
                                ("8192" == "16384") ? 14 :
                                ("8192" == "32768") ? 15 :
                                                    16 ;
                                                    
function integer clog2;
    input integer n;
    begin
        n = n - 1;
        for (clog2=0; n>0; clog2=clog2+1)
            n = n >> 1;
    end
endfunction
                                                    
localparam  MAX_TIME_OF_FFT  = (FFT_ARCH==1) ? (LOGS_FFT_LEN+clog2(LOGS_FFT_LEN)+1) : (LOGS_FFT_LEN+2);
                                                   

localparam  OUTPUT_ORDER      = ("Natural Order" == "Natural Order") ? 1 : 0; 

localparam  SCALE_MODE        = ("Block Floating Point" == "Block Floating Point") ? 1 : 0; 

localparam  INPUT_WIDTH       = 10;

 
localparam  DATAIN_BYTE_NUM   = ((INPUT_WIDTH%8)==0) ? INPUT_WIDTH/8 : INPUT_WIDTH/8 + 1;
localparam  DATAIN_WIDTH      = DATAIN_BYTE_NUM*8;
localparam  UNSCALED_WIDTH    = INPUT_WIDTH + LOGS_FFT_LEN + 1;
localparam  OUTPUT_WIDTH      = SCALE_MODE ? INPUT_WIDTH : UNSCALED_WIDTH;
localparam  DATAOUT_BYTE_NUM  = ((OUTPUT_WIDTH%8)==0) ? OUTPUT_WIDTH/8 : OUTPUT_WIDTH/8 + 1;
localparam  DATAOUT_WIDTH     = DATAOUT_BYTE_NUM * 8;
localparam  USER_BYTE_NUM     = ((LOGS_FFT_LEN%8)==0) ? LOGS_FFT_LEN/8 + 1: LOGS_FFT_LEN/8 + 2; // blk_exp and index
localparam  USER_WIDTH        = USER_BYTE_NUM * 8;

// for test
localparam  DB_CNT_MAX        = 2048;
localparam  DB_CNT_WIDTH      = 12;

wire                          aclken              ; 
wire                          xn_axi4s_data_tvalid;
wire   [DATAIN_WIDTH*2-1:0]   xn_axi4s_data_tdata ;
wire                          xn_axi4s_data_tlast ;
wire                          xn_axi4s_data_tready;
wire                          xn_axi4s_cfg_tvalid ;
wire                          xn_axi4s_cfg_tdata  ;
wire                          xk_axi4s_data_tvalid;
wire   [DATAOUT_WIDTH*2-1:0]  xk_axi4s_data_tdata ;
wire                          xk_axi4s_data_tlast ;
wire   [USER_WIDTH-1:0]       xk_axi4s_data_tuser ;
wire   [2:0]                  alm                 ;
wire                          stat                ;
wire                          err                 ;
reg                           all_err_lck = 1'b0  ;

wire                          srstn               ;

reg     [2:0]                 start_test_dly = 3'b111;
reg     [DB_CNT_WIDTH-1:0]    db_cnt = {DB_CNT_WIDTH{1'b0}};
reg                           start_test_pulse = 1'b0;


ipsxb_fft_sync_arstn u_sync_arstn (
    .i_clk               (i_clk     ),
    .i_arstn_presync     (i_rstn    ),
    .o_arstn_synced      (srstn     )
);

always @(posedge i_clk or negedge srstn) begin
    if (~srstn)
        start_test_dly <= 3'b111;                                      
    else if (aclken)
        start_test_dly <= {start_test_dly[1:0], i_start_test};
end 

always @(posedge i_clk or negedge srstn) begin
    if (~srstn)
        db_cnt <= {DB_CNT_WIDTH{1'b0}};
    else if (aclken) begin
        if (start_test_dly[1] & ~start_test_dly[2] && o_chk_finished)
            db_cnt <= {{(DB_CNT_WIDTH-1){1'b0}}, 1'b1};
        else if (db_cnt != {DB_CNT_WIDTH{1'b0}})
            db_cnt <= db_cnt + 1'b1;
    end
end

always @(posedge i_clk or negedge srstn) begin
    if (~srstn)
        start_test_pulse <= 1'b0;
    else if (aclken) begin
        if (db_cnt == DB_CNT_MAX-1)
            start_test_pulse <= 1'b1;
        else
            start_test_pulse <= 1'b0;
    end
end

// -----------------------------------------------------------------------------
ipsxb_fft_frame_gen #(
    .FRAME_GEN_PRINT_EN     (FRAME_GEN_PRINT_EN  ),
    .CLKDIV                 (CLKDIV              ),
    .TEST_FRAME_NUM         (TEST_FRAME_NUM      ),
    .LOGS_FFT_LEN           (LOGS_FFT_LEN        ),
    .INPUT_WIDTH            (INPUT_WIDTH         )
) u_fft_frame_gen (                              
    .i_aclk                 (i_clk               ),
    .i_aresetn              (srstn               ),
    .o_aclken               (aclken              ),  
    .i_axi4s_data_tready    (xn_axi4s_data_tready),    
    .o_axi4s_data_tvalid    (xn_axi4s_data_tvalid),
    .o_axi4s_data_tdata     (xn_axi4s_data_tdata ),
    .o_axi4s_data_tlast     (xn_axi4s_data_tlast ),
    .o_axi4s_cfg_tvalid     (xn_axi4s_cfg_tvalid ),
    .o_axi4s_cfg_tdata      (xn_axi4s_cfg_tdata  ),
    .i_start_test           (start_test_pulse      ),  
    .i_chk_finished         (o_chk_finished      ),
    .i_stat                 (stat                )
);
fft_8192  u_fft_wrapper ( 
    .i_aclk                 (i_clk               ),
  
    .i_aresetn              (srstn               ),

    .i_axi4s_data_tvalid    (xn_axi4s_data_tvalid),
    .i_axi4s_data_tdata     (xn_axi4s_data_tdata ),
    .i_axi4s_data_tlast     (xn_axi4s_data_tlast ),
    .o_axi4s_data_tready    (xn_axi4s_data_tready),
    .i_axi4s_cfg_tvalid     (xn_axi4s_cfg_tvalid ),
    .i_axi4s_cfg_tdata      (xn_axi4s_cfg_tdata  ),
    .o_axi4s_data_tvalid    (xk_axi4s_data_tvalid),
    .o_axi4s_data_tdata     (xk_axi4s_data_tdata ),
    .o_axi4s_data_tlast     (xk_axi4s_data_tlast ),
    .o_axi4s_data_tuser     (xk_axi4s_data_tuser ),
    .o_alm                  (alm                 ),
    .o_stat                 (stat                )
);

ipsxb_fft_frame_chk #(
    .FRAME_CHK_PRINT_EN     (FRAME_CHK_PRINT_EN  ),
    .FRAME_CHK_DATA_EN      (FRAME_CHK_DATA_EN   ),   
    .TEST_FRAME_NUM         (TEST_FRAME_NUM      ),
    .MAX_TIME_OF_FFT        (MAX_TIME_OF_FFT     ),
    .LOGS_FFT_LEN           (LOGS_FFT_LEN        ),
    .OUTPUT_ORDER           (OUTPUT_ORDER        ),
    .INPUT_WIDTH            (INPUT_WIDTH         ),
    .SCALE_MODE             (SCALE_MODE          )    
) u_fft_frame_chk (                              
    .i_aclk                 (i_clk               ),
    .i_aclken               (aclken              ),
    .i_aresetn              (srstn               ),
    .i_start_test           (start_test_pulse    ),
    .i_axi4s_data_tvalid    (xk_axi4s_data_tvalid),
    .i_axi4s_data_tdata     (xk_axi4s_data_tdata ),
    .i_axi4s_data_tlast     (xk_axi4s_data_tlast ),
    .i_axi4s_data_tuser     (xk_axi4s_data_tuser ),
    .o_err                  (err                 ),
    .o_chk_finished         (o_chk_finished      )
);


always @(posedge i_clk or negedge srstn) begin
    if (~srstn)
        all_err_lck <= 1'b0;
    else if (aclken) begin
        if (start_test_pulse)
            all_err_lck <= 1'b0;
        else if (err || alm!=3'b000)
            all_err_lck <= 1'b1;
    end
end

assign o_err = all_err_lck;
  

endmodule
