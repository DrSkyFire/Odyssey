// Created by IP Generator (Version 2022.2-SP6.4 build 146967)
// Instantiation Template
//
// Insert the following codes into your Verilog file.
//   * Change the_instance_name to your own instance name.
//   * Change the signal names in the port associations


fft_8192 the_instance_name (
  .i_axi4s_data_tdata(i_axi4s_data_tdata),      // input [31:0]
  .i_axi4s_data_tvalid(i_axi4s_data_tvalid),    // input
  .i_axi4s_data_tlast(i_axi4s_data_tlast),      // input
  .o_axi4s_data_tready(o_axi4s_data_tready),    // output
  .i_axi4s_cfg_tdata(i_axi4s_cfg_tdata),        // input
  .i_axi4s_cfg_tvalid(i_axi4s_cfg_tvalid),      // input
  .i_aclk(i_aclk),                              // input
  .i_aresetn(i_aresetn),                        // input
  .o_axi4s_data_tdata(o_axi4s_data_tdata),      // output [31:0]
  .o_axi4s_data_tvalid(o_axi4s_data_tvalid),    // output
  .o_axi4s_data_tlast(o_axi4s_data_tlast),      // output
  .o_axi4s_data_tuser(o_axi4s_data_tuser),      // output [23:0]
  .o_alm(o_alm),                                // output
  .o_stat(o_stat)                               // output
);
