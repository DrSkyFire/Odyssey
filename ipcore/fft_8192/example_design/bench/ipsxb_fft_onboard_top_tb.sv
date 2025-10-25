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

`timescale 1ns / 1ps

module ipsxb_fft_onboard_top_tb ();

GTP_GRS GRS_INST(
    .GRS_N (1'b1)
);

reg clk, rstn;

reg  i_start_test  ;
wire o_err         ;
wire o_chk_finished;

parameter   CLK_P             = 10      ; // 10ns
initial begin
    clk = 1'b1;
    forever 
        #(CLK_P/2) clk = ~clk;
end

ipsxb_fft_onboard_top u_onboard_top ( 
    .i_clk              (clk                ),
    .i_rstn             (rstn               ),
    .i_start_test       (i_start_test       ),      
    .o_err              (o_err              ),
    .o_chk_finished     (o_chk_finished     )
);
   
//------------------------------------------------------
initial begin
    rstn = 1'b0;
    #100
    rstn = 1'b1;
    
    i_start_test = 1'b0;
    #100
    i_start_test = 1'b1;
    #(10000*CLK_P)
    wait(o_chk_finished)
    
    #1000
    
    if (o_err)
        $display("Simulation is failed.");
    else
        $display("Simulation is successful.");
        
    $finish;
end    

endmodule