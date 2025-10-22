//=============================================================================
// 文件名: signal_analyzer_top.v
// 描述: FPGA智能信号分析与测试系统 - 顶层模块
// 功能: 
//   - 双通道ADC同步采集（MS9280，10位，1MSPS）
//   - 1024点FFT频谱分析（双通道时分复用）
//   - 参数测量（频率、幅度、占空比、THD、相位差）
//   - HDMI实时显示（720p@60Hz，频谱+参数）
//   - 自动测试模式（阈值判断+LED指示）
// 作者: DrSkyFire
// 日期: 2025-10-21
// 版本: v2.0 - 时序优化版
//=============================================================================

 module signal_analyzer_top (
    // 系统时钟和复位
    input  wire         sys_clk_50m,        // 板载50MHz时钟
    input  wire         sys_rst_n,          // 系统复位，低有效
    input  wire         sys_clk_27m,        // 板载27MHz时钟（HDMI PLL时钟源）
    
    // ADC接口 (MS9280)
    // 通道1 (AD-IN1)
    input  wire [9:0]   adc_ch1_data,       // 通道1数据 (管脚23,25,26,27,28,29,30,31,32,33)
    output wire         adc_ch1_clk,        // 通道1时钟 (管脚34)
    output wire         adc_ch1_oe,         // 通道1输出使能 (管脚36)
    
    // 通道2 (AD-IN2)
    input  wire [9:0]   adc_ch2_data,       // 通道2数据 (管脚5,7,8,9,10,11,12,13,14,15)
    output wire         adc_ch2_clk,        // 通道2时钟 (管脚16)
    output wire         adc_ch2_oe,         // 通道2输出使能 (管脚18)

    // MS7210 HDMI输出（添加这些端口）
    output wire         hd_tx_pclk,         // MS7210像素时钟
    output wire         hd_tx_vs,           // MS7210场同步
    output wire         hd_tx_hs,           // MS7210行同步
    output wire         hd_tx_de,           // MS7210数据使能
    output wire [23:0]  hd_tx_data,         // MS7210 RGB数据
    
    // MS7210 IIC配置
    output wire         hd_iic_scl,         // IIC时钟
    inout  wire         hd_iic_sda,         // IIC数据
    
    // 用户接口
    input  wire [7:0]   user_button,        // 用户按键
    output wire [7:0]   user_led,           // 用户LED

    // UART接口
    output wire         uart_tx            // UART发送管脚
);

//=============================================================================
// 参数定义
//=============================================================================
localparam FFT_POINTS = 1024;               // FFT点数
localparam ADC_WIDTH  = 10;                  // ADC位宽
localparam FFT_WIDTH  = 10;                 // FFT数据位宽

//=============================================================================
// 时钟和复位信号
//=============================================================================
wire        clk_100m;                       // 100MHz系统时钟
wire        clk_10m;                        // 10MHz中间时钟
wire        clk_adc;                        // 1MHz ADC采样时钟（级联）
wire        clk_fft;                        // 100MHz FFT处理时钟
wire        pll1_lock;                      // PLL1锁定信号
// HDMI相关时钟
wire        pll2_lock;                      // PLL2锁定信号
wire        clk_hdmi_pixel;                 // 148.5MHz HDMI像素时钟 (1080p)
wire        ms7210_init_over;                  // MS7210配置完成标志
//全局PLL锁定信号
wire        pll_lock;
assign      pll_lock = pll1_lock & pll2_lock;
// 复位信号
wire        rst_n_sync;                     // 同步后的全局复位
reg         wr_rst_n;                       // FIFO写端口复位
reg         rd_rst_n;                       // FIFO读端口复位
reg  [3:0]  rd_rst_delay_cnt;               // 读复位延迟计数器
wire        rst_n;                          // 其他模块使用的复位

//=============================================================================
// ADC采集相关信号
//=============================================================================
wire [15:0] selected_adc_data;               // 选择的ADC数据（16位扩展）
wire [9:0]  ch1_data_sync;                  // 同步后的通道1数据
wire [9:0]  ch2_data_sync;                  // 同步后的通道2数据
wire        dual_data_valid;                // 两个通道的数据同步有效标志
reg         channel_sel;                    // 0 = 通道0, 1 = 通道1
wire        btn_ch_sel;                     // 通道选择按键
wire [7:0]  adc_data_sync;
wire        adc_data_valid;
wire [15:0] adc_data_ext;

//=============================================================================
// FIFO相关信号 - 双通道
//=============================================================================
// 通道1 FIFO
wire        ch1_fifo_wr_en;                 // 通道1 FIFO写使能
wire [15:0] ch1_fifo_din;                   // 通道1 FIFO输入数据
wire        ch1_fifo_rd_en;                 // 通道1 FIFO读使能
wire [15:0] ch1_fifo_dout;                  // 通道1 FIFO输出数据
wire        ch1_fifo_full;                  // 通道1 FIFO满标志
wire        ch1_fifo_empty;                 // 通道1 FIFO空标志
wire [11:0] ch1_fifo_rd_water_level;        // 通道1 FIFO读水位
wire [11:0] ch1_fifo_wr_water_level;        // 通道1 FIFO写水位

// 通道2 FIFO
wire        ch2_fifo_wr_en;                 // 通道2 FIFO写使能
wire [15:0] ch2_fifo_din;                   // 通道2 FIFO输入数据
wire        ch2_fifo_rd_en;                 // 通道2 FIFO读使能
wire [15:0] ch2_fifo_dout;                  // 通道2 FIFO输出数据
wire        ch2_fifo_full;                  // 通道2 FIFO满标志
wire        ch2_fifo_empty;                 // 通道2 FIFO空标志
wire [11:0] ch2_fifo_rd_water_level;        // 通道2 FIFO读水位
wire [11:0] ch2_fifo_wr_water_level;        // 通道2 FIFO写水位

//=============================================================================
// FFT相关信号
//=============================================================================
wire        fft_start;                      // FFT启动信号
wire [31:0] fft_din;                        // FFT输入 {虚部16bit, 实部16bit}
wire        fft_din_valid;                  // FFT输入有效
wire        fft_din_last;                   // FFT输入最后一个数据
wire        fft_din_ready;                  // FFT输入准备好

wire [31:0] fft_dout;                       // FFT输出 {虚部16bit, 实部16bit}
wire        fft_dout_valid;                 // FFT输出有效
wire        fft_dout_last;                  // FFT输出最后一个数据
wire        fft_dout_ready;                 // FFT输出准备好
wire [15:0] fft_tuser;

//=============================================================================
// 频谱数据处理信号 - 双通道
//=============================================================================
// 通道1频谱
wire [15:0] ch1_spectrum_magnitude;         // 通道1频谱幅度
wire [9:0]  ch1_spectrum_wr_addr;           // 通道1频谱写地址
wire        ch1_spectrum_valid;             // 通道1频谱数据有效

// 通道2频谱
wire [15:0] ch2_spectrum_magnitude;         // 通道2频谱幅度
wire [9:0]  ch2_spectrum_wr_addr;           // 通道2频谱写地址
wire        ch2_spectrum_valid;             // 通道2频谱数据有效

// 双通道FFT控制状态
wire        ch1_fft_busy;                   // 通道1 FFT忙
wire        ch2_fft_busy;                   // 通道2 FFT忙
wire        current_fft_channel;            // 当前FFT处理通道

//=============================================================================
// 显示相关信号 - 双通道
//=============================================================================
wire [23:0] hdmi_rgb;                       // HDMI RGB数据
wire        hdmi_de;                        // HDMI数据使能
wire        hdmi_hs;                        // HDMI行同步
wire        hdmi_vs;                        // HDMI场同步

// 输出至MS7210前增加一级寄存器，力求将寄存器放置在I/O逻辑中
(* iob = "true" *) reg [23:0] hdmi_rgb_q;
(* iob = "true" *) reg        hdmi_de_q;
(* iob = "true" *) reg        hdmi_hs_q;
(* iob = "true" *) reg        hdmi_vs_q;
wire [15:0] spectrum_rd_data;               // 从RAM读出的频谱数据（经过通道选择）
wire [9:0]  spectrum_rd_addr;               // 频谱读地址
reg [7:0]   user_led_reg;                   // 用户LED寄存器

// 通道1频谱RAM
wire [15:0] ch1_spectrum_rd_data;           // 通道1频谱读数据
// 通道2频谱RAM
wire [15:0] ch2_spectrum_rd_data;           // 通道2频谱读数据

// 显示通道选择
reg         display_channel;                // 0=显示通道1, 1=显示通道2
wire        btn_display_ch_sel;             // 显示通道切换按键

//=============================================================================
// 控制信号
//=============================================================================
reg  [1:0]  work_mode;                      // 工作模式: 0-时域 1-频域 2-参数测量
wire        btn_mode;                       // 模式切换按键
wire        btn_start;                      // 启动按键
wire        btn_stop;                       // 停止按键
reg         run_flag;                       // 运行标志

