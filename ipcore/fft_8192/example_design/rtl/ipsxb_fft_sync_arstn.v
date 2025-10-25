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
//
module ipsxb_fft_sync_arstn (
    input  wire        i_clk                ,
    input  wire        i_arstn_presync      ,
    output reg         o_arstn_synced
);

reg         arstn_presync_ff     ;



always@(posedge i_clk or negedge i_arstn_presync)
begin
    if(i_arstn_presync==1'b0) begin
        arstn_presync_ff <= 1'b0;
        o_arstn_synced   <= 1'b0;
    end
    else begin
        arstn_presync_ff <= 1'b1;
        o_arstn_synced   <= arstn_presync_ff;
    end
end

endmodule
