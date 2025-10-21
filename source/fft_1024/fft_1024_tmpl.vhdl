-- Created by IP Generator (Version 2022.2-SP6.4 build 146967)
-- Instantiation Template
--
-- Insert the following codes into your VHDL file.
--   * Change the_instance_name to your own instance name.
--   * Change the net names in the port map.


COMPONENT fft_1024
  PORT (
    i_axi4s_data_tdata : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
    i_axi4s_data_tvalid : IN STD_LOGIC;
    i_axi4s_data_tlast : IN STD_LOGIC;
    o_axi4s_data_tready : OUT STD_LOGIC;
    i_axi4s_cfg_tdata : IN STD_LOGIC;
    i_axi4s_cfg_tvalid : IN STD_LOGIC;
    i_aclk : IN STD_LOGIC;
    i_aresetn : IN STD_LOGIC;
    o_axi4s_data_tdata : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
    o_axi4s_data_tvalid : OUT STD_LOGIC;
    o_axi4s_data_tlast : OUT STD_LOGIC;
    o_axi4s_data_tuser : OUT STD_LOGIC_VECTOR(23 DOWNTO 0);
    o_alm : OUT STD_LOGIC;
    o_stat : OUT STD_LOGIC
  );
END COMPONENT;


the_instance_name : fft_1024
  PORT MAP (
    i_axi4s_data_tdata => i_axi4s_data_tdata,
    i_axi4s_data_tvalid => i_axi4s_data_tvalid,
    i_axi4s_data_tlast => i_axi4s_data_tlast,
    o_axi4s_data_tready => o_axi4s_data_tready,
    i_axi4s_cfg_tdata => i_axi4s_cfg_tdata,
    i_axi4s_cfg_tvalid => i_axi4s_cfg_tvalid,
    i_aclk => i_aclk,
    i_aresetn => i_aresetn,
    o_axi4s_data_tdata => o_axi4s_data_tdata,
    o_axi4s_data_tvalid => o_axi4s_data_tvalid,
    o_axi4s_data_tlast => o_axi4s_data_tlast,
    o_axi4s_data_tuser => o_axi4s_data_tuser,
    o_alm => o_alm,
    o_stat => o_stat
  );