//=============================================================================
// 信号参数测量
//=============================================================================
wire [15:0] signal_freq;                    // 信号频率
wire [15:0] signal_amplitude;               // 信号幅度
wire [15:0] signal_duty;                    // 占空比
wire [15:0] signal_thd;                     // 总谐波失真

//=============================================================================
// 相位差测量信号
//=============================================================================
wire [15:0] phase_difference;               // 相位差 (0-3599 = 0-359.9度)
wire        phase_diff_valid;               // 相位差有效

// FFT基波频点数据提取（用于相位差计算）
reg signed [15:0] ch1_fundamental_re;       // 通道1基波实部
reg signed [15:0] ch1_fundamental_im;       // 通道1基波虚部
reg         ch1_fundamental_valid;          // 通道1基波有效

reg signed [15:0] ch2_fundamental_re;       // 通道2基波实部
reg signed [15:0] ch2_fundamental_im;       // 通道2基波虚部
reg         ch2_fundamental_valid;          // 通道2基波有效

//=============================================================================
// 双口RAM相关信号 - 双通道
//=============================================================================
// 通道1乒乓缓存控制信号
reg         ch1_buffer_sel;                     // 通道1缓存选择
reg         ch1_buffer_sel_sync1, ch1_buffer_sel_sync2;  // 跨时钟域同步

// 通道1 RAM0信号
wire        ch1_ram0_we;
wire [9:0]  ch1_ram0_wr_addr;
wire [15:0] ch1_ram0_wr_data;
wire [9:0]  ch1_ram0_rd_addr;
wire [15:0] ch1_ram0_rd_data;

// 通道1 RAM1信号
wire        ch1_ram1_we;
wire [9:0]  ch1_ram1_wr_addr;
wire [15:0] ch1_ram1_wr_data;
wire [9:0]  ch1_ram1_rd_addr;
wire [15:0] ch1_ram1_rd_data;

// 通道2乒乓缓存控制信号
reg         ch2_buffer_sel;                     // 通道2缓存选择
reg         ch2_buffer_sel_sync1, ch2_buffer_sel_sync2;  // 跨时钟域同步

// 通道2 RAM0信号
wire        ch2_ram0_we;
wire [9:0]  ch2_ram0_wr_addr;
wire [15:0] ch2_ram0_wr_data;
wire [9:0]  ch2_ram0_rd_addr;
wire [15:0] ch2_ram0_rd_data;

// 通道2 RAM1信号
wire        ch2_ram1_we;
wire [9:0]  ch2_ram1_wr_addr;
wire [15:0] ch2_ram1_wr_data;
wire [9:0]  ch2_ram1_rd_addr;
wire [15:0] ch2_ram1_rd_data;
wire [15:0] ram0_rd_data;

// RAM1信号
wire        ram1_we;
wire [9:0]  ram1_wr_addr;
wire [15:0] ram1_wr_data;
wire [9:0]  ram1_rd_addr;
wire [15:0] ram1_rd_data;

//=============================================================================
// 内部测试信号发生器
//=============================================================================
reg [15:0] test_signal_gen;
reg [9:0]  test_counter;
reg test_mode;
wire btn_test_mode;

//=============================================================================
// 自动测试模块信号
//=============================================================================
wire [7:0] auto_test_result;        // 自动测试结果LED
reg        auto_test_enable;        // 自动测试使能
wire       btn_auto_test;           // 自动测试按键

//=============================================================================
// UART发送模块信号
//=============================================================================
wire        uart_busy;
reg  [7:0]  uart_data_to_send;
reg         uart_send_trigger;
reg  [7:0]  send_state;

// 调试数据捕获（原始信号，不同时钟域）
reg  [15:0] debug_adc_ch1_sample;      // ADC通道1采样值 (clk_adc域)
reg  [15:0] debug_adc_ch2_sample;      // ADC通道2采样值 (clk_adc域)
reg  [15:0] debug_fifo_wr_count;       // FIFO写入计数 (clk_adc域)
reg  [15:0] debug_fft_out_count;       // FFT输出计数 (clk_fft域)
reg  [15:0] debug_spectrum_addr_last;  // 最后的频谱地址 (clk_fft域)
reg         debug_data_valid;          // ADC数据有效标志 (clk_adc域)
reg         debug_fft_done;            // FFT完成标志 (clk_fft域)

// 同步到100MHz域的调试信号（用于UART发送）
reg  [15:0] debug_adc_ch1_sample_sync;
reg  [15:0] debug_adc_ch2_sample_sync;
reg  [15:0] debug_fifo_wr_count_sync;
reg  [15:0] debug_fft_out_count_sync;
reg  [15:0] debug_spectrum_addr_last_sync;
reg         debug_data_valid_sync;
reg         debug_fft_done_sync;

//=============================================================================
// 1. PLL1 - 系统时钟管理（50MHz输入）
//=============================================================================
pll_sys u_pll_sys (
    .clkin1         (sys_clk_50m),          // 50MHz输入
    .pll_lock       (pll1_lock),            // PLL1锁定
    .clkout0        (clk_100m),             // 100MHz系统时钟
    .clkout1        (clk_10m),              // 10MHz中间时钟
    .clkout2        (clk_adc)               // 1MHz ADC时钟（级联）
);

// PLL1配置说明：
// VCO = 1000MHz (50MHz × 20 / 1)
// CLKOUT0 = 100MHz (1000MHz / 10)
// CLKOUT1 = 10MHz (1000MHz / 100)
// CLKOUT2 = 1MHz (级联CLKOUT1 / 10)

//=============================================================================
// 2. PLL2 - HDMI时钟管理（27MHz输入）
//=============================================================================
pll_hdmi u_pll_hdmi (
    .clkin1         (sys_clk_27m),          // 27MHz输入
    .pll_lock       (pll2_lock),            // PLL2锁定
    .clkout0        (clk_hdmi_pixel)        // 148.5MHz HDMI像素时钟 (1080p)
);

// PLL2配置说明：
// VCO = 1188MHz (27MHz × 44 / 1)
// CLKOUT0 = 148.5MHz (1188MHz / 8) - 1080p@60Hz像素时钟

assign clk_fft = clk_100m;                  // FFT使用100MHz时钟

//=============================================================================
// 2. 复位同步和管理
//=============================================================================

// 2.1 全局复位同步
reset_sync u_reset_sync (
    .clk            (clk_100m),
    .async_rst_n    (sys_rst_n & pll_lock),
    .sync_rst_n     (rst_n_sync)
);

// 2.2 FIFO写端口复位 - 先释放
always @(posedge clk_adc or negedge rst_n_sync) begin
    if (!rst_n_sync)
        wr_rst_n <= 1'b0;
    else
        wr_rst_n <= 1'b1;
end

