//=============================================================================
// 文件名: reset_sync.v
// 描述: 异步复位同步释放模块
//=============================================================================

module reset_sync (
    input  wire clk,
    input  wire async_rst_n,        // 异步复位输入
    output reg  sync_rst_n          // 同步复位输出
);

reg rst_n_d1;

always @(posedge clk or negedge async_rst_n) begin
    if (!async_rst_n) begin
        rst_n_d1    <= 1'b0;
        sync_rst_n  <= 1'b0;
    end else begin
        rst_n_d1    <= 1'b1;
        sync_rst_n  <= rst_n_d1;
    end
end

endmodule