// 2.3 FIFO读端口复位 - 延迟释放（晚于写端口15个时钟周期）
always @(posedge clk_fft or negedge rst_n_sync) begin
    if (!rst_n_sync) begin
        rd_rst_delay_cnt <= 4'd0;
        rd_rst_n <= 1'b0;
    end else begin
        if (rd_rst_delay_cnt < 4'd15)
            rd_rst_delay_cnt <= rd_rst_delay_cnt + 1'b1;
        else
            rd_rst_n <= 1'b1;
    end
end

// 2.4 其他模块使用统一的复位信号
assign rst_n = rst_n_sync;

//=============================================================================
// 3. ADC数据采集模块
//=============================================================================
assign adc_oe = 1'b1; // 直接使能ADC数据输出
assign adc_data_sync = channel_sel ? ch2_data_sync[9:2] : ch1_data_sync[9:2];
assign adc_data_valid = dual_data_valid;
// ADC数据扩展到16位 (高8位为数据，低8位补0以提高精度)
assign selected_adc_data = channel_sel ? {ch1_data_sync, 6'h00} : {ch2_data_sync, 6'h00};
assign adc_data_ext = selected_adc_data;

adc_capture_dual u_adc_dual (
    .clk                (clk_adc),
    .rst_n              (rst_n),
    
    // 通道1接口
    .adc_ch1_in         (adc_ch1_data),
    .adc_ch1_clk_out    (adc_ch1_clk),
    .adc_ch1_oe_out     (adc_ch1_oe),
    
    // 通道2接口
    .adc_ch2_in         (adc_ch2_data),
    .adc_ch2_clk_out    (adc_ch2_clk),
    .adc_ch2_oe_out     (adc_ch2_oe),
    
    // 数据输出
    .ch1_data_out       (ch1_data_sync),
    .ch2_data_out       (ch2_data_sync),
    .data_valid         (dual_data_valid),
    
    .enable             (run_flag)
);

//=============================================================================
// 4. 双通道数据缓冲FIFO (跨时钟域：ADC 1MHz → FFT 100MHz)
//=============================================================================
// ✓ 双通道独立FIFO，支持同步采集

// 通道1数据源选择（支持测试信号）
wire [15:0] ch1_fifo_data_source;
assign ch1_fifo_data_source = test_mode ? test_signal_gen : {ch1_data_sync, 6'h00};
assign ch1_fifo_wr_en = test_mode ? 1'b1 : (dual_data_valid && run_flag);
assign ch1_fifo_din = ch1_fifo_data_source;

// 通道2数据源（正常ADC数据）
assign ch2_fifo_wr_en = dual_data_valid && run_flag;
assign ch2_fifo_din = {ch2_data_sync, 6'h00};

// 通道1 FIFO
fifo_async #(
    .DATA_WIDTH     (16),
    .FIFO_DEPTH     (2048)
) u_ch1_fifo (
    // 写端口 (ADC时钟域 1MHz)
    .wr_clk         (clk_adc),
    .wr_rst_n       (wr_rst_n),
    .wr_en          (ch1_fifo_wr_en),
    .wr_data        (ch1_fifo_din),
    .full           (ch1_fifo_full),
    .almost_full    (),
    .wr_water_level (ch1_fifo_wr_water_level),
    
    // 读端口 (FFT时钟域 100MHz)
    .rd_clk         (clk_fft),
    .rd_rst_n       (rd_rst_n),
    .rd_en          (ch1_fifo_rd_en),
    .rd_data        (ch1_fifo_dout),
    .empty          (ch1_fifo_empty),
    .almost_empty   (),
    .rd_water_level (ch1_fifo_rd_water_level)
);

// 通道2 FIFO
fifo_async #(
    .DATA_WIDTH     (16),
    .FIFO_DEPTH     (2048)
) u_ch2_fifo (
    // 写端口 (ADC时钟域 1MHz)
    .wr_clk         (clk_adc),
    .wr_rst_n       (wr_rst_n),
    .wr_en          (ch2_fifo_wr_en),
    .wr_data        (ch2_fifo_din),
    .full           (ch2_fifo_full),
    .almost_full    (),
    .wr_water_level (ch2_fifo_wr_water_level),
    
    // 读端口 (FFT时钟域 100MHz)
    .rd_clk         (clk_fft),
    .rd_rst_n       (rd_rst_n),
    .rd_en          (ch2_fifo_rd_en),
    .rd_data        (ch2_fifo_dout),
    .empty          (ch2_fifo_empty),
    .almost_empty   (),
    .rd_water_level (ch2_fifo_rd_water_level)
);

//=============================================================================
// 5. 双通道时分复用FFT控制模块
//=============================================================================
dual_channel_fft_controller #(
    .FFT_POINTS     (FFT_POINTS),
    .DATA_WIDTH     (16)
) u_dual_fft_ctrl (
    .clk                    (clk_fft),
    .rst_n                  (rst_n),
    
    // 通道1 FIFO接口
    .ch1_fifo_empty         (ch1_fifo_empty),
    .ch1_fifo_rd_en         (ch1_fifo_rd_en),
    .ch1_fifo_dout          (ch1_fifo_dout),
    .ch1_fifo_rd_water_level(ch1_fifo_rd_water_level),
    
    // 通道2 FIFO接口
    .ch2_fifo_empty         (ch2_fifo_empty),
    .ch2_fifo_rd_en         (ch2_fifo_rd_en),
    .ch2_fifo_dout          (ch2_fifo_dout),
    .ch2_fifo_rd_water_level(ch2_fifo_rd_water_level),
    
    // FFT IP接口
    .fft_din                (fft_din),
    .fft_din_valid          (fft_din_valid),
    .fft_din_last           (fft_din_last),
    .fft_din_ready          (fft_din_ready),
    .fft_dout               (fft_dout),
    .fft_dout_valid         (fft_dout_valid),
    .fft_dout_last          (fft_dout_last),
    
    // 频谱输出 - 通道1
    .ch1_spectrum_data      (ch1_spectrum_magnitude),
    .ch1_spectrum_addr      (ch1_spectrum_wr_addr),
    .ch1_spectrum_valid     (ch1_spectrum_valid),
    
    // 频谱输出 - 通道2
    .ch2_spectrum_data      (ch2_spectrum_magnitude),
    .ch2_spectrum_addr      (ch2_spectrum_wr_addr),
    .ch2_spectrum_valid     (ch2_spectrum_valid),
    
    // 控制信号
    .fft_enable             (fft_start),
    .work_mode              (work_mode),
    
    // 状态输出
    .ch1_fft_busy           (ch1_fft_busy),
    .ch2_fft_busy           (ch2_fft_busy),
    .current_channel        (current_fft_channel)
);

//=============================================================================
// 5.5 FFT配置信号生成（参考官方例程）
//=============================================================================
reg fft_cfg_valid;
reg fft_start_d1;

// 检测fft_start上升沿
always @(posedge clk_fft or negedge rst_n) begin
    if (!rst_n)
        fft_start_d1 <= 1'b0;
    else
        fft_start_d1 <= fft_start;
end

// 在fft_start拉高时发送一个配置脉冲
always @(posedge clk_fft or negedge rst_n) begin
    if (!rst_n)
        fft_cfg_valid <= 1'b0;
    else if (fft_cfg_valid)
        fft_cfg_valid <= 1'b0;  // 保持1个时钟周期
    else if (fft_start && !fft_start_d1)
        fft_cfg_valid <= 1'b1;  // 上升沿触发
end

//=============================================================================
// 6. FFT IP核实例化
//=============================================================================
fft_1024 u_fft_1024 (
    // 时钟和复位
    .i_aclk                 (clk_fft),              // 100MHz时钟
    .i_aresetn              (rst_n),                // 复位，低有效
    
    // 输入数据流 (AXI4-Stream)
    .i_axi4s_data_tvalid    (fft_din_valid),        // 输入数据有效
    .o_axi4s_data_tready    (fft_din_ready),        // FFT准备接收
    .i_axi4s_data_tlast     (fft_din_last),         // 最后一个输入数据
    .i_axi4s_data_tdata     (fft_din),              // 32位输入 {虚部[31:16], 实部[15:0]}
    
    // 配置接口（参考官方例程）
    .i_axi4s_cfg_tdata      (1'b1),                 // 1=FFT, 0=IFFT
    .i_axi4s_cfg_tvalid     (fft_cfg_valid),        // ✓ 修复：使用脉冲信号
    
    // 输出数据流 (AXI4-Stream)
    .o_axi4s_data_tvalid    (fft_dout_valid),       // 输出数据有效
    .o_axi4s_data_tlast     (fft_dout_last),        // 最后一个输出数据
    .o_axi4s_data_tdata     (fft_dout),             // 32位输出 {虚部[31:16], 实部[15:0]}
    .o_axi4s_data_tuser     (fft_tuser),            // 输出信息（暂不使用）
    
    // 状态和告警
    .o_alm                  (),                     // 告警信号（可选）
    .o_stat                 ()                      // 状态信号（可选）
);

assign fft_dout_ready = 1'b1;  // 后级始终准备好接收

//=============================================================================
// 6.5 基波频点数据提取（用于相位差计算）
// 假设基波在第10个频点（可根据实际信号频率调整）
//=============================================================================
reg [9:0] fft_out_cnt;  // FFT输出计数器

always @(posedge clk_fft or negedge rst_n) begin
    if (!rst_n) begin
        fft_out_cnt <= 10'd0;
    end else if (fft_dout_valid) begin
        if (fft_dout_last)
            fft_out_cnt <= 10'd0;
        else
            fft_out_cnt <= fft_out_cnt + 1'b1;
    end
end

// 提取通道1基波数据（第10个频点）
always @(posedge clk_fft or negedge rst_n) begin
    if (!rst_n) begin
        ch1_fundamental_re <= 16'd0;
        ch1_fundamental_im <= 16'd0;
        ch1_fundamental_valid <= 1'b0;
    end else if (fft_dout_valid && fft_out_cnt == 10'd10 && current_fft_channel == 1'b0) begin
        ch1_fundamental_re <= fft_dout[15:0];   // 实部
        ch1_fundamental_im <= fft_dout[31:16];  // 虚部
        ch1_fundamental_valid <= 1'b1;
    end else begin
        ch1_fundamental_valid <= 1'b0;
    end
end

// 提取通道2基波数据
always @(posedge clk_fft or negedge rst_n) begin
    if (!rst_n) begin
        ch2_fundamental_re <= 16'd0;
        ch2_fundamental_im <= 16'd0;
        ch2_fundamental_valid <= 1'b0;
    end else if (fft_dout_valid && fft_out_cnt == 10'd10 && current_fft_channel == 1'b1) begin
        ch2_fundamental_re <= fft_dout[15:0];
        ch2_fundamental_im <= fft_dout[31:16];
        ch2_fundamental_valid <= 1'b1;
    end else begin
        ch2_fundamental_valid <= 1'b0;
    end
end

//=============================================================================
// 7. 频谱幅度计算模块
//=============================================================================
spectrum_magnitude_calc u_spectrum_calc (
    .clk            (clk_fft),
    .rst_n          (rst_n),
    
    // FFT输出
    .fft_dout       (fft_dout),
    .fft_valid      (fft_dout_valid),
    .fft_last       (fft_dout_last),
    .fft_ready      (fft_dout_ready),
    
    // 幅度输出
    .magnitude      (spectrum_magnitude),
    .magnitude_addr (spectrum_wr_addr),
    .magnitude_valid(spectrum_valid)
);

//=============================================================================
// 8. 频谱数据存储 (双口RAM)
//=============================================================================
// dpram_1024x16 u_spectrum_ram (
//     // 写端口 (FFT时钟域)
//     .clka           (clk_fft),              // 100MHz
//     // .wea            (spectrum_valid),       // 频谱数据有效时写入
//     .wea            (1'b0),                   // 频谱数据有效时写入
//     .addra          (spectrum_wr_addr),        // 频谱地址 (0~1023)
//     .dina           (spectrum_magnitude),   // 频谱幅度值
    
//     // 读端口 (显示时钟域)
//     .clkb           (clk_hdmi_pixel),       // 148.5MHz
//     .addrb          (spectrum_rd_addr),     // 显示模块提供的读地址
//     .doutb          (spectrum_rd_data)      // 读出的频谱数据
// );
//=============================================================================
// 8. 双通道频谱数据存储 (双口RAM - 乒乓缓存)
//=============================================================================
//--- 通道1乒乓缓存切换逻辑（在FFT时钟域）---
always @(posedge clk_fft or negedge rst_n) begin
    if (!rst_n)
        ch1_buffer_sel <= 1'b0;
    else if (ch1_spectrum_valid && ch1_spectrum_wr_addr == 10'd1023)
        ch1_buffer_sel <= ~ch1_buffer_sel;
end

//--- 通道2乒乓缓存切换逻辑---
always @(posedge clk_fft or negedge rst_n) begin
    if (!rst_n)
        ch2_buffer_sel <= 1'b0;
    else if (ch2_spectrum_valid && ch2_spectrum_wr_addr == 10'd1023)
        ch2_buffer_sel <= ~ch2_buffer_sel;
end

//--- 通道1缓存选择信号同步到HDMI时钟域---
always @(posedge clk_hdmi_pixel or negedge rst_n) begin
    if (!rst_n) begin
        ch1_buffer_sel_sync1 <= 1'b0;
        ch1_buffer_sel_sync2 <= 1'b0;
    end else begin
        ch1_buffer_sel_sync1 <= ch1_buffer_sel;
        ch1_buffer_sel_sync2 <= ch1_buffer_sel_sync1;
    end
end

//--- 通道2缓存选择信号同步到HDMI时钟域---
always @(posedge clk_hdmi_pixel or negedge rst_n) begin
    if (!rst_n) begin
        ch2_buffer_sel_sync1 <= 1'b0;
        ch2_buffer_sel_sync2 <= 1'b0;
    end else begin
        ch2_buffer_sel_sync1 <= ch2_buffer_sel;
        ch2_buffer_sel_sync2 <= ch2_buffer_sel_sync1;
    end
end

//--- 通道1写端口选择---
assign ch1_ram0_we      = ch1_spectrum_valid && (ch1_buffer_sel == 1'b0);
assign ch1_ram0_wr_addr = ch1_spectrum_wr_addr;
assign ch1_ram0_wr_data = ch1_spectrum_magnitude;

assign ch1_ram1_we      = ch1_spectrum_valid && (ch1_buffer_sel == 1'b1);
assign ch1_ram1_wr_addr = ch1_spectrum_wr_addr;
assign ch1_ram1_wr_data = ch1_spectrum_magnitude;

//--- 通道2写端口选择---
assign ch2_ram0_we      = ch2_spectrum_valid && (ch2_buffer_sel == 1'b0);
assign ch2_ram0_wr_addr = ch2_spectrum_wr_addr;
assign ch2_ram0_wr_data = ch2_spectrum_magnitude;

assign ch2_ram1_we      = ch2_spectrum_valid && (ch2_buffer_sel == 1'b1);
assign ch2_ram1_wr_addr = ch2_spectrum_wr_addr;
assign ch2_ram1_wr_data = ch2_spectrum_magnitude;

//--- 通道1读端口选择---
assign ch1_ram0_rd_addr = spectrum_rd_addr;
assign ch1_ram1_rd_addr = spectrum_rd_addr;
assign ch1_spectrum_rd_data = ch1_buffer_sel_sync2 ? ch1_ram0_rd_data : ch1_ram1_rd_data;

//--- 通道2读端口选择---
assign ch2_ram0_rd_addr = spectrum_rd_addr;
assign ch2_ram1_rd_addr = spectrum_rd_addr;
assign ch2_spectrum_rd_data = ch2_buffer_sel_sync2 ? ch2_ram0_rd_data : ch2_ram1_rd_data;

//--- 显示通道选择---
assign spectrum_rd_data = display_channel ? ch2_spectrum_rd_data : ch1_spectrum_rd_data;

//=============================================================================
// 通道1 RAM0实例化
//=============================================================================
dpram_1024x16 u_ch1_spectrum_ram0 (
    .clka   (clk_fft),
    .wea    (ch1_ram0_we),
    .addra  (ch1_ram0_wr_addr),
    .dina   (ch1_ram0_wr_data),
    .clkb   (clk_hdmi_pixel),
    .addrb  (ch1_ram0_rd_addr),
    .doutb  (ch1_ram0_rd_data)
);

//=============================================================================
// 通道1 RAM1实例化
//=============================================================================
dpram_1024x16 u_ch1_spectrum_ram1 (
    .clka   (clk_fft),
    .wea    (ch1_ram1_we),
    .addra  (ch1_ram1_wr_addr),
    .dina   (ch1_ram1_wr_data),
    .clkb   (clk_hdmi_pixel),
    .addrb  (ch1_ram1_rd_addr),
    .doutb  (ch1_ram1_rd_data)
);

//=============================================================================
// 通道2 RAM0实例化
//=============================================================================
dpram_1024x16 u_ch2_spectrum_ram0 (
    .clka   (clk_fft),
    .wea    (ch2_ram0_we),
    .addra  (ch2_ram0_wr_addr),
    .dina   (ch2_ram0_wr_data),
    .clkb   (clk_hdmi_pixel),
    .addrb  (ch2_ram0_rd_addr),
    .doutb  (ch2_ram0_rd_data)
);

//=============================================================================
// 通道2 RAM1实例化
//=============================================================================
dpram_1024x16 u_ch2_spectrum_ram1 (
    .clka   (clk_fft),
    .wea    (ch2_ram1_we),
    .addra  (ch2_ram1_wr_addr),
    .dina   (ch2_ram1_wr_data),
    .clkb   (clk_hdmi_pixel),
    .addrb  (ch2_ram1_rd_addr),
    .doutb  (ch2_ram1_rd_data)
);

//=============================================================================
// 9. 信号参数测量模块（暂使用通道1数据）
//=============================================================================
signal_parameter_measure u_param_measure (
    .clk            (clk_100m),
    .rst_n          (rst_n),
    
    // 时域数据输入
    .sample_clk     (clk_adc),
    .sample_data    (adc_data_sync),
    .sample_valid   (adc_data_valid),
    
    // 频域数据输入（使用通道1）
    .spectrum_data  (ch1_spectrum_magnitude),
    .spectrum_addr  (ch1_spectrum_wr_addr),
    .spectrum_valid (ch1_spectrum_valid),
    
    // 参数输出
    .freq_out       (signal_freq),
    .amplitude_out  (signal_amplitude),
    .duty_out       (signal_duty),
    .thd_out        (signal_thd),
    
    // 控制
    .measure_en     (work_mode == 2'd2)
);

//=============================================================================
// 9.5 相位差计算模块
//=============================================================================
phase_diff_calc u_phase_diff (
    .clk            (clk_fft),
    .rst_n          (rst_n),
    
    // 通道1基波数据
    .ch1_re         (ch1_fundamental_re),
    .ch1_im         (ch1_fundamental_im),
    .ch1_valid      (ch1_fundamental_valid),
    
    // 通道2基波数据
    .ch2_re         (ch2_fundamental_re),
    .ch2_im         (ch2_fundamental_im),
    .ch2_valid      (ch2_fundamental_valid),
    
    // 相位差输出
    .phase_diff     (phase_difference),
    .phase_valid    (phase_diff_valid),
    
    // 控制
    .enable         (work_mode == 2'd1)  // 频域模式下使能
);

//=============================================================================
// 9.6 自动测试模块
//=============================================================================
auto_test u_auto_test (
    .clk            (clk_100m),
    .rst_n          (rst_n),
    
    // 测试控制
    .test_enable    (auto_test_enable),
    
    // 参数输入
    .freq           (signal_freq),
    .amplitude      (signal_amplitude),
    .duty           (signal_duty),
    .thd            (signal_thd),
    .phase_diff     (phase_difference),
    .param_valid    (param_valid),
    
    // 测试结果输出
    .test_result    (auto_test_result)
);

//=============================================================================
// 10. HDMI显示控制模块
//=============================================================================
hdmi_display_ctrl u_hdmi_ctrl (
    .clk_pixel          (clk_hdmi_pixel),       // 148.5MHz
    .rst_n              (rst_n),
    
    // 显示数据输入
    .spectrum_data      (spectrum_rd_data),
    .spectrum_addr      (spectrum_rd_addr),
    .time_data          (adc_data_ext),
    
    // 参数显示
    .freq               (signal_freq),
    .amplitude          (signal_amplitude),
    .duty               (signal_duty),
    .thd                (signal_thd),
    .phase_diff         (phase_difference),     // 相位差
    .current_channel    (display_channel),      // 当前显示通道
    
    // 控制
    .work_mode          (work_mode),
    
    // HDMI时序输出
    .rgb_out            (hdmi_rgb),
    .de_out             (hdmi_de),
    .hs_out             (hdmi_hs),
    .vs_out             (hdmi_vs)
);

//=============================================================================
// 11. HDMI物理层输出 (直接连接到MS7210)
//=============================================================================
// MS7210使用并行RGB接口，不需要TMDS编码
// hdmi_tx模块在这里实际上不执行任何操作，仅作为占位
// 实际的HDMI数据直接通过hd_tx_*端口输出
hdmi_tx u_hdmi_tx (
    .clk_pixel      (clk_hdmi_pixel),       // 148.5MHz
    .rst_n          (rst_n),
    
    // 视频输入
    .rgb            (hdmi_rgb),
    .de             (hdmi_de),
    .hs             (hdmi_hs),
    .vs             (hdmi_vs),
    // HDMI物理输出 (未使用，MS7210使用并行接口)
    .tmds_clk_p     ()                      // 悬空，不连接
);

//=============================================================================
// 12. 按键消抖和控制逻辑
//=============================================================================
key_debounce u_key_mode (
    .clk            (clk_100m),
    .rst_n          (rst_n),
    .key_in         (user_button[0]),
    .key_pulse      (btn_mode)
);

key_debounce u_key_start (
    .clk            (clk_100m),
    .rst_n          (rst_n),
    .key_in         (user_button[1]),
    .key_pulse      (btn_start)
);

key_debounce u_key_stop (
    .clk            (clk_100m),
    .rst_n          (rst_n),
    .key_in         (user_button[2]),
    .key_pulse      (btn_stop)
);

// 通道选择（用于ADC采集的通道选择，已不需要用于FFT）
key_debounce u_key_ch_sel (
    .clk            (clk_100m),
    .rst_n          (rst_n),
    .key_in         (user_button[3]),
    .key_pulse      (btn_ch_sel)
);

// ✓ 新增：显示通道切换按键
key_debounce u_key_display_ch (
    .clk            (clk_100m),
    .rst_n          (rst_n),
    .key_in         (user_button[6]),       // 使用按键6切换显示通道
    .key_pulse      (btn_display_ch_sel)
);

// 显示通道切换逻辑
always @(posedge clk_100m or negedge rst_n) begin
    if (!rst_n)
        display_channel <= 1'b0;            // 默认显示通道1
    else if (btn_display_ch_sel)
        display_channel <= ~display_channel;
end

// 工作模式切换（默认频域模式便于测试）
always @(posedge clk_100m or negedge rst_n) begin
    if (!rst_n)
        work_mode <= 2'd1;  // ✓ 默认频域模式
    else if (btn_mode) begin
        if (work_mode == 2'd2)
            work_mode <= 2'd0;
        else
            work_mode <= work_mode + 1'b1;
    end
end

// 运行控制
always @(posedge clk_100m or negedge rst_n) begin
    if (!rst_n)
        run_flag <= 1'b0;
    else if (btn_start)
        run_flag <= 1'b1;
    else if (btn_stop)
        run_flag <= 1'b0;
end

// 测试模式切换
key_debounce u_key_test (
    .clk        (clk_100m),
    .rst_n      (rst_n),
    .key_in     (user_button[7]),
    .key_pulse  (btn_test_mode)
);

// 自动测试按键
key_debounce u_key_auto_test (
    .clk        (clk_100m),
    .rst_n      (rst_n),
    .key_in     (user_button[5]),
    .key_pulse  (btn_auto_test)
);

// FFT启动信号
assign fft_start = run_flag && (work_mode == 2'd1);

//=============================================================================
// 13. LED状态指示（双通道状态 / 自动测试结果切换）
//=============================================================================
// 自动测试使能控制
always @(posedge clk_100m or negedge rst_n) begin
    if (!rst_n)
        auto_test_enable <= 1'b0;
    else if (btn_auto_test)
        auto_test_enable <= ~auto_test_enable;
end

// LED输出选择：自动测试模式显示测试结果，否则显示系统状态
assign user_led = auto_test_enable ? auto_test_result : user_led_reg;

always @(posedge clk_100m or negedge rst_n) begin
    if (!rst_n)
        user_led_reg <= 8'h00;
    else begin
        user_led_reg[0] <= run_flag;                // 运行状态
        user_led_reg[1] <= ch1_fft_busy;            // 通道1 FFT忙
        user_led_reg[2] <= ch2_fft_busy;            // 通道2 FFT忙
        user_led_reg[3] <= current_fft_channel;     // 当前处理的通道
        user_led_reg[4] <= display_channel;         // 当前显示的通道
        user_led_reg[5] <= test_mode;               // 测试模式
        user_led_reg[6] <= pll1_lock;               // PLL1锁定
        user_led_reg[7] <= pll2_lock;               // PLL2锁定
    end
end

//=============================================================================
// 改进的测试信号发生器 - 多频混合信号
//=============================================================================
// 在clk_adc (1MHz)时钟域生成测试信号
// 生成1kHz + 3kHz + 10kHz混合方波，用于FFT测试
//=============================================================================
always @(posedge clk_adc or negedge rst_n) begin
    if (!rst_n) begin
        test_counter <= 10'd0;
        test_signal_gen <= 16'd0;
    end else if (test_mode && run_flag) begin
        test_counter <= test_counter + 1'b1;
        
        // 1kHz方波（周期1000，采样率1MHz）
        // 3kHz方波（周期333）
        // 10kHz方波（周期100）
        test_signal_gen <= 
            (test_counter < 10'd500 ? 16'h4000 : 16'h0000) +   // 1kHz基波
            (test_counter % 10'd333 < 10'd166 ? 16'h2000 : 16'h0000) + // 3kHz
            (test_counter[6:0] < 7'd50 ? 16'h1000 : 16'h0000); // 10kHz
    end else begin
        test_counter <= 10'd0;
        test_signal_gen <= 16'd0;
    end
end

// 测试模式切换逻辑
always @(posedge clk_100m or negedge rst_n) begin
    if (!rst_n)
        test_mode <= 1'b0;
    else if (btn_test_mode)
        test_mode <= ~test_mode;
end

//=============================================================================
// 调试数据捕获逻辑 - 用于串口输出
//=============================================================================
// 在ADC时钟域捕获ADC数据
always @(posedge clk_adc or negedge rst_n) begin
    if (!rst_n) begin
        debug_adc_ch1_sample <= 16'd0;
        debug_adc_ch2_sample <= 16'd0;
        debug_data_valid <= 1'b0;
        debug_fifo_wr_count <= 16'd0;
    end else begin
        if (dual_data_valid) begin
            debug_adc_ch1_sample <= {ch1_data_sync, 6'h00};
            debug_adc_ch2_sample <= {ch2_data_sync, 6'h00};
            debug_data_valid <= 1'b1;
            debug_fifo_wr_count <= debug_fifo_wr_count + 1'b1;
        end
    end
end

// 在FFT时钟域捕获FFT输出数据
always @(posedge clk_fft or negedge rst_n) begin
    if (!rst_n) begin
        debug_fft_out_count <= 16'd0;
        debug_fft_done <= 1'b0;
    end else begin
        if (fft_dout_valid) begin
            debug_fft_out_count <= debug_fft_out_count + 1'b1;
            if (fft_dout_last)
                debug_fft_done <= 1'b1;
        end
    end
end

// 捕获频谱写入地址
always @(posedge clk_fft or negedge rst_n) begin
    if (!rst_n) begin
        debug_spectrum_addr_last <= 10'd0;
    end else begin
        if (ch1_spectrum_valid)
            debug_spectrum_addr_last <= {6'd0, ch1_spectrum_wr_addr};
    end
end

// ============= 跨时钟域同步：同步调试信号到100MHz域 =============
always @(posedge clk_100m or negedge rst_n) begin
    if (!rst_n) begin
        debug_adc_ch1_sample_sync <= 16'd0;
        debug_adc_ch2_sample_sync <= 16'd0;
        debug_fifo_wr_count_sync <= 16'd0;
        debug_fft_out_count_sync <= 16'd0;
        debug_spectrum_addr_last_sync <= 16'd0;
        debug_data_valid_sync <= 1'b0;
        debug_fft_done_sync <= 1'b0;
    end else begin
        // 简单的寄存器同步（对于多bit信号可能有亚稳态，但用于调试可接受）
        debug_adc_ch1_sample_sync <= debug_adc_ch1_sample;
        debug_adc_ch2_sample_sync <= debug_adc_ch2_sample;
        debug_fifo_wr_count_sync <= debug_fifo_wr_count;
        debug_fft_out_count_sync <= debug_fft_out_count;
        debug_spectrum_addr_last_sync <= debug_spectrum_addr_last;
        debug_data_valid_sync <= debug_data_valid;
        debug_fft_done_sync <= debug_fft_done;
    end
end

//=============================================================================
// 通道选择逻辑
//=============================================================================
always @(posedge clk_100m or negedge rst_n) begin
    if (!rst_n)
        channel_sel <= 1'b0;
    else if (btn_ch_sel)
        channel_sel <= ~channel_sel;
end

//=============================================================================
// MS7210配置模块
//=============================================================================
// MS7210配置控制器的信号
wire [7:0]  ms7210_device_id;
wire        ms7210_iic_trig;
wire        ms7210_w_r;
wire [15:0] ms7210_addr;
wire [7:0]  ms7210_data_in;
wire        ms7210_busy;
wire [7:0]  ms7210_data_out;
wire        ms7210_byte_over;

// IIC SDA三态信号
wire        hd_iic_sda_out;
wire        hd_iic_sda_oe;
// 1. MS7210配置控制器（生成配置序列）
ms7210_ctl u_ms7210_ctl (
    .clk        (clk_10m),              // 10MHz配置时钟
    .rstn       (rst_n),                // 复位
    .init_over  (ms7210_init_over),     // 配置完成标志
    
    // 输出到IIC驱动
    .device_id  (ms7210_device_id),     // 0xB2
    .iic_trig   (ms7210_iic_trig),      // IIC触发
    .w_r        (ms7210_w_r),           // 读写控制
    .addr       (ms7210_addr),          // 寄存器地址
    .data_in    (ms7210_data_in),       // 写数据
    
    // 从IIC驱动输入
    .busy       (ms7210_busy),          // IIC忙标志
    .data_out   (ms7210_data_out),      // 读数据
    .byte_over  (ms7210_byte_over)      // 字节传输完成
);

// 2. IIC底层驱动（实际发送IIC信号）
iic_dri #(
    .CLK_FRE    (27'd10_000_000),       // 10MHz系统时钟
    .IIC_FREQ   (20'd400_000),          // 400kHz IIC时钟
    .T_WR       (10'd1),                // 传输延时1ms
    .ADDR_BYTE  (2'd2),                 // 2字节地址（16位）
    .LEN_WIDTH  (8'd3),                 // 传输字节宽度
    .DATA_BYTE  (2'd1)                  // 1字节数据
) u_iic_dri_ms7210 (
    .clk        (clk_10m),              // 10MHz时钟
    .rstn       (rst_n),                // 复位
    
    // 从配置控制器输入
    .device_id  (ms7210_device_id),     // 设备地址
    .pluse      (ms7210_iic_trig),      // 触发信号
    .w_r        (ms7210_w_r),           // 读写方向
    .byte_len   (4'd1),                 // 每次传输1字节
    .addr       (ms7210_addr),          // 寄存器地址
    .data_in    (ms7210_data_in),       // 写数据
    
    // 输出到配置控制器
    .busy       (ms7210_busy),          // 忙标志
    .byte_over  (ms7210_byte_over),     // 字节完成
    .data_out   (ms7210_data_out),      // 读数据
    
    // 物理IIC接口
    .scl        (hd_iic_scl),           // IIC时钟输出
    .sda_in     (hd_iic_sda),           // IIC数据输入
    .sda_out    (hd_iic_sda_out),       // IIC数据输出
    .sda_out_en (hd_iic_sda_oe)         // IIC数据输出使能
);

assign hd_iic_sda = hd_iic_sda_oe ? hd_iic_sda_out : 1'bz;
//=============================================================================
// HDMI输出寄存器
//=============================================================================
always @(posedge clk_hdmi_pixel or negedge rst_n) begin
    if (!rst_n) begin
        hdmi_rgb_q <= 24'd0;
        hdmi_de_q  <= 1'b0;
        hdmi_hs_q  <= 1'b0;
        hdmi_vs_q  <= 1'b0;
    end else begin
        hdmi_rgb_q <= hdmi_rgb;
        hdmi_de_q  <= hdmi_de;
        hdmi_hs_q  <= hdmi_hs;
        hdmi_vs_q  <= hdmi_vs;
    end
end

//=============================================================================
// MS7210数据输出
//=============================================================================
assign hd_tx_pclk = clk_hdmi_pixel;
assign hd_tx_vs   = hdmi_vs_q;
assign hd_tx_hs   = hdmi_hs_q;
assign hd_tx_de   = hdmi_de_q;
assign hd_tx_data = hdmi_rgb_q;

//=============================================================================
// 实例化UART发送模块
//=============================================================================
reg  [4:0]  captured_blk_exp;
reg  [15:0] captured_fft_dout_re; // 捕获实部
reg         capture_event;

// HDMI调试定时器 - 每秒触发一次
reg [26:0] hdmi_debug_timer;
reg        hdmi_debug_trigger;

always @(posedge clk_100m or negedge rst_n) begin
    if (!rst_n) begin
        hdmi_debug_timer <= 27'd0;
        hdmi_debug_trigger <= 1'b0;
    end else begin
        if (hdmi_debug_timer == 27'd50_000_000 - 1) begin  // 0.5秒
            hdmi_debug_timer <= 27'd0;
            hdmi_debug_trigger <= 1'b1;
        end else begin
            hdmi_debug_timer <= hdmi_debug_timer + 1'b1;
            hdmi_debug_trigger <= 1'b0;
        end
    end
end

// HDMI同步信号活动检测（捕获任何翻转）
reg hdmi_vs_d1, hdmi_vs_d2;
reg hdmi_hs_d1, hdmi_hs_d2;
reg hdmi_vs_toggle_flag, hdmi_hs_toggle_flag;

always @(posedge clk_100m or negedge rst_n) begin
    if (!rst_n) begin
        hdmi_vs_d1 <= 1'b0;
        hdmi_vs_d2 <= 1'b0;
        hdmi_hs_d1 <= 1'b0;
        hdmi_hs_d2 <= 1'b0;
        hdmi_vs_toggle_flag <= 1'b0;
        hdmi_hs_toggle_flag <= 1'b0;
    end else begin
        hdmi_vs_d1 <= hdmi_vs;
        hdmi_vs_d2 <= hdmi_vs_d1;
        hdmi_hs_d1 <= hdmi_hs;
        hdmi_hs_d2 <= hdmi_hs_d1;
        
        // 检测到翻转就锁存标志
        if (hdmi_vs_d1 != hdmi_vs_d2)
            hdmi_vs_toggle_flag <= 1'b1;
        else if (hdmi_debug_trigger)  // 定时器触发时清除
            hdmi_vs_toggle_flag <= 1'b0;
            
        if (hdmi_hs_d1 != hdmi_hs_d2)
            hdmi_hs_toggle_flag <= 1'b1;
        else if (hdmi_debug_trigger)  // 定时器触发时清除
            hdmi_hs_toggle_flag <= 1'b0;
    end
end

uart_tx #(
    .CLOCK_FREQ(100_000_000),
    .BAUD_RATE(115200)
) u_uart_tx (
    .clk(clk_100m),
    .rst_n(rst_n),
    .data_in(uart_data_to_send),
    .send_trigger(uart_send_trigger),
    .uart_tx_pin(uart_tx),
    .busy(uart_busy)
);

// 在FFT时钟域捕获数据，避免跨时钟域问题
always @(posedge clk_fft or negedge rst_n) begin
    if (!rst_n) begin
        capture_event <= 1'b0;
    end else begin
        capture_event <= 1'b0; // 默认为0
        if (fft_dout_valid && fft_dout_last) begin
            captured_blk_exp     <= fft_tuser[4:0];     // 捕获块指数
            captured_fft_dout_re <= fft_dout[15:0];    // 捕获实部
            capture_event        <= 1'b1;               // 产生捕获事件脉冲
        end
    end
end
// --- UART发送状态机 - HDMI调试输出 (在100MHz系统时钟域) ---
// 输出格式: "HDMI: P1 P2 CLK INIT\n" 每0.5秒
// P1/P2 = PLL锁定状态 (0/1)
// CLK = HDMI时钟活动 (0/1)  
// INIT = MS7210初始化完成 (0/1)

always @(posedge clk_100m or negedge rst_n) begin
    if (!rst_n) begin
        send_state        <= 8'd0;
        uart_send_trigger <= 1'b0;
    end else begin
        uart_send_trigger <= 1'b0; // 脉冲信号，用完即清零

        case(send_state)
            8'd0: begin // 等待定时触发
                if (hdmi_debug_trigger && !uart_busy) begin
                    send_state <= 8'd1;
                end
            end

            8'd1: begin // 发送 'H'
                if (!uart_busy) begin
                    uart_data_to_send <= "H";
                    uart_send_trigger <= 1'b1;
                    send_state        <= 8'd2;
                end
            end

            8'd2: begin // 发送 'D'
                if (!uart_busy) begin
                    uart_data_to_send <= "D";
                    uart_send_trigger <= 1'b1;
                    send_state        <= 8'd3;
                end
            end
            
            8'd3: begin // 发送 'M'
                if (!uart_busy) begin
                    uart_data_to_send <= "M";
                    uart_send_trigger <= 1'b1;
                    send_state        <= 8'd4;
                end
            end

            8'd4: begin // 发送 'I'
                if (!uart_busy) begin
                    uart_data_to_send <= "I";
                    uart_send_trigger <= 1'b1;
                    send_state        <= 8'd5;
                end
            end

            8'd5: begin // 发送 ':'
                if (!uart_busy) begin
                    uart_data_to_send <= ":";
                    uart_send_trigger <= 1'b1;
                    send_state        <= 8'd6;
                end
            end
            
            8'd6: begin // 发送 ' '
                if (!uart_busy) begin
                    uart_data_to_send <= " ";
                    uart_send_trigger <= 1'b1;
                    send_state        <= 8'd7;
                end
            end
            
            8'd7: begin // 发送 PLL1状态
                if (!uart_busy) begin
                    uart_data_to_send <= pll1_lock ? "1" : "0";
                    uart_send_trigger <= 1'b1;
                    send_state        <= 8'd8;
                end
            end
            
            8'd8: begin // 发送 ' '
                if (!uart_busy) begin
                    uart_data_to_send <= " ";
                    uart_send_trigger <= 1'b1;
                    send_state        <= 8'd9;
                end
            end
            
            8'd9: begin // 发送 PLL2状态
                if (!uart_busy) begin
                    uart_data_to_send <= pll2_lock ? "1" : "0";
                    uart_send_trigger <= 1'b1;
                    send_state        <= 8'd10;
                end
            end
            
            8'd10: begin // 发送 ' '
                if (!uart_busy) begin
                    uart_data_to_send <= " ";
                    uart_send_trigger <= 1'b1;
                    send_state        <= 8'd11;
                end
            end
            
            8'd11: begin // 发送 HDMI时钟状态 (简化：使用PLL2状态代替)
                if (!uart_busy) begin
                    uart_data_to_send <= pll2_lock ? "1" : "0";
                    uart_send_trigger <= 1'b1;
                    send_state        <= 8'd12;
                end
            end
            
            8'd12: begin // 发送 ' '
                if (!uart_busy) begin
                    uart_data_to_send <= " ";
                    uart_send_trigger <= 1'b1;
                    send_state        <= 8'd13;
                end
            end
            
            8'd13: begin // 发送 MS7210初始化状态
                if (!uart_busy) begin
                    uart_data_to_send <= ms7210_init_over ? "1" : "0";
                    uart_send_trigger <= 1'b1;
                    send_state        <= 8'd14;
                end
            end
            
            8'd14: begin // 发送 ' |V='
                if (!uart_busy) begin
                    uart_data_to_send <= " ";
                    uart_send_trigger <= 1'b1;
                    send_state        <= 8'd15;
                end
            end
            
            8'd15: begin // 发送 'V'
                if (!uart_busy) begin
                    uart_data_to_send <= "V";
                    uart_send_trigger <= 1'b1;
                    send_state        <= 8'd16;
                end
            end
            
            8'd16: begin // 发送 '='
                if (!uart_busy) begin
                    uart_data_to_send <= "=";
                    uart_send_trigger <= 1'b1;
                    send_state        <= 8'd17;
                end
            end
            
            8'd17: begin // 发送 VS活动标志（是否有翻转）
                if (!uart_busy) begin
                    uart_data_to_send <= hdmi_vs_toggle_flag ? "1" : "0";
                    uart_send_trigger <= 1'b1;
                    send_state        <= 8'd18;
                end
            end
            
            8'd18: begin // 发送 ' H='
                if (!uart_busy) begin
                    uart_data_to_send <= " ";
                    uart_send_trigger <= 1'b1;
                    send_state        <= 8'd19;
                end
            end
            
            8'd19: begin // 发送 'H'
                if (!uart_busy) begin
                    uart_data_to_send <= "H";
                    uart_send_trigger <= 1'b1;
                    send_state        <= 8'd20;
                end
            end
            
            8'd20: begin // 发送 '='
                if (!uart_busy) begin
                    uart_data_to_send <= "=";
                    uart_send_trigger <= 1'b1;
                    send_state        <= 8'd21;
                end
            end
            
            8'd21: begin // 发送 HS活动标志（是否有翻转）
                if (!uart_busy) begin
                    uart_data_to_send <= hdmi_hs_toggle_flag ? "1" : "0";
                    uart_send_trigger <= 1'b1;
                    send_state        <= 8'd22;
                end
            end
            
            8'd22: begin // 发送 ' D='
                if (!uart_busy) begin
                    uart_data_to_send <= " ";
                    uart_send_trigger <= 1'b1;
                    send_state        <= 8'd23;
                end
            end
            
            8'd23: begin // 发送 'D'
                if (!uart_busy) begin
                    uart_data_to_send <= "D";
                    uart_send_trigger <= 1'b1;
                    send_state        <= 8'd24;
                end
            end
            
            8'd24: begin // 发送 '='
                if (!uart_busy) begin
                    uart_data_to_send <= "=";
                    uart_send_trigger <= 1'b1;
                    send_state        <= 8'd25;
                end
            end
            
            8'd25: begin // 发送 DE状态
                if (!uart_busy) begin
                    uart_data_to_send <= hdmi_de ? "1" : "0";
                    uart_send_trigger <= 1'b1;
                    send_state        <= 8'd26;
                end
            end
            
            8'd26: begin // 发送 ' R='
                if (!uart_busy) begin
                    uart_data_to_send <= " ";
                    uart_send_trigger <= 1'b1;
                    send_state        <= 8'd27;
                end
            end
            
            8'd27: begin // 发送 'R'
                if (!uart_busy) begin
                    uart_data_to_send <= "R";
                    uart_send_trigger <= 1'b1;
                    send_state        <= 8'd28;
                end
            end
            
            8'd28: begin // 发送 '='
                if (!uart_busy) begin
                    uart_data_to_send <= "=";
                    uart_send_trigger <= 1'b1;
                    send_state        <= 8'd29;
                end
            end
            
            8'd29: begin // 发送 RST_N状态
                if (!uart_busy) begin
                    uart_data_to_send <= rst_n ? "1" : "0";
                    uart_send_trigger <= 1'b1;
                    send_state        <= 8'd30;
                end
            end
            
            8'd30: begin // 发送 ' M='
                if (!uart_busy) begin
                    uart_data_to_send <= " ";
                    uart_send_trigger <= 1'b1;
                    send_state        <= 8'd31;
                end
            end
            
            8'd31: begin // 发送 'M'
                if (!uart_busy) begin
                    uart_data_to_send <= "M";
                    uart_send_trigger <= 1'b1;
                    send_state        <= 8'd32;
                end
            end
            
            8'd32: begin // 发送 '='
                if (!uart_busy) begin
                    uart_data_to_send <= "=";
                    uart_send_trigger <= 1'b1;
                    send_state        <= 8'd33;
                end
            end
            
            8'd33: begin // 发送 工作模式
                if (!uart_busy) begin
                    uart_data_to_send <= "0" + work_mode[1:0];
                    uart_send_trigger <= 1'b1;
                    send_state        <= 8'd34;
                end
            end
            
            8'd34: begin // 发送 ' RGB='
                if (!uart_busy) begin
                    uart_data_to_send <= " ";
                    uart_send_trigger <= 1'b1;
                    send_state        <= 8'd35;
                end
            end
            
            8'd35: begin // 发送 'R'
                if (!uart_busy) begin
                    uart_data_to_send <= "R";
                    uart_send_trigger <= 1'b1;
                    send_state        <= 8'd36;
                end
            end
            
            8'd36: begin // 发送 'G'
                if (!uart_busy) begin
                    uart_data_to_send <= "G";
                    uart_send_trigger <= 1'b1;
                    send_state        <= 8'd37;
                end
            end
            
            8'd37: begin // 发送 'B'
                if (!uart_busy) begin
                    uart_data_to_send <= "B";
                    uart_send_trigger <= 1'b1;
                    send_state        <= 8'd38;
                end
            end
            
            8'd38: begin // 发送 '='
                if (!uart_busy) begin
                    uart_data_to_send <= "=";
                    uart_send_trigger <= 1'b1;
                    send_state        <= 8'd39;
                end
            end
            
            8'd39: begin // 发送 RGB高4位 (检查是否有非0值)
                if (!uart_busy) begin
                    // 发送R通道是否非0
                    uart_data_to_send <= (hdmi_rgb[23:16] != 8'h00) ? "1" : "0";
                    uart_send_trigger <= 1'b1;
                    send_state        <= 8'd40;
                end
            end
            
            8'd40: begin // 发送换行
                if (!uart_busy) begin
                    uart_data_to_send <= 8'd10;  // '\n'
                    uart_send_trigger <= 1'b1;
                    send_state        <= 8'd41; // 继续输出调试信息
                end
            end
            
            // ========== 新增：ADC和FFT调试信息 ==========
            8'd41: begin // 发送 'ADC:'
                if (!uart_busy) begin
                    uart_data_to_send <= "A";
                    uart_send_trigger <= 1'b1;
                    send_state        <= 8'd42;
                end
            end
            
            8'd42: begin
                if (!uart_busy) begin
                    uart_data_to_send <= "D";
                    uart_send_trigger <= 1'b1;
                    send_state        <= 8'd43;
                end
            end
            
            8'd43: begin
                if (!uart_busy) begin
                    uart_data_to_send <= "C";
                    uart_send_trigger <= 1'b1;
                    send_state        <= 8'd44;
                end
            end
            
            8'd44: begin // ':'
                if (!uart_busy) begin
                    uart_data_to_send <= ":";
                    uart_send_trigger <= 1'b1;
                    send_state        <= 8'd45;
                end
            end
            
            8'd45: begin // 发送ADC有效标志
                if (!uart_busy) begin
                    uart_data_to_send <= debug_data_valid_sync ? "1" : "0";
                    uart_send_trigger <= 1'b1;
                    send_state        <= 8'd46;
                end
            end
            
            8'd46: begin // 空格
                if (!uart_busy) begin
                    uart_data_to_send <= " ";
                    uart_send_trigger <= 1'b1;
                    send_state        <= 8'd47;
                end
            end
            
            8'd47: begin // 发送FIFO写计数（千位）
                if (!uart_busy) begin
                    uart_data_to_send <= "0" + ((debug_fifo_wr_count_sync / 1000) % 10);
                    uart_send_trigger <= 1'b1;
                    send_state        <= 8'd48;
                end
            end
            
            8'd48: begin // 百位
                if (!uart_busy) begin
                    uart_data_to_send <= "0" + ((debug_fifo_wr_count_sync / 100) % 10);
                    uart_send_trigger <= 1'b1;
                    send_state        <= 8'd49;
                end
            end
            
            8'd49: begin // 十位
                if (!uart_busy) begin
                    uart_data_to_send <= "0" + ((debug_fifo_wr_count_sync / 10) % 10);
                    uart_send_trigger <= 1'b1;
                    send_state        <= 8'd50;
                end
            end
            
            8'd50: begin // 个位
                if (!uart_busy) begin
                    uart_data_to_send <= "0" + (debug_fifo_wr_count_sync % 10);
                    uart_send_trigger <= 1'b1;
                    send_state        <= 8'd51;
                end
            end
            
            8'd51: begin // 发送 ' FFT:'
                if (!uart_busy) begin
                    uart_data_to_send <= " ";
                    uart_send_trigger <= 1'b1;
                    send_state        <= 8'd52;
                end
            end
            
            8'd52: begin
                if (!uart_busy) begin
                    uart_data_to_send <= "F";
                    uart_send_trigger <= 1'b1;
                    send_state        <= 8'd53;
                end
            end
            
            8'd53: begin
                if (!uart_busy) begin
                    uart_data_to_send <= "F";
                    uart_send_trigger <= 1'b1;
                    send_state        <= 8'd54;
                end
            end
            
            8'd54: begin
                if (!uart_busy) begin
                    uart_data_to_send <= "T";
                    uart_send_trigger <= 1'b1;
                    send_state        <= 8'd55;
                end
            end
            
            8'd55: begin
                if (!uart_busy) begin
                    uart_data_to_send <= ":";
                    uart_send_trigger <= 1'b1;
                    send_state        <= 8'd56;
                end
            end
            
            8'd56: begin // FFT完成标志
                if (!uart_busy) begin
                    uart_data_to_send <= debug_fft_done_sync ? "1" : "0";
                    uart_send_trigger <= 1'b1;
                    send_state        <= 8'd57;
                end
            end
            
            8'd57: begin // 空格
                if (!uart_busy) begin
                    uart_data_to_send <= " ";
                    uart_send_trigger <= 1'b1;
                    send_state        <= 8'd58;
                end
            end
            
            8'd58: begin // FFT输出计数（千位）
                if (!uart_busy) begin
                    uart_data_to_send <= "0" + ((debug_fft_out_count_sync / 1000) % 10);
                    uart_send_trigger <= 1'b1;
                    send_state        <= 8'd59;
                end
            end
            
            8'd59: begin // 百位
                if (!uart_busy) begin
                    uart_data_to_send <= "0" + ((debug_fft_out_count_sync / 100) % 10);
                    uart_send_trigger <= 1'b1;
                    send_state        <= 8'd60;
                end
            end
            
            8'd60: begin // 十位
                if (!uart_busy) begin
                    uart_data_to_send <= "0" + ((debug_fft_out_count_sync / 10) % 10);
                    uart_send_trigger <= 1'b1;
                    send_state        <= 8'd61;
                end
            end
            
            8'd61: begin // 个位
                if (!uart_busy) begin
                    uart_data_to_send <= "0" + (debug_fft_out_count_sync % 10);
                    uart_send_trigger <= 1'b1;
                    send_state        <= 8'd62;
                end
            end
            
            8'd62: begin // 发送 ' SADDR:'
                if (!uart_busy) begin
                    uart_data_to_send <= " ";
                    uart_send_trigger <= 1'b1;
                    send_state        <= 8'd63;
                end
            end
            
            8'd63: begin
                if (!uart_busy) begin
                    uart_data_to_send <= "S";
                    uart_send_trigger <= 1'b1;
                    send_state        <= 8'd64;
                end
            end
            
            8'd64: begin
                if (!uart_busy) begin
                    uart_data_to_send <= ":";
                    uart_send_trigger <= 1'b1;
                    send_state        <= 8'd65;
                end
            end
            
            8'd65: begin // 频谱地址（千位）
                if (!uart_busy) begin
                    uart_data_to_send <= "0" + ((debug_spectrum_addr_last_sync / 1000) % 10);
                    uart_send_trigger <= 1'b1;
                    send_state        <= 8'd66;
                end
            end
            
            8'd66: begin // 百位
                if (!uart_busy) begin
                    uart_data_to_send <= "0" + ((debug_spectrum_addr_last_sync / 100) % 10);
                    uart_send_trigger <= 1'b1;
                    send_state        <= 8'd67;
                end
            end
            
            8'd67: begin // 十位
                if (!uart_busy) begin
                    uart_data_to_send <= "0" + ((debug_spectrum_addr_last_sync / 10) % 10);
                    uart_send_trigger <= 1'b1;
                    send_state        <= 8'd68;
                end
            end
            
            8'd68: begin // 个位
                if (!uart_busy) begin
                    uart_data_to_send <= "0" + (debug_spectrum_addr_last_sync % 10);
                    uart_send_trigger <= 1'b1;
                    send_state        <= 8'd69;
                end
            end
            
            8'd69: begin // 最终换行
                if (!uart_busy) begin
                    uart_data_to_send <= 8'd10;  // '\n'
                    uart_send_trigger <= 1'b1;
                    send_state        <= 8'd0;  // 回到等待状态
                end
            end

            default: send_state <= 8'd0;
        endcase
    end
end

endmodule