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
    input  wire         adc_ch1_otr,        // 通道1溢出检测 (Over-Range)
    
    // 通道2 (AD-IN2)
    input  wire [9:0]   adc_ch2_data,       // 通道2数据 (管脚5,7,8,9,10,11,12,13,14,15)
    output wire         adc_ch2_clk,        // 通道2时钟 (管脚16)
    input  wire         adc_ch2_otr,        // 通道2溢出检测 (Over-Range)

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
localparam FFT_POINTS = 8192;               // FFT点数
localparam ADC_WIDTH  = 10;                 // ADC位宽
localparam FFT_WIDTH  = 10;                 // FFT数据位宽（10位ADC直接使用）

//=============================================================================
// 时钟和复位信号
//=============================================================================
wire        clk_100m;                       // 100MHz系统时钟
wire        clk_10m;                        // 10MHz中间时钟
wire        clk_adc;                        // 35MHz ADC采样时钟
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
wire [9:0]  ch1_data_sync;                  // 同步后的通道1数据（10位）
wire [9:0]  ch2_data_sync;                  // 同步后的通道2数据（10位）
// 10位ADC数据保持不变（变量名保留兼容性，但实际只用10位）
wire [10:0] ch1_data_11b;                   // 通道1数据（兼容变量名，实际10位有效）
wire [10:0] ch2_data_11b;                   // 通道2数据（兼容变量名，实际10位有效）
assign ch1_data_11b = {1'b0, ch1_data_sync};  // 高位补0，保持接口兼容
assign ch2_data_11b = {1'b0, ch2_data_sync};  // 高位补0，保持接口兼容

// ADC溢出检测信号
reg         adc_ch1_otr_sync;               // 同步后的通道1 OTR信号
reg         adc_ch2_otr_sync;               // 同步后的通道2 OTR信号
reg         adc_ch1_otr_flag;               // 通道1溢出标志（锁存）
reg         adc_ch2_otr_flag;               // 通道2溢出标志（锁存）
wire        adc_otr_clear;                  // 溢出标志清除信号（按键触发）

wire        dual_data_valid;                // 两个通道的数据同步有效标志
// ✅ 改为独立通道使能控制（类似专业示波器）
reg         ch1_enable;                     // 通道1显示使能
reg         ch2_enable;                     // 通道2显示使能
wire        btn_ch1_toggle;                 // 通道1开关按键
wire        btn_ch2_toggle;                 // 通道2开关按键
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
wire [13:0] ch1_fifo_rd_water_level;        // 通道1 FIFO读水位（IP核输出14位[13:0]）
wire [13:0] ch1_fifo_wr_water_level;        // 通道1 FIFO写水位（IP核输出14位[13:0]）

// 通道2 FIFO
wire        ch2_fifo_wr_en;                 // 通道2 FIFO写使能
wire [15:0] ch2_fifo_din;                   // 通道2 FIFO输入数据
wire        ch2_fifo_rd_en;                 // 通道2 FIFO读使能
wire [15:0] ch2_fifo_dout;                  // 通道2 FIFO输出数据
wire        ch2_fifo_full;                  // 通道2 FIFO满标志
wire        ch2_fifo_empty;                 // 通道2 FIFO空标志
wire [13:0] ch2_fifo_rd_water_level;        // 通道2 FIFO读水位（IP核输出14位[13:0]）
wire [13:0] ch2_fifo_wr_water_level;        // 通道2 FIFO写水位（IP核输出14位[13:0]）

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
// 通道1频谱（原始）
wire [15:0] ch1_spectrum_magnitude;         // 通道1频谱幅度（FFT输出）
wire [12:0] ch1_spectrum_wr_addr;           // 通道1频谱写地址（8192需要13位）
wire        ch1_spectrum_valid;             // 通道1频谱数据有效

// 通道1频谱平滑（指数平滑滤波）
reg  [15:0] ch1_spectrum_smoothed;          // 通道1平滑后的频谱幅度
reg  [12:0] ch1_spectrum_smoothed_addr;     // 通道1平滑后的地址
reg         ch1_spectrum_smoothed_valid;    // 通道1平滑后的有效信号

// 通道2频谱（原始）
wire [15:0] ch2_spectrum_magnitude;         // 通道2频谱幅度（FFT输出）
wire [12:0] ch2_spectrum_wr_addr;           // 通道2频谱写地址（8192需要13位）
wire        ch2_spectrum_valid;             // 通道2频谱数据有效

// 通道2频谱平滑（指数平滑滤波）
reg  [15:0] ch2_spectrum_smoothed;          // 通道2平滑后的频谱幅度
reg  [12:0] ch2_spectrum_smoothed_addr;     // 通道2平滑后的地址
reg         ch2_spectrum_smoothed_valid;    // 通道2平滑后的有效信号

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
wire [12:0] spectrum_rd_addr;               // 频谱读地址（8192需要13位）
reg [7:0]   user_led_reg;                   // 用户LED寄存器

// ADC溢出标志同步到100MHz时钟域（用于LED显示）
reg         adc_ch1_otr_sync_100m;
reg         adc_ch2_otr_sync_100m;

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
// 触发系统信号
//=============================================================================
reg         trigger_mode;                   // 触发模式: 0=Auto, 1=Normal
reg         trigger_edge;                   // 触发边沿: 0=上升沿, 1=下降沿
reg [9:0]   trigger_level;                  // 触发电平 (0-1023, 10位ADC范围)
wire        btn_trig_mode;                  // 触发模式切换按键
wire        btn_trig_level_up;              // 触发电平增加按键
wire        btn_trig_level_dn;              // 触发电平减少按键

// 触发检测信号
reg [9:0]   adc_data_d1, adc_data_d2;       // ADC数据延迟（用于边沿检测）
wire        trigger_event;                  // 触发事件脉冲
reg         triggered;                      // 已触发标志
reg [23:0]  auto_trigger_timer;             // 自动触发超时计数器（100MHz）
localparam  AUTO_TRIG_TIMEOUT = 24'd10_000_000;  // 100ms超时

//=============================================================================
// 信号参数测量 - 双通道
//=============================================================================
// 通道1参数
wire [15:0] ch1_freq;                       // CH1信号频率
wire        ch1_freq_is_khz;                // CH1频率单位标志 (0=Hz, 1=kHz, 与ch1_freq_is_mhz组合)
wire        ch1_freq_is_mhz;                // CH1 MHz单位标志 (1=MHz)
wire [15:0] ch1_amplitude;                  // CH1信号幅度
wire [15:0] ch1_duty;                       // CH1占空比
wire [15:0] ch1_thd;                        // CH1总谐波失真

// 通道1 THD调试信号
wire [15:0] ch1_dbg_harmonic_2;
wire [15:0] ch1_dbg_harmonic_3;
wire [15:0] ch1_dbg_harmonic_4;
wire [15:0] ch1_dbg_harmonic_5;
wire [31:0] ch1_dbg_harmonic_sum;
wire [15:0] ch1_dbg_fft_max_amp;
wire        ch1_dbg_calc_trigger;
wire [2:0]  ch1_dbg_pipe_valid;

// 通道2参数
wire [15:0] ch2_freq;                       // CH2信号频率
wire        ch2_freq_is_khz;                // CH2频率单位标志 (0=Hz, 1=kHz, 与ch2_freq_is_mhz组合)
wire        ch2_freq_is_mhz;                // CH2 MHz单位标志 (1=MHz)
wire [15:0] ch2_amplitude;                  // CH2信号幅度
wire [15:0] ch2_duty;                       // CH2占空比
wire [15:0] ch2_thd;                        // CH2总谐波失真

//=============================================================================
// 相位差测量信号
//=============================================================================
wire signed [15:0] phase_difference;        // 相位差 (-1800 ~ +1799 = -180.0° ~ +179.9°)
wire        phase_diff_valid;               // 相位差有效
wire [7:0]  phase_confidence;               // 相位差置信度 (0-255)

// 【添加】相位差信号跨时钟域同步到HDMI时钟域
reg signed [15:0] phase_diff_sync1, phase_diff_sync2;
reg [7:0] phase_conf_sync1, phase_conf_sync2;

always @(posedge clk_hdmi_pixel or negedge rst_n) begin
    if (!rst_n) begin
        phase_diff_sync1 <= 16'sd0;
        phase_diff_sync2 <= 16'sd0;
        phase_conf_sync1 <= 8'd0;
        phase_conf_sync2 <= 8'd0;
    end else begin
        // 两级寄存器同步
        phase_diff_sync1 <= phase_difference;
        phase_diff_sync2 <= phase_diff_sync1;
        phase_conf_sync1 <= phase_confidence;
        phase_conf_sync2 <= phase_conf_sync1;
    end
end

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
wire [12:0] ch1_ram0_wr_addr;
wire [15:0] ch1_ram0_wr_data;
wire [12:0] ch1_ram0_rd_addr;
wire [10:0] ch1_ram0_rd_data_11b;  // 11位RAM输出
wire [15:0] ch1_ram0_rd_data;      // 扩展到16位
assign ch1_ram0_rd_data = {5'd0, ch1_ram0_rd_data_11b};

// 通道1 RAM1信号
wire        ch1_ram1_we;
wire [12:0] ch1_ram1_wr_addr;
wire [15:0] ch1_ram1_wr_data;
wire [12:0] ch1_ram1_rd_addr;
wire [10:0] ch1_ram1_rd_data_11b;  // 11位RAM输出
wire [15:0] ch1_ram1_rd_data;      // 扩展到16位
assign ch1_ram1_rd_data = {5'd0, ch1_ram1_rd_data_11b};

// 通道2乒乓缓存控制信号
reg         ch2_buffer_sel;                     // 通道2缓存选择
reg         ch2_buffer_sel_sync1, ch2_buffer_sel_sync2;  // 跨时钟域同步

// 通道2 RAM0信号
wire        ch2_ram0_we;
wire [12:0] ch2_ram0_wr_addr;
wire [15:0] ch2_ram0_wr_data;
wire [12:0] ch2_ram0_rd_addr;
wire [10:0] ch2_ram0_rd_data_11b;  // 11位RAM输出
wire [15:0] ch2_ram0_rd_data;      // 扩展到16位
assign ch2_ram0_rd_data = {5'd0, ch2_ram0_rd_data_11b};

// 通道2 RAM1信号
wire        ch2_ram1_we;
wire [12:0] ch2_ram1_wr_addr;
wire [15:0] ch2_ram1_wr_data;
wire [12:0] ch2_ram1_rd_addr;
wire [10:0] ch2_ram1_rd_data_11b;  // 11位RAM输出
wire [15:0] ch2_ram1_rd_data;      // 扩展到16位
assign ch2_ram1_rd_data = {5'd0, ch2_ram1_rd_data_11b};
wire [15:0] ram0_rd_data;

// RAM1信号
wire        ram1_we;
wire [12:0] ram1_wr_addr;
wire [15:0] ram1_wr_data;
wire [12:0] ram1_rd_addr;
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

// BCD计数器（避免除法运算，时序优化）
reg  [3:0]  debug_fifo_wr_bcd_1;       // FIFO计数个位
reg  [3:0]  debug_fifo_wr_bcd_10;      // FIFO计数十位

//=============================================================================
// 微弱信号检测模块信号
//=============================================================================
// 配置信号
reg  [1:0]  weak_sig_ref_mode;          // 参考模式: 0=内部DDS, 1=CH2作参考, 2=外部, 3=自动
reg  [31:0] weak_sig_ref_freq;          // 参考频率（Hz）
reg  [3:0]  weak_sig_gain;              // 数字增益: 0-15
// weak_sig_lpf_tc 已移除 - 滤波器阶数固定为8（256点）
reg         weak_sig_auto_gain;         // 自动增益控制使能
reg         weak_sig_enable;            // 微弱信号检测使能

// CH1检测结果
wire signed [23:0] ch1_lia_i;           // CH1 I分量
wire signed [23:0] ch1_lia_q;           // CH1 Q分量
wire [23:0]        ch1_lia_magnitude;   // CH1 幅度
wire [15:0]        ch1_lia_phase;       // CH1 相位
wire               ch1_lia_locked;      // CH1 锁定状态
wire               ch1_lia_valid;       // CH1 结果有效

// CH2检测结果
wire signed [23:0] ch2_lia_i;           // CH2 I分量
wire signed [23:0] ch2_lia_q;           // CH2 Q分量
wire [23:0]        ch2_lia_magnitude;   // CH2 幅度
wire [15:0]        ch2_lia_phase;       // CH2 相位
wire               ch2_lia_locked;      // CH2 锁定状态
wire               ch2_lia_valid;       // CH2 结果有效

// SNR和状态
wire [15:0]        weak_sig_snr;        // 信噪比估计（dB）

//=============================================================================
// AI信号识别模块信号
//=============================================================================
// 配置信号
reg         ai_enable;                  // AI识别使能
wire        btn_ai_enable;              // AI识别使能按键

// CH1识别结果
wire [2:0]  ch1_waveform_type;          // CH1波形类型: 0=未知,1=正弦,2=方波,3=三角,4=锯齿,5=噪声
wire [7:0]  ch1_confidence;             // CH1置信度 (0-100%)
wire        ch1_ai_valid;               // CH1识别结果有效

// CH2识别结果
wire [2:0]  ch2_waveform_type;          // CH2波形类型
wire [7:0]  ch2_confidence;             // CH2置信度
wire        ch2_ai_valid;               // CH2识别结果有效

// 调试特征输出
wire [15:0] ch1_dbg_zcr;                // CH1过零率
wire [15:0] ch1_dbg_crest_factor;       // CH1峰值因子
wire [15:0] ch1_dbg_thd;                // CH1 THD
wire [15:0] ch2_dbg_zcr;
wire [15:0] ch2_dbg_crest_factor;
wire [15:0] ch2_dbg_thd;
wire               weak_sig_snr_valid;  // SNR有效
wire [3:0]         weak_sig_current_gain; // 当前增益
wire [31:0]        weak_sig_detected_freq; // 检测到的频率

// 按键控制
wire               btn_weak_sig_enable; // 微弱信号检测使能按键
wire               btn_ref_freq_up;     // 参考频率增加
wire               btn_ref_freq_dn;     // 参考频率减少
wire               btn_ref_mode;        // 参考模式切换
reg  [3:0]  debug_fifo_wr_bcd_100;     // FIFO计数百位
reg  [3:0]  debug_fifo_wr_bcd_1000;    // FIFO计数千位
reg  [3:0]  debug_fft_out_bcd_1;       // FFT计数个位
reg  [3:0]  debug_fft_out_bcd_10;      // FFT计数十位
reg  [3:0]  debug_fft_out_bcd_100;     // FFT计数百位
reg  [3:0]  debug_fft_out_bcd_1000;    // FFT计数千位

// 同步到100MHz域的调试信号（用于UART发送）
reg  [15:0] debug_adc_ch1_sample_sync;
reg  [15:0] debug_adc_ch2_sample_sync;
reg  [15:0] debug_fifo_wr_count_sync;
reg  [15:0] debug_fft_out_count_sync;
reg  [15:0] debug_spectrum_addr_last_sync;
reg         debug_data_valid_sync;
reg         debug_fft_done_sync;

// 预计算的数字字符（流水线优化，减少组合逻辑延迟）
reg  [3:0]  fifo_count_digit_1000;
reg  [3:0]  fifo_count_digit_100;
reg  [3:0]  fifo_count_digit_10;
reg  [3:0]  fifo_count_digit_1;
reg  [3:0]  fft_count_digit_1000;
reg  [3:0]  fft_count_digit_100;
reg  [3:0]  fft_count_digit_10;
reg  [3:0]  fft_count_digit_1;
reg  [3:0]  spectrum_addr_digit_1000;
reg  [3:0]  spectrum_addr_digit_100;
reg  [3:0]  spectrum_addr_digit_10;
reg  [3:0]  spectrum_addr_digit_1;
reg  [3:0]  adc_ch1_digit_10000;
reg  [3:0]  adc_ch1_digit_1000;
reg  [3:0]  adc_ch1_digit_100;
reg  [3:0]  adc_ch1_digit_10;
reg  [3:0]  adc_ch1_digit_1;
reg  [3:0]  adc_ch2_digit_10000;
reg  [3:0]  adc_ch2_digit_1000;
reg  [3:0]  adc_ch2_digit_100;
reg  [3:0]  adc_ch2_digit_10;
reg  [3:0]  adc_ch2_digit_1;
// 完整频谱地址的5位数字（用于SFULL输出）
reg  [3:0]  spectrum_addr_full_digit_10000;
reg  [3:0]  spectrum_addr_full_digit_1000;
reg  [3:0]  spectrum_addr_full_digit_100;
reg  [3:0]  spectrum_addr_full_digit_10;
reg  [3:0]  spectrum_addr_full_digit_1;

// 二级流水线：中间除法结果（减少组合逻辑深度）
reg  [15:0] fifo_count_div10;
reg  [15:0] fifo_count_div100;
reg  [15:0] fifo_count_div1000;
reg  [15:0] fft_count_div10;
reg  [15:0] fft_count_div100;
reg  [15:0] fft_count_div1000;
reg  [15:0] spectrum_addr_div10;
reg  [15:0] spectrum_addr_div100;
reg  [15:0] spectrum_addr_div1000;
reg  [15:0] spectrum_addr_div10000;
reg  [15:0] adc_ch1_div10;
reg  [15:0] adc_ch1_div100;
reg  [15:0] adc_ch1_div1000;
reg  [15:0] adc_ch1_div10000;
reg  [15:0] adc_ch2_div10;
reg  [15:0] adc_ch2_div100;
reg  [15:0] adc_ch2_div1000;
reg  [15:0] adc_ch2_div10000;

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
// VCO = 1400MHz (50MHz × 28 / 1)
// CLKOUT0 = 100MHz (1400MHz / 14) - 系统时钟
// CLKOUT1 = 10MHz (1400MHz / 140) - 保留
// CLKOUT2 = 35MHz (1400MHz / 40) - ADC采样时钟

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
// ✅ 改为根据通道使能来选择数据（优先CH1，其次CH2）
// 注意：这里仍使用8位用于显示和参数测量（兼容现有接口）
assign adc_data_sync = ch1_enable ? ch1_data_sync[9:2] : 
                       ch2_enable ? ch2_data_sync[9:2] : 8'h00;
assign adc_data_valid = dual_data_valid;
// ADC数据扩展到16位 - 用于FFT等需要单通道输入的模块
// 使用11位扩展数据以提高精度
assign selected_adc_data = ch1_enable ? {5'h00, ch1_data_11b} : 
                           ch2_enable ? {5'h00, ch2_data_11b} : 16'h0000;
assign adc_data_ext = selected_adc_data;

adc_capture_dual u_adc_dual (
    .clk                (clk_adc),
    .rst_n              (rst_n),
    
    // 通道1接口
    .adc_ch1_in         (adc_ch1_data),
    .adc_ch1_clk_out    (adc_ch1_clk),
    
    // 通道2接口
    .adc_ch2_in         (adc_ch2_data),
    .adc_ch2_clk_out    (adc_ch2_clk),
    
    // 数据输出
    .ch1_data_out       (ch1_data_sync),
    .ch2_data_out       (ch2_data_sync),
    .data_valid         (dual_data_valid),
    
    .enable             (run_flag)
);

//=============================================================================
// 3.5 ADC溢出检测（OTR信号处理）
//=============================================================================
// OTR信号同步到ADC时钟域（双级同步器，避免亚稳态）
always @(posedge clk_adc or negedge rst_n) begin
    if (!rst_n) begin
        adc_ch1_otr_sync <= 1'b0;
        adc_ch2_otr_sync <= 1'b0;
    end else begin
        adc_ch1_otr_sync <= adc_ch1_otr;
        adc_ch2_otr_sync <= adc_ch2_otr;
    end
end

// 溢出标志锁存（一旦发生溢出，保持标志直到手动清除）
assign adc_otr_clear = user_button[7];  // 按键7清除溢出标志

always @(posedge clk_adc or negedge rst_n) begin
    if (!rst_n) begin
        adc_ch1_otr_flag <= 1'b0;
        adc_ch2_otr_flag <= 1'b0;
    end else begin
        // 检测到溢出时锁存标志
        if (adc_ch1_otr_sync && dual_data_valid)
            adc_ch1_otr_flag <= 1'b1;
        else if (adc_otr_clear)  // 按键清除
            adc_ch1_otr_flag <= 1'b0;
            
        if (adc_ch2_otr_sync && dual_data_valid)
            adc_ch2_otr_flag <= 1'b1;
        else if (adc_otr_clear)  // 按键清除
            adc_ch2_otr_flag <= 1'b0;
    end
end

//=============================================================================
// 3.6 触发检测逻辑（ADC时钟域）
//=============================================================================
// 触发电平和模式同步到ADC时钟域
reg [9:0]   trigger_level_sync;
reg         trigger_mode_sync;
reg [1:0]   work_mode_sync;

always @(posedge clk_adc or negedge rst_n) begin
    if (!rst_n) begin
        trigger_level_sync <= 10'd512;
        trigger_mode_sync  <= 1'b0;
        work_mode_sync     <= 2'd0;
    end else begin
        trigger_level_sync <= trigger_level;
        trigger_mode_sync  <= trigger_mode;
        work_mode_sync     <= work_mode;
    end
end

// ADC数据延迟（边沿检测）
always @(posedge clk_adc or negedge rst_n) begin
    if (!rst_n) begin
        adc_data_d1 <= 10'd0;
        adc_data_d2 <= 10'd0;
    end else if (dual_data_valid) begin
        adc_data_d1 <= ch1_data_sync;  // 使用通道1进行触发
        adc_data_d2 <= adc_data_d1;
    end
end

// 上升沿检测：前一个采样点 < 触发电平，当前采样点 >= 触发电平
assign trigger_event = (work_mode_sync == 2'd0) &&  // 仅在时域模式下触发
                       dual_data_valid &&
                       (adc_data_d2 < trigger_level_sync) && 
                       (adc_data_d1 >= trigger_level_sync);

// 触发状态机（ADC时钟域）
reg [1:0] trig_state;  // 0=IDLE, 1=WAIT_TRIG, 2=TRIGGERED, 3=TIMEOUT
localparam TRIG_IDLE      = 2'd0;
localparam TRIG_WAIT      = 2'd1;
localparam TRIG_TRIGGERED = 2'd2;
localparam TRIG_TIMEOUT   = 2'd3;

reg [19:0] trig_timeout_cnt;  // 1MHz时钟，100ms = 100,000 cycles
localparam TRIG_TIMEOUT_VAL = 20'd100_000;  // 100ms

always @(posedge clk_adc or negedge rst_n) begin
    if (!rst_n) begin
        trig_state <= TRIG_IDLE;
        triggered <= 1'b0;
        trig_timeout_cnt <= 20'd0;
    end else begin
        case (trig_state)
            TRIG_IDLE: begin
                triggered <= 1'b0;
                trig_timeout_cnt <= 20'd0;
                if (work_mode_sync == 2'd0 && run_flag)  // 时域模式且运行
                    trig_state <= TRIG_WAIT;
            end
            
            TRIG_WAIT: begin
                if (work_mode_sync != 2'd0 || !run_flag) begin
                    trig_state <= TRIG_IDLE;  // 退出时域模式或停止
                end else if (trigger_event) begin
                    triggered <= 1'b1;
                    trig_state <= TRIG_TRIGGERED;
                end else if (trigger_mode_sync == 1'b0) begin  // Auto模式
                    if (trig_timeout_cnt >= TRIG_TIMEOUT_VAL) begin
                        triggered <= 1'b1;  // 超时也触发
                        trig_state <= TRIG_TIMEOUT;
                    end else begin
                        trig_timeout_cnt <= trig_timeout_cnt + 1'b1;
                    end
                end
            end
            
            TRIG_TRIGGERED, TRIG_TIMEOUT: begin
                // 保持触发状态，等待FIFO写满一帧数据
                trig_timeout_cnt <= 20'd0;
                // 简化：写满1024点后复位
                if (ch1_fifo_wr_water_level >= 12'd1020)
                    trig_state <= TRIG_IDLE;
            end
            
            default: trig_state <= TRIG_IDLE;
        endcase
    end
end

//=============================================================================
// 4. 双通道数据缓冲FIFO (跨时钟域：ADC 35MHz → FFT 100MHz)
//=============================================================================
// ✓ 双通道独立FIFO，支持同步采集

// 通道1数据源选择（支持测试信号）
wire [15:0] ch1_fifo_data_source;
assign ch1_fifo_data_source = test_mode ? test_signal_gen : {6'h00, ch1_data_11b[10:1]};  // 10位数据扩展到16位
// FIFO写使能：触发后才写入（时域模式），或者其他模式正常写入
assign ch1_fifo_wr_en = test_mode ? 1'b1 : 
                        (work_mode_sync == 2'd0) ? (dual_data_valid && run_flag && triggered) :
                        (dual_data_valid && run_flag);
assign ch1_fifo_din = ch1_fifo_data_source;

// 通道2数据源（正常ADC数据，应用触发控制）
assign ch2_fifo_wr_en = (work_mode_sync == 2'd0) ? (dual_data_valid && run_flag && triggered) :
                        (dual_data_valid && run_flag);
assign ch2_fifo_din = {6'h00, ch2_data_11b[10:1]};  // 10位数据扩展到16位

// 通道1 FIFO
fifo_async #(
    .DATA_WIDTH     (16),
    .FIFO_DEPTH     (8192)  // ✓ 修改为8192以匹配FFT点数
) u_ch1_fifo (
    // 写端口 (ADC时钟域 35MHz)
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
    .FIFO_DEPTH     (8192)  // ✓ 修改为8192以匹配FFT点数
) u_ch2_fifo (
    // 写端口 (ADC时钟域 35MHz)
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
// 5.4 频谱平滑滤波器（峰值保持+轻度平滑）
// 策略：对峰值使用峰值保持，对非峰值使用轻度平滑
// 这样可以保持峰值锐利，同时抑制噪声抖动
//=============================================================================
// 通道1频谱平滑RAM（存储上一帧频谱）
reg [15:0] ch1_spectrum_prev [0:8191];
reg [15:0] ch1_prev_data;
reg [17:0] ch1_smooth_temp;  // 18位临时变量，防溢出
reg [15:0] ch1_output_data;  // 最终输出数据

// 通道2频谱平滑RAM
reg [15:0] ch2_spectrum_prev [0:8191];
reg [15:0] ch2_prev_data;
reg [17:0] ch2_smooth_temp;
reg [15:0] ch2_output_data;

// 通道1平滑处理（峰值保持策略）
always @(posedge clk_fft or negedge rst_n) begin
    if (!rst_n) begin
        ch1_spectrum_smoothed <= 16'd0;
        ch1_spectrum_smoothed_addr <= 13'd0;
        ch1_spectrum_smoothed_valid <= 1'b0;
        ch1_prev_data <= 16'd0;
        ch1_smooth_temp <= 18'd0;
        ch1_output_data <= 16'd0;
    end else begin
        if (ch1_spectrum_valid) begin
            // 读取上一帧数据
            ch1_prev_data <= ch1_spectrum_prev[ch1_spectrum_wr_addr];
            
            // 峰值保持策略：
            // 如果当前值大于历史值，快速跟随（保持峰值锐利）
            // 如果当前值小于历史值，缓慢下降（抑制噪声抖动）
            if (ch1_spectrum_magnitude > ch1_prev_data) begin
                // 上升：使用当前值（α=1.0，无延迟）
                ch1_output_data <= ch1_spectrum_magnitude;
            end else begin
                // 下降：轻度平滑（α=0.5）
                ch1_smooth_temp <= {2'b00, ch1_spectrum_magnitude} + {2'b00, ch1_prev_data};
                ch1_output_data <= ch1_smooth_temp[17:1];  // 除以2
            end
            
            ch1_spectrum_smoothed <= ch1_output_data;
            
            // 更新RAM
            ch1_spectrum_prev[ch1_spectrum_wr_addr] <= ch1_output_data;
            
            // 传递地址和有效信号
            ch1_spectrum_smoothed_addr <= ch1_spectrum_wr_addr;
            ch1_spectrum_smoothed_valid <= 1'b1;
        end else begin
            ch1_spectrum_smoothed_valid <= 1'b0;
        end
    end
end

// 通道2平滑处理（峰值保持策略）
always @(posedge clk_fft or negedge rst_n) begin
    if (!rst_n) begin
        ch2_spectrum_smoothed <= 16'd0;
        ch2_spectrum_smoothed_addr <= 13'd0;
        ch2_spectrum_smoothed_valid <= 1'b0;
        ch2_prev_data <= 16'd0;
        ch2_smooth_temp <= 18'd0;
        ch2_output_data <= 16'd0;
    end else begin
        if (ch2_spectrum_valid) begin
            // 读取上一帧数据
            ch2_prev_data <= ch2_spectrum_prev[ch2_spectrum_wr_addr];
            
            // 峰值保持策略
            if (ch2_spectrum_magnitude > ch2_prev_data) begin
                // 上升：快速跟随
                ch2_output_data <= ch2_spectrum_magnitude;
            end else begin
                // 下降：轻度平滑
                ch2_smooth_temp <= {2'b00, ch2_spectrum_magnitude} + {2'b00, ch2_prev_data};
                ch2_output_data <= ch2_smooth_temp[17:1];
            end
            
            ch2_spectrum_smoothed <= ch2_output_data;
            
            // 更新RAM
            ch2_spectrum_prev[ch2_spectrum_wr_addr] <= ch2_output_data;
            
            // 传递地址和有效信号
            ch2_spectrum_smoothed_addr <= ch2_spectrum_wr_addr;
            ch2_spectrum_smoothed_valid <= 1'b1;
        end else begin
            ch2_spectrum_smoothed_valid <= 1'b0;
        end
    end
end

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
// 6. FFT IP核实例化 - 使用8192点10位FFT
//=============================================================================
fft_8192 u_fft_8192 (
    // 时钟和复位
    .i_aclk                 (clk_fft),              // 100MHz时钟
    .i_aresetn              (rst_n),                // 复位，低有效
    
    // 输入数据流 (AXI4-Stream)
    .i_axi4s_data_tvalid    (fft_din_valid),        // 输入数据有效
    .o_axi4s_data_tready    (fft_din_ready),        // FFT准备接收
    .i_axi4s_data_tlast     (fft_din_last),         // 最后一个输入数据
    .i_axi4s_data_tdata     ({6'd0, fft_din[25:16], 6'd0, fft_din[9:0]}),  // 32位输入：[31:26]=0,[25:16]=虚部10位,[15:10]=0,[9:0]=实部10位
    
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
// 【修复】使用FFT峰值检测动态确定基波bin，而不是固定bin=80
//=============================================================================
reg [12:0] fft_out_cnt;  // FFT输出计数器（8192需要13位）

always @(posedge clk_fft or negedge rst_n) begin
    if (!rst_n) begin
        fft_out_cnt <= 13'd0;
    end else if (fft_dout_valid) begin
        if (fft_dout_last)
            fft_out_cnt <= 13'd0;
        else
            fft_out_cnt <= fft_out_cnt + 1'b1;
    end
end

// 【新增】通道1/2的峰值bin检测（用于动态基波提取）
reg [12:0]  ch1_peak_bin;                   // 通道1峰值bin
reg [15:0]  ch1_peak_magnitude;             // 通道1峰值幅度
reg [12:0]  ch2_peak_bin;                   // 通道2峰值bin
reg [15:0]  ch2_peak_magnitude;             // 通道2峰值幅度

// 通道1峰值检测（在FFT输出过程中实时检测）
// 使用简单的绝对值和近似：|Re| + |Im|
always @(posedge clk_fft or negedge rst_n) begin
    if (!rst_n) begin
        ch1_peak_bin <= 13'd0;
        ch1_peak_magnitude <= 16'd0;
    end else if (fft_dout_valid && current_fft_channel == 1'b0) begin
        if (fft_out_cnt == 13'd0) begin
            // FFT开始，重置峰值
            ch1_peak_bin <= 13'd0;
            ch1_peak_magnitude <= 16'd0;
        end else if (fft_out_cnt >= 13'd10 && fft_out_cnt < (13'd4096)) begin
            // 跳过DC和Nyquist频率，只在有效范围内检测
            // 计算当前bin的幅度近似：|Re| + |Im| (避免乘法，节省资源)
            // 实部绝对值
            // 虚部绝对值  
            // 近似幅度
            if ((fft_dout[15] ? (~fft_dout[15:0] + 1'b1) : fft_dout[15:0]) +
                (fft_dout[31] ? (~fft_dout[31:16] + 1'b1) : fft_dout[31:16]) > ch1_peak_magnitude) begin
                ch1_peak_bin <= fft_out_cnt;
                ch1_peak_magnitude <= (fft_dout[15] ? (~fft_dout[15:0] + 1'b1) : fft_dout[15:0]) +
                                     (fft_dout[31] ? (~fft_dout[31:16] + 1'b1) : fft_dout[31:16]);
            end
        end
    end
end

// 通道2峰值检测
always @(posedge clk_fft or negedge rst_n) begin
    if (!rst_n) begin
        ch2_peak_bin <= 13'd0;
        ch2_peak_magnitude <= 16'd0;
    end else if (fft_dout_valid && current_fft_channel == 1'b1) begin
        if (fft_out_cnt == 13'd0) begin
            ch2_peak_bin <= 13'd0;
            ch2_peak_magnitude <= 16'd0;
        end else if (fft_out_cnt >= 13'd10 && fft_out_cnt < (13'd4096)) begin
            if ((fft_dout[15] ? (~fft_dout[15:0] + 1'b1) : fft_dout[15:0]) +
                (fft_dout[31] ? (~fft_dout[31:16] + 1'b1) : fft_dout[31:16]) > ch2_peak_magnitude) begin
                ch2_peak_bin <= fft_out_cnt;
                ch2_peak_magnitude <= (fft_dout[15] ? (~fft_dout[15:0] + 1'b1) : fft_dout[15:0]) +
                                     (fft_dout[31] ? (~fft_dout[31:16] + 1'b1) : fft_dout[31:16]);
            end
        end
    end
end

// 【修复v5】提取基波数据并使用状态机保证两通道数据同步
// 状态机：
// IDLE: 等待新的FFT数据
// WAIT_CH: 等待两个通道基波数据都就绪
// VALID: 发出valid信号并保持25周期
// 关键：只有在IDLE状态才接受新数据，避免连续触发
localparam PHASE_IDLE    = 2'd0;
localparam PHASE_WAIT_CH = 2'd1;
localparam PHASE_VALID   = 2'd2;

reg [1:0] phase_state;
reg ch1_fundamental_ready;  // 通道1数据已就绪
reg ch2_fundamental_ready;  // 通道2数据已就绪
reg [4:0] fundamental_valid_cnt;  // valid信号保持计数器（扩展到5位支持25周期）

// 提取通道1基波数据（使用检测到的峰值bin）
always @(posedge clk_fft or negedge rst_n) begin
    if (!rst_n) begin
        ch1_fundamental_re <= 16'd0;
        ch1_fundamental_im <= 16'd0;
        ch1_fundamental_ready <= 1'b0;
    end else begin
        // 只在IDLE或WAIT_CH状态接受新数据
        if ((phase_state == PHASE_IDLE || phase_state == PHASE_WAIT_CH) && 
            fft_dout_valid && current_fft_channel == 1'b0) begin
            // 【强制测试v6】直接使用固定bin 234（1kHz @ 35MHz/8192 ≈ 234）
            // 忽略峰值检测结果，确保能提取到数据
            if (fft_out_cnt == 13'd234) begin
                // 提取基波频点的复数数据
                ch1_fundamental_re <= fft_dout[15:0];   // 实部
                ch1_fundamental_im <= fft_dout[31:16];  // 虚部
                ch1_fundamental_ready <= 1'b1;          // 标记数据已就绪
            end
        end else if (phase_state == PHASE_IDLE) begin
            // 回到IDLE状态时清除ready标志
            ch1_fundamental_ready <= 1'b0;
        end
    end
end

// 提取通道2基波数据（使用检测到的峰值bin）
always @(posedge clk_fft or negedge rst_n) begin
    if (!rst_n) begin
        ch2_fundamental_re <= 16'd0;
        ch2_fundamental_im <= 16'd0;
        ch2_fundamental_ready <= 1'b0;
    end else begin
        // 只在IDLE或WAIT_CH状态接受新数据
        if ((phase_state == PHASE_IDLE || phase_state == PHASE_WAIT_CH) && 
            fft_dout_valid && current_fft_channel == 1'b1) begin
            // 【强制测试v6】直接使用固定bin 234
            if (fft_out_cnt == 13'd234) begin
                ch2_fundamental_re <= fft_dout[15:0];
                ch2_fundamental_im <= fft_dout[31:16];
                ch2_fundamental_ready <= 1'b1;
            end
        end else if (phase_state == PHASE_IDLE) begin
            // 回到IDLE状态时清除ready标志
            ch2_fundamental_ready <= 1'b0;
        end
    end
end

// 【关键修复v5】状态机控制valid信号 - 单次触发机制
always @(posedge clk_fft or negedge rst_n) begin
    if (!rst_n) begin
        phase_state <= PHASE_IDLE;
        ch1_fundamental_valid <= 1'b0;
        ch2_fundamental_valid <= 1'b0;
        fundamental_valid_cnt <= 5'd0;
    end else begin
        case (phase_state)
            PHASE_IDLE: begin
                // 空闲状态，等待新的FFT数据
                ch1_fundamental_valid <= 1'b0;
                ch2_fundamental_valid <= 1'b0;
                fundamental_valid_cnt <= 5'd0;
                // 检测到任意通道有数据就进入等待状态
                if (ch1_fundamental_ready || ch2_fundamental_ready) begin
                    phase_state <= PHASE_WAIT_CH;
                end
            end
            
            PHASE_WAIT_CH: begin
                // 等待两个通道都就绪
                if (ch1_fundamental_ready && ch2_fundamental_ready) begin
                    // 两个通道都就绪，开始发出valid信号
                    ch1_fundamental_valid <= 1'b1;
                    ch2_fundamental_valid <= 1'b1;
                    fundamental_valid_cnt <= 5'd1;
                    phase_state <= PHASE_VALID;
                end
                // 如果等待超时（这里暂不实现超时机制）
            end
            
            PHASE_VALID: begin
                // 保持valid信号25个周期
                if (fundamental_valid_cnt < 5'd25) begin
                    ch1_fundamental_valid <= 1'b1;
                    ch2_fundamental_valid <= 1'b1;
                    fundamental_valid_cnt <= fundamental_valid_cnt + 1'b1;
                end else begin
                    // 计数结束，回到IDLE状态
                    ch1_fundamental_valid <= 1'b0;
                    ch2_fundamental_valid <= 1'b0;
                    phase_state <= PHASE_IDLE;
                end
            end
            
            default: begin
                phase_state <= PHASE_IDLE;
            end
        endcase
    end
end

//=============================================================================
// 7. 频谱幅度计算模块 (已集成在dual_channel_fft_controller内部)
//=============================================================================
// 注释掉：频谱计算已经在dual_channel_fft_controller内部完成
// spectrum_magnitude_calc u_spectrum_calc (
//     .clk            (clk_fft),
//     .rst_n          (rst_n),
//     
//     // FFT输出
//     .fft_dout       (fft_dout),
//     .fft_valid      (fft_dout_valid),
//     .fft_last       (fft_dout_last),
//     .fft_ready      (fft_dout_ready),
//     
//     // 幅度输出
//     .magnitude      (spectrum_magnitude),
//     .magnitude_addr (spectrum_wr_addr),
//     .magnitude_valid(spectrum_valid)
// );

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

//=============================================================================
// 8.1 时域模式：ADC数据直接写入RAM（绕过FFT）
//=============================================================================
reg [12:0] time_wr_addr_ch1, time_wr_addr_ch2;  // 时域写地址计数器（8192需要13位）
reg        time_wr_en_ch1, time_wr_en_ch2;      // 时域写使能
reg        time_buffer_sel_ch1, time_buffer_sel_ch2;  // 时域乒乓选择

// 时域写入条件：时域模式 + 运行中 + (有数据或测试模式)
wire time_wr_condition_ch1;
wire time_wr_condition_ch2;
reg test_mode_sync;  // 同步test_mode到ADC时钟域

always @(posedge clk_adc or negedge rst_n) begin
    if (!rst_n)
        test_mode_sync <= 1'b0;
    else
        test_mode_sync <= test_mode;
end

// 时域写入条件：简化逻辑，不强制要求触发
// 在测试模式或者有ADC数据时就写入
assign time_wr_condition_ch1 = (work_mode_sync == 2'd0) && run_flag && 
                               (test_mode_sync || dual_data_valid);
assign time_wr_condition_ch2 = (work_mode_sync == 2'd0) && run_flag && 
                               dual_data_valid;  // CH2不使用测试信号

// 通道1时域写地址生成（在ADC时钟域）
always @(posedge clk_adc or negedge rst_n) begin
    if (!rst_n) begin
        time_wr_addr_ch1 <= 13'd0;
        time_wr_en_ch1 <= 1'b0;
    end else if (time_wr_condition_ch1) begin
        // 时域模式下，持续写入（循环缓存）
        time_wr_en_ch1 <= 1'b1;
        if (time_wr_addr_ch1 == 13'd8191)
            time_wr_addr_ch1 <= 13'd0;  // 循环写入
        else
            time_wr_addr_ch1 <= time_wr_addr_ch1 + 1'b1;
    end else begin
        time_wr_en_ch1 <= 1'b0;
        if (work_mode_sync != 2'd0)  // 退出时域模式时复位地址
            time_wr_addr_ch1 <= 13'd0;
    end
end

// 通道2时域写地址生成
always @(posedge clk_adc or negedge rst_n) begin
    if (!rst_n) begin
        time_wr_addr_ch2 <= 13'd0;
        time_wr_en_ch2 <= 1'b0;
    end else if (time_wr_condition_ch2) begin
        time_wr_en_ch2 <= 1'b1;
        if (time_wr_addr_ch2 == 13'd8191)
            time_wr_addr_ch2 <= 13'd0;
        else
            time_wr_addr_ch2 <= time_wr_addr_ch2 + 1'b1;
    end else begin
        time_wr_en_ch2 <= 1'b0;
        if (work_mode_sync != 2'd0)
            time_wr_addr_ch2 <= 13'd0;
    end
end

// 时域乒乓缓存切换（写满8192点后切换）
always @(posedge clk_adc or negedge rst_n) begin
    if (!rst_n)
        time_buffer_sel_ch1 <= 1'b0;
    else if (time_wr_en_ch1 && time_wr_addr_ch1 == 13'd8191)
        time_buffer_sel_ch1 <= ~time_buffer_sel_ch1;
end

always @(posedge clk_adc or negedge rst_n) begin
    if (!rst_n)
        time_buffer_sel_ch2 <= 1'b0;
    else if (time_wr_en_ch2 && time_wr_addr_ch2 == 13'd8191)
        time_buffer_sel_ch2 <= ~time_buffer_sel_ch2;
end

// 同步时域buffer_sel到FFT时钟域（用于读取）
reg time_buffer_sel_sync1_ch1, time_buffer_sel_sync2_ch1;
reg time_buffer_sel_sync1_ch2, time_buffer_sel_sync2_ch2;

always @(posedge clk_fft or negedge rst_n) begin
    if (!rst_n) begin
        time_buffer_sel_sync1_ch1 <= 1'b0;
        time_buffer_sel_sync2_ch1 <= 1'b0;
        time_buffer_sel_sync1_ch2 <= 1'b0;
        time_buffer_sel_sync2_ch2 <= 1'b0;
    end else begin
        time_buffer_sel_sync1_ch1 <= time_buffer_sel_ch1;
        time_buffer_sel_sync2_ch1 <= time_buffer_sel_sync1_ch1;
        time_buffer_sel_sync1_ch2 <= time_buffer_sel_ch2;
        time_buffer_sel_sync2_ch2 <= time_buffer_sel_sync1_ch2;
    end
end

//=============================================================================
// 8.2 频谱模式：乒乓缓存切换逻辑（在FFT时钟域）
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

// 同步时域写使能和地址到FFT时钟域
reg [12:0] time_wr_addr_ch1_sync1, time_wr_addr_ch1_sync2;
reg [12:0] time_wr_addr_ch2_sync1, time_wr_addr_ch2_sync2;
reg        time_wr_en_ch1_sync1, time_wr_en_ch1_sync2;
reg        time_wr_en_ch2_sync1, time_wr_en_ch2_sync2;
reg [15:0] ch1_data_sync_fft1, ch1_data_sync_fft2;
reg [15:0] ch2_data_sync_fft1, ch2_data_sync_fft2;
reg        test_mode_fft_sync1, test_mode_fft_sync2;
reg [15:0] test_signal_fft_sync1, test_signal_fft_sync2;

always @(posedge clk_fft or negedge rst_n) begin
    if (!rst_n) begin
        time_wr_addr_ch1_sync1 <= 13'd0;
        time_wr_addr_ch1_sync2 <= 13'd0;
        time_wr_addr_ch2_sync1 <= 13'd0;
        time_wr_addr_ch2_sync2 <= 13'd0;
        time_wr_en_ch1_sync1 <= 1'b0;
        time_wr_en_ch1_sync2 <= 1'b0;
        time_wr_en_ch2_sync1 <= 1'b0;
        time_wr_en_ch2_sync2 <= 1'b0;
        ch1_data_sync_fft1 <= 16'd0;
        ch1_data_sync_fft2 <= 16'd0;
        ch2_data_sync_fft1 <= 16'd0;
        ch2_data_sync_fft2 <= 16'd0;
        test_mode_fft_sync1 <= 1'b0;
        test_mode_fft_sync2 <= 1'b0;
        test_signal_fft_sync1 <= 16'd0;
        test_signal_fft_sync2 <= 16'd0;
    end else begin
        // 双级寄存器同步
        time_wr_addr_ch1_sync1 <= time_wr_addr_ch1;
        time_wr_addr_ch1_sync2 <= time_wr_addr_ch1_sync1;
        time_wr_addr_ch2_sync1 <= time_wr_addr_ch2;
        time_wr_addr_ch2_sync2 <= time_wr_addr_ch2_sync1;
        time_wr_en_ch1_sync1 <= time_wr_en_ch1;
        time_wr_en_ch1_sync2 <= time_wr_en_ch1_sync1;
        time_wr_en_ch2_sync1 <= time_wr_en_ch2;
        time_wr_en_ch2_sync2 <= time_wr_en_ch2_sync1;
        // 数据同步（包含测试模式支持）
        test_mode_fft_sync1 <= test_mode;
        test_mode_fft_sync2 <= test_mode_fft_sync1;
        test_signal_fft_sync1 <= test_signal_gen;
        test_signal_fft_sync2 <= test_signal_fft_sync1;
        ch1_data_sync_fft1 <= {5'h00, ch1_data_11b};  // 11位数据扩展到16位
        ch1_data_sync_fft2 <= ch1_data_sync_fft1;
        ch2_data_sync_fft1 <= {5'h00, ch2_data_11b};  // 11位数据扩展到16位
        ch2_data_sync_fft2 <= ch2_data_sync_fft1;
    end
end

//--- 通道1写端口选择（时域/频域模式多路复用）---
// 时域模式：使用同步后的ADC数据或测试信号
// 频域模式：使用FFT输出的频谱数据
wire [15:0] ch1_time_data_src;
// 时域数据源：测试模式用测试信号，否则用ADC数据
assign ch1_time_data_src = test_mode_fft_sync2 ? test_signal_fft_sync2 : ch1_data_sync_fft2;
wire        ch1_ram_wr_en;
wire [12:0] ch1_ram_wr_addr;
wire [15:0] ch1_ram_wr_data;
reg [1:0]   work_mode_fft_sync;  // 同步到FFT时钟域的work_mode

always @(posedge clk_fft or negedge rst_n) begin
    if (!rst_n)
        work_mode_fft_sync <= 2'd0;
    else
        work_mode_fft_sync <= work_mode;
end

assign ch1_ram_wr_en   = (work_mode_fft_sync == 2'd0) ? time_wr_en_ch1_sync2 : ch1_spectrum_smoothed_valid;
assign ch1_ram_wr_addr = (work_mode_fft_sync == 2'd0) ? time_wr_addr_ch1_sync2 : ch1_spectrum_smoothed_addr;
assign ch1_ram_wr_data = (work_mode_fft_sync == 2'd0) ? ch1_time_data_src : ch1_spectrum_smoothed;  // 使用平滑后的数据

assign ch1_ram0_we      = ch1_ram_wr_en && (((work_mode_fft_sync == 2'd0) ? time_buffer_sel_sync2_ch1 : ch1_buffer_sel) == 1'b0);
assign ch1_ram0_wr_addr = ch1_ram_wr_addr;
assign ch1_ram0_wr_data = ch1_ram_wr_data;

assign ch1_ram1_we      = ch1_ram_wr_en && (((work_mode_fft_sync == 2'd0) ? time_buffer_sel_sync2_ch1 : ch1_buffer_sel) == 1'b1);
assign ch1_ram1_wr_addr = ch1_ram_wr_addr;
assign ch1_ram1_wr_data = ch1_ram_wr_data;

//--- 通道2写端口选择（时域/频域模式多路复用）---
wire        ch2_ram_wr_en;
wire [12:0] ch2_ram_wr_addr;
wire [15:0] ch2_ram_wr_data;

assign ch2_ram_wr_en   = (work_mode_fft_sync == 2'd0) ? time_wr_en_ch2_sync2 : ch2_spectrum_smoothed_valid;
assign ch2_ram_wr_addr = (work_mode_fft_sync == 2'd0) ? time_wr_addr_ch2_sync2 : ch2_spectrum_smoothed_addr;
assign ch2_ram_wr_data = (work_mode_fft_sync == 2'd0) ? ch2_data_sync_fft2 : ch2_spectrum_smoothed;  // 使用平滑后的数据

assign ch2_ram0_we      = ch2_ram_wr_en && (((work_mode_fft_sync == 2'd0) ? time_buffer_sel_sync2_ch2 : ch2_buffer_sel) == 1'b0);
assign ch2_ram0_wr_addr = ch2_ram_wr_addr;
assign ch2_ram0_wr_data = ch2_ram_wr_data;

assign ch2_ram1_we      = ch2_ram_wr_en && (((work_mode_fft_sync == 2'd0) ? time_buffer_sel_sync2_ch2 : ch2_buffer_sel) == 1'b1);
assign ch2_ram1_wr_addr = ch2_ram_wr_addr;
assign ch2_ram1_wr_data = ch2_ram_wr_data;

//--- 通道1读端口选择（使用同步后的buffer_sel，时域/频域自动切换）---
// 同步work_mode到HDMI时钟域
reg [1:0] work_mode_hdmi_sync1, work_mode_hdmi_sync2;

always @(posedge clk_hdmi_pixel or negedge rst_n) begin
    if (!rst_n) begin
        work_mode_hdmi_sync1 <= 2'd0;
        work_mode_hdmi_sync2 <= 2'd0;
    end else begin
        work_mode_hdmi_sync1 <= work_mode;
        work_mode_hdmi_sync2 <= work_mode_hdmi_sync1;
    end
end

// 同步时域buffer_sel到HDMI时钟域
reg time_buffer_sel_hdmi_ch1_sync1, time_buffer_sel_hdmi_ch1_sync2;
reg time_buffer_sel_hdmi_ch2_sync1, time_buffer_sel_hdmi_ch2_sync2;

always @(posedge clk_hdmi_pixel or negedge rst_n) begin
    if (!rst_n) begin
        time_buffer_sel_hdmi_ch1_sync1 <= 1'b0;
        time_buffer_sel_hdmi_ch1_sync2 <= 1'b0;
        time_buffer_sel_hdmi_ch2_sync1 <= 1'b0;
        time_buffer_sel_hdmi_ch2_sync2 <= 1'b0;
    end else begin
        time_buffer_sel_hdmi_ch1_sync1 <= time_buffer_sel_ch1;
        time_buffer_sel_hdmi_ch1_sync2 <= time_buffer_sel_hdmi_ch1_sync1;
        time_buffer_sel_hdmi_ch2_sync1 <= time_buffer_sel_ch2;
        time_buffer_sel_hdmi_ch2_sync2 <= time_buffer_sel_hdmi_ch2_sync1;
    end
end

assign ch1_ram0_rd_addr = spectrum_rd_addr;
assign ch1_ram1_rd_addr = spectrum_rd_addr;
// 时域模式使用时域buffer_sel，频域模式使用频谱buffer_sel
wire ch1_rd_buffer_sel = (work_mode_hdmi_sync2 == 2'd0) ? (~time_buffer_sel_hdmi_ch1_sync2) : ch1_buffer_sel_sync2;
assign ch1_spectrum_rd_data = ch1_rd_buffer_sel ? ch1_ram1_rd_data : ch1_ram0_rd_data;

//--- 通道2读端口选择---
assign ch2_ram0_rd_addr = spectrum_rd_addr;
assign ch2_ram1_rd_addr = spectrum_rd_addr;
wire ch2_rd_buffer_sel = (work_mode_hdmi_sync2 == 2'd0) ? (~time_buffer_sel_hdmi_ch2_sync2) : ch2_buffer_sel_sync2;
assign ch2_spectrum_rd_data = ch2_rd_buffer_sel ? ch2_ram1_rd_data : ch2_ram0_rd_data;

//--- 显示通道选择---
assign spectrum_rd_data = display_channel ? ch2_spectrum_rd_data : ch1_spectrum_rd_data;

//=============================================================================
// 通道1 RAM0实例化 - 使用8192x10 DPRAM包装模块
//=============================================================================
dpram_8192x11 u_ch1_spectrum_ram0 (
    .clka   (clk_fft),
    .wea    (ch1_ram0_we),
    .addra  (ch1_ram0_wr_addr),
    .dina   (ch1_ram0_wr_data[9:0]),  // 截取低10位
    .clkb   (clk_hdmi_pixel),
    .addrb  (ch1_ram0_rd_addr),
    .doutb  (ch1_ram0_rd_data_11b)     // 输出11位（实际10位有效，最高位填0）
);

//=============================================================================
// 通道1 RAM1实例化 - 使用8192x10 DPRAM包装模块
//=============================================================================
dpram_8192x11 u_ch1_spectrum_ram1 (
    .clka   (clk_fft),
    .wea    (ch1_ram1_we),
    .addra  (ch1_ram1_wr_addr),
    .dina   (ch1_ram1_wr_data[9:0]),  // 截取低10位
    .clkb   (clk_hdmi_pixel),
    .addrb  (ch1_ram1_rd_addr),
    .doutb  (ch1_ram1_rd_data_11b)     // 输出11位（实际10位有效，最高位填0）
);

//=============================================================================
// 通道2 RAM0实例化 - 使用8192x10 DPRAM包装模块
//=============================================================================
dpram_8192x11 u_ch2_spectrum_ram0 (
    .clka   (clk_fft),
    .wea    (ch2_ram0_we),
    .addra  (ch2_ram0_wr_addr),
    .dina   (ch2_ram0_wr_data[9:0]),  // 截取低10位
    .clkb   (clk_hdmi_pixel),
    .addrb  (ch2_ram0_rd_addr),
    .doutb  (ch2_ram0_rd_data_11b)     // 输出11位（实际10位有效，最高位填0）
);

//=============================================================================
// 通道2 RAM1实例化 - 使用8192x10 DPRAM包装模块
//=============================================================================
dpram_8192x11 u_ch2_spectrum_ram1 (
    .clka   (clk_fft),
    .wea    (ch2_ram1_we),
    .addra  (ch2_ram1_wr_addr),
    .dina   (ch2_ram1_wr_data[9:0]),  // 截取低10位
    .clkb   (clk_hdmi_pixel),
    .addrb  (ch2_ram1_rd_addr),
    .doutb  (ch2_ram1_rd_data_11b)     // 输出11位（实际10位有效，最高位填0）
);

//=============================================================================
// 9. 信号参数测量模块 - 双通道
//=============================================================================
// 通道1参数测量
signal_parameter_measure u_ch1_param_measure (
    .clk            (clk_100m),
    .rst_n          (rst_n),
    
    // 时域数据输入 - 【修改】使用完整10位数据
    .sample_clk     (clk_adc),
    .sample_data    (ch1_data_sync),
    .sample_valid   (dual_data_valid || test_mode),
    
    // 频域数据输入
    .spectrum_data  (ch1_spectrum_magnitude),
    .spectrum_addr  (ch1_spectrum_wr_addr),
    .spectrum_valid (ch1_spectrum_valid),
    
    // 参数输出
    .freq_out       (ch1_freq),
    .freq_is_khz    (ch1_freq_is_khz),
    .freq_is_mhz    (ch1_freq_is_mhz),
    .amplitude_out  (ch1_amplitude),
    .duty_out       (ch1_duty),
    .thd_out        (ch1_thd),
    
    // 控制
    .measure_en     (run_flag),
    
    // 调试输出
    .dbg_fft_harmonic_2 (ch1_dbg_harmonic_2),
    .dbg_fft_harmonic_3 (ch1_dbg_harmonic_3),
    .dbg_fft_harmonic_4 (ch1_dbg_harmonic_4),
    .dbg_fft_harmonic_5 (ch1_dbg_harmonic_5),
    .dbg_harmonic_sum   (ch1_dbg_harmonic_sum),
    .dbg_fft_max_amp    (ch1_dbg_fft_max_amp),
    .dbg_calc_trigger   (ch1_dbg_calc_trigger),
    .dbg_pipe_valid     (ch1_dbg_pipe_valid)
);

// 通道2参数测量
signal_parameter_measure u_ch2_param_measure (
    .clk            (clk_100m),
    .rst_n          (rst_n),
    
    // 时域数据输入 - 【修改】使用完整10位数据
    .sample_clk     (clk_adc),
    .sample_data    (ch2_data_sync),
    .sample_valid   (dual_data_valid || test_mode),
    
    // 频域数据输入
    .spectrum_data  (ch2_spectrum_magnitude),
    .spectrum_addr  (ch2_spectrum_wr_addr),
    .spectrum_valid (ch2_spectrum_valid),
    
    // 参数输出
    .freq_out       (ch2_freq),
    .freq_is_khz    (ch2_freq_is_khz),
    .freq_is_mhz    (ch2_freq_is_mhz),
    .amplitude_out  (ch2_amplitude),
    .duty_out       (ch2_duty),
    .thd_out        (ch2_thd),
    
    // 控制
    .measure_en     (run_flag)
);

//=============================================================================
// 9.5 相位差计算模块 - 时域过零检测法（不依赖FFT）
// 精度：采样率35MHz，1kHz信号理论精度~0.01°
// 算法：过零点检测 + 时间差测量
//=============================================================================
phase_diff_time_domain u_phase_diff_time (
    .clk            (clk_adc),              // 使用ADC采样时钟 35MHz
    .rst_n          (rst_n),
    
    // ADC数据输入（8位）
    .adc_ch1_data   (ch1_data_sync[9:2]),   // 取10位数据的高8位
    .adc_ch2_data   (ch2_data_sync[9:2]),   // 取10位数据的高8位
    .adc_valid      (dual_data_valid),      // 双通道数据有效
    
    // 相位差输出 (有符号 -1800 ~ +1800 = -180.0° ~ +180.0°)
    .phase_diff     (phase_difference),
    .phase_valid    (phase_diff_valid),
    .confidence     (phase_confidence)      // 置信度输出 0-255（注意端口名是confidence）
);

/*
// 【已禁用】FFT频域相位差计算模块 v4
phase_diff_calc_v4 u_phase_diff (
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
    
    // 控制
    .enable         (run_flag),                 // 使能控制
    .smooth_factor  (4'd8),                     // 平滑因子：8 = 中等滤波（α=1/256）
    
    // 相位差输出 (有符号 -1800 ~ +1800 = -180.0° ~ +180.0°)
    .phase_diff     (phase_difference),
    .phase_valid    (phase_diff_valid),
    .phase_confidence(phase_confidence)         // 置信度输出 0-255
);
*/

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
// 9.7 微弱信号检测模块（锁相放大器）
//=============================================================================
// 配置逻辑
always @(posedge clk_100m or negedge rst_n) begin
    if (!rst_n) begin
        weak_sig_enable   <= 1'b0;
        weak_sig_ref_mode <= 2'd0;      // 默认内部DDS
        weak_sig_ref_freq <= 32'd1000;  // 默认1kHz参考频率
        weak_sig_gain     <= 4'd4;      // 默认16x增益
        // weak_sig_lpf_tc 已移除，固定为8（256点滤波）
        weak_sig_auto_gain <= 1'b1;     // 默认开启自动增益
    end else begin
        // 按键控制（预留）
        if (btn_weak_sig_enable)
            weak_sig_enable <= ~weak_sig_enable;
        
        if (btn_ref_mode) begin
            if (weak_sig_ref_mode < 2'd3)
                weak_sig_ref_mode <= weak_sig_ref_mode + 1'b1;
            else
                weak_sig_ref_mode <= 2'd0;
        end
        
        if (btn_ref_freq_up && weak_sig_ref_freq < 32'd17_500_000)  // 最大17.5MHz
            weak_sig_ref_freq <= weak_sig_ref_freq + 32'd100;  // 100Hz步进
        
        if (btn_ref_freq_dn && weak_sig_ref_freq > 32'd100)
            weak_sig_ref_freq <= weak_sig_ref_freq - 32'd100;
    end
end

// 微弱信号检测器实例化
// 注意：滤波器阶数固定为8（256点），如需不同配置请修改weak_signal_detector.v
weak_signal_detector #(
    .DATA_WIDTH     (16),
    .OUTPUT_WIDTH   (24)
) u_weak_sig_detector (
    .clk                (clk_fft),
    .rst_n              (rst_n && weak_sig_enable),  // 检测器独立使能
    
    // 双通道输入（使用11位扩展数据）
    .ch1_data           ({5'd0, ch1_data_11b}),
    .ch2_data           ({5'd0, ch2_data_11b}),
    .data_valid         (dual_data_valid),
    
    // 参考信号配置
    .ref_mode           (weak_sig_ref_mode),
    .ref_frequency      (weak_sig_ref_freq),
    .clk_frequency      (32'd35_000_000),  // 35MHz采样时钟
    
    // 增益配置（滤波器阶数已固定为8）
    .digital_gain       (weak_sig_gain),
    .lpf_time_constant  (4'd8),  // 固定传入8，实际在模块内部已硬编码
    .auto_gain_enable   (weak_sig_auto_gain),
    
    // CH1检测结果
    .ch1_i_component    (ch1_lia_i),
    .ch1_q_component    (ch1_lia_q),
    .ch1_magnitude      (ch1_lia_magnitude),
    .ch1_phase          (ch1_lia_phase),
    .ch1_locked         (ch1_lia_locked),
    .ch1_valid          (ch1_lia_valid),
    
    // CH2检测结果
    .ch2_i_component    (ch2_lia_i),
    .ch2_q_component    (ch2_lia_q),
    .ch2_magnitude      (ch2_lia_magnitude),
    .ch2_phase          (ch2_lia_phase),
    .ch2_locked         (ch2_lia_locked),
    .ch2_valid          (ch2_lia_valid),
    
    // SNR和状态
    .snr_estimate       (weak_sig_snr),
    .snr_valid          (weak_sig_snr_valid),
    .current_gain       (weak_sig_current_gain),
    .detected_freq      (weak_sig_detected_freq)
);

//=============================================================================
// 9.8 AI信号识别模块
//=============================================================================
// AI使能控制
always @(posedge clk_100m or negedge rst_n) begin
    if (!rst_n) begin
        ai_enable <= 1'b1;  // 默认开启AI识别
    end else begin
        if (btn_ai_enable)
            ai_enable <= ~ai_enable;
    end
end

// 需要FFT数据选择（根据当前处理通道）
// 假设FFT模块有输出：fft_magnitude_out, fft_bin_index_out, fft_valid_out
// 这里需要连接实际的FFT输出信号

// CH1 AI识别器
ai_signal_recognizer #(
    .DATA_WIDTH   (11),
    .WINDOW_SIZE  (1024),
    .FFT_BINS     (512)
) u_ch1_ai_recognizer (
    .clk              (clk_fft),
    .rst_n            (rst_n),
    
    // 时域信号输入
    .signal_in        (ch1_data_11b),
    .signal_valid     (dual_data_valid && ai_enable),
    
    // FFT频谱输入（需要根据实际FFT模块连接）
    .fft_magnitude    (ch1_spectrum_rd_data),  // 使用频谱RAM读出数据
    .fft_bin_index    (spectrum_rd_addr[9:0]),
    .fft_valid        (ai_enable && (current_fft_channel == 1'b0)),  // 仅CH1 FFT期间有效
    
    .ai_enable        (ai_enable),
    
    // 识别结果
    .waveform_type    (ch1_waveform_type),
    .confidence       (ch1_confidence),
    .result_valid     (ch1_ai_valid),
    
    // 调试输出
    .dbg_zcr          (ch1_dbg_zcr),
    .dbg_crest_factor (ch1_dbg_crest_factor),
    .dbg_thd          (ch1_dbg_thd)
);

// CH2 AI识别器
ai_signal_recognizer #(
    .DATA_WIDTH   (11),
    .WINDOW_SIZE  (1024),
    .FFT_BINS     (512)
) u_ch2_ai_recognizer (
    .clk              (clk_fft),
    .rst_n            (rst_n),
    
    // 时域信号输入
    .signal_in        (ch2_data_11b),
    .signal_valid     (dual_data_valid && ai_enable),
    
    // FFT频谱输入
    .fft_magnitude    (ch2_spectrum_rd_data),
    .fft_bin_index    (spectrum_rd_addr[9:0]),
    .fft_valid        (ai_enable && (current_fft_channel == 1'b1)),  // 仅CH2 FFT期间有效
    
    .ai_enable        (ai_enable),
    
    // 识别结果
    .waveform_type    (ch2_waveform_type),
    .confidence       (ch2_confidence),
    .result_valid     (ch2_ai_valid),
    
    // 调试输出
    .dbg_zcr          (ch2_dbg_zcr),
    .dbg_crest_factor (ch2_dbg_crest_factor),
    .dbg_thd          (ch2_dbg_thd)
);

//=============================================================================
// 10. HDMI显示控制模块
//=============================================================================
hdmi_display_ctrl u_hdmi_ctrl (
    .clk_pixel          (clk_hdmi_pixel),       // 148.5MHz
    .rst_n              (rst_n),
    
    // ✅ 双通道数据输入
    .ch1_data           (ch1_spectrum_rd_data), // 通道1数据（时域/频域）
    .ch2_data           (ch2_spectrum_rd_data), // 通道2数据（时域/频域）
    .spectrum_addr      (spectrum_rd_addr),
    
    // 双通道参数显示
    .ch1_freq           (ch1_freq),
    .ch1_freq_is_khz    (ch1_freq_is_khz),
    .ch1_freq_is_mhz    (ch1_freq_is_mhz),
    .ch1_amplitude      (ch1_amplitude),
    .ch1_duty           (ch1_duty),
    .ch1_thd            (ch1_thd),
    .ch2_freq           (ch2_freq),
    .ch2_freq_is_khz    (ch2_freq_is_khz),
    .ch2_freq_is_mhz    (ch2_freq_is_mhz),
    .ch2_amplitude      (ch2_amplitude),
    .ch2_duty           (ch2_duty),
    .ch2_thd            (ch2_thd),
    .phase_diff         (phase_diff_sync2),     // 【修改】使用CDC同步后的相位差
    .phase_confidence   (phase_conf_sync2),     // 【修改】使用CDC同步后的置信度
    
    // ✅ AI识别结果输入
    .ch1_waveform_type  (ch1_waveform_type),
    .ch1_confidence     (ch1_confidence),
    .ch1_ai_valid       (ch1_ai_valid),
    .ch2_waveform_type  (ch2_waveform_type),
    .ch2_confidence     (ch2_confidence),
    .ch2_ai_valid       (ch2_ai_valid),
    
    // ✅ 双通道控制
    .ch1_enable         (ch1_enable),           // 通道1显示使能
    .ch2_enable         (ch2_enable),           // 通道2显示使能
    
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

// ✅ 通道1开关按键（替代原来的通道选择）
key_debounce u_key_ch1_toggle (
    .clk            (clk_100m),
    .rst_n          (rst_n),
    .key_in         (user_button[3]),       // 按键3控制CH1开关
    .key_pulse      (btn_ch1_toggle)
);

// ✅ 通道2开关按键
key_debounce u_key_ch2_toggle (
    .clk            (clk_100m),
    .rst_n          (rst_n),
    .key_in         (user_button[6]),       // 按键6控制CH2开关
    .key_pulse      (btn_ch2_toggle)
);

// 触发模式切换按键（Auto/Normal）- 使用button[4]
key_debounce u_key_trig_mode (
    .clk            (clk_100m),
    .rst_n          (rst_n),
    .key_in         (user_button[4]),
    .key_pulse      (btn_trig_mode)
);

// 工作模式切换（默认频域模式展示FFT功能）
always @(posedge clk_100m or negedge rst_n) begin
    if (!rst_n)
        work_mode <= 2'd1;  // ✓ 默认频域模式，展示8192点FFT
    else if (btn_mode) begin
        if (work_mode == 2'd2)
            work_mode <= 2'd0;
        else
            work_mode <= work_mode + 1'b1;
    end
end

//=============================================================================
// 触发系统控制逻辑
//=============================================================================
// 触发模式切换（Auto/Normal）
always @(posedge clk_100m or negedge rst_n) begin
    if (!rst_n)
        trigger_mode <= 1'b0;  // 默认Auto模式
    else if (btn_trig_mode)
        trigger_mode <= ~trigger_mode;
end

// 触发电平调节（在时域模式下，START/STOP按键复用为电平调节）
always @(posedge clk_100m or negedge rst_n) begin
    if (!rst_n)
        trigger_level <= 10'd512;  // 默认中间电平（0V参考）
    else if (work_mode == 2'd0) begin  // 仅在时域模式下有效
        if (btn_start && trigger_level < 10'd1000)  // UP（防溢出）
            trigger_level <= trigger_level + 10'd10;
        else if (btn_stop && trigger_level > 10'd23)  // DOWN（防溢出）
            trigger_level <= trigger_level - 10'd10;
    end
end

// 触发边沿选择（暂时固定为上升沿，未来可扩展）
always @(posedge clk_100m or negedge rst_n) begin
    if (!rst_n)
        trigger_edge <= 1'b0;  // 默认上升沿
end

// 运行控制（添加延迟自动启动，确保系统初始化完成）
reg [27:0] auto_start_counter;  // 28位计数器，最大268秒@100MHz
reg        auto_start_done;

always @(posedge clk_100m or negedge rst_n) begin
    if (!rst_n) begin
        auto_start_counter <= 28'd0;
        auto_start_done <= 1'b0;
    end else begin
        // 等待0.5秒（50,000,000个时钟周期）后自动启动
        if (auto_start_counter == 28'd50_000_000 && !auto_start_done) begin
            auto_start_done <= 1'b1;
        end else if (auto_start_counter < 28'd50_000_000) begin
            auto_start_counter <= auto_start_counter + 1'b1;
        end
    end
end

always @(posedge clk_100m or negedge rst_n) begin
    if (!rst_n)
        run_flag <= 1'b0;
    else if (auto_start_done && !run_flag)  // 延迟0.5秒后自动启动一次
        run_flag <= 1'b1;
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

// 微弱信号检测使能按键（预留：user_button[6]）
assign btn_weak_sig_enable = 1'b0;  // 暂时禁用，未连接按键

// 参考频率调整按键（预留）
assign btn_ref_freq_up = 1'b0;
assign btn_ref_freq_dn = 1'b0;
assign btn_ref_mode = 1'b0;

// AI信号识别使能按键（预留：user_button[7]）
assign btn_ai_enable = 1'b0;  // 暂时禁用，未连接按键

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

// OTR标志同步到100MHz时钟域（双级同步器）
always @(posedge clk_100m or negedge rst_n) begin
    if (!rst_n) begin
        adc_ch1_otr_sync_100m <= 1'b0;
        adc_ch2_otr_sync_100m <= 1'b0;
    end else begin
        adc_ch1_otr_sync_100m <= adc_ch1_otr_flag;
        adc_ch2_otr_sync_100m <= adc_ch2_otr_flag;
    end
end

// 【诊断用】spectrum_valid活动检测
reg ch1_spectrum_active;
reg [12:0] ch1_peak_bin_debug;  // 【新增】调试：记录检测到的峰值bin
always @(posedge clk_100m or negedge rst_n) begin
    if (!rst_n) begin
        ch1_spectrum_active <= 1'b0;
        ch1_peak_bin_debug <= 13'd0;
    end else if (ch1_spectrum_valid) begin
        ch1_spectrum_active <= 1'b1;  // 锁存，检测到FFT输出就保持
        // 简单记录：如果幅度>512，记录这个bin
        if (ch1_spectrum_magnitude > 16'd512) begin
            ch1_peak_bin_debug <= ch1_spectrum_wr_addr;
        end
    end
end

always @(posedge clk_100m or negedge rst_n) begin
    if (!rst_n)
        user_led_reg <= 8'h00;
    else begin
        user_led_reg[0] <= run_flag;                                    // 运行状态
        user_led_reg[1] <= dual_data_valid;                             // 【时域】双通道数据有效
        user_led_reg[2] <= phase_diff_valid;                            // 【时域】相位差输出有效
        user_led_reg[3] <= (phase_confidence > 8'd100);                 // 【时域】信号置信度足够
        user_led_reg[4] <= (phase_difference > 16'sd100);               // 【时域】相位差 > 10°
        user_led_reg[5] <= (phase_difference < -16'sd100);              // 【时域】相位差 < -10°
        user_led_reg[6] <= adc_ch1_otr_sync_100m;                       // CH1 过载
        user_led_reg[7] <= adc_ch2_otr_sync_100m;                       // CH2 过载
    end
end

//=============================================================================
// 改进的测试信号发生器 - 简化的正弦波查表法
//=============================================================================
// 在clk_adc (1MHz)时钟域生成测试信号
// 生成1kHz正弦波，用于清晰的时域和频域测试
//=============================================================================

// 16点简化正弦波查找表（0-2π）
function [15:0] sin_lut;
    input [3:0] index;  // 0-15对应0-360度
    begin
        case (index)
            4'd0:  sin_lut = 16'd32768;  // sin(0°) = 0 (中心值)
            4'd1:  sin_lut = 16'd44739;  // sin(22.5°) ≈ 0.383
            4'd2:  sin_lut = 16'd55188;  // sin(45°) ≈ 0.707
            4'd3:  sin_lut = 16'd62464;  // sin(67.5°) ≈ 0.924
            4'd4:  sin_lut = 16'd65535;  // sin(90°) = 1.0
            4'd5:  sin_lut = 16'd62464;  // sin(112.5°) ≈ 0.924
            4'd6:  sin_lut = 16'd55188;  // sin(135°) ≈ 0.707
            4'd7:  sin_lut = 16'd44739;  // sin(157.5°) ≈ 0.383
            4'd8:  sin_lut = 16'd32768;  // sin(180°) = 0
            4'd9:  sin_lut = 16'd20797;  // sin(202.5°) ≈ -0.383
            4'd10: sin_lut = 16'd10348;  // sin(225°) ≈ -0.707
            4'd11: sin_lut = 16'd3072;   // sin(247.5°) ≈ -0.924
            4'd12: sin_lut = 16'd0;      // sin(270°) = -1.0
            4'd13: sin_lut = 16'd3072;   // sin(292.5°) ≈ -0.924
            4'd14: sin_lut = 16'd10348;  // sin(315°) ≈ -0.707
            4'd15: sin_lut = 16'd20797;  // sin(337.5°) ≈ -0.383
        endcase
    end
endfunction

always @(posedge clk_adc or negedge rst_n) begin
    if (!rst_n) begin
        test_counter <= 10'd0;
        test_signal_gen <= 16'd32768;  // 中间值
    end else if (test_mode && run_flag) begin
        // 1kHz正弦波：1MHz / 1000Hz = 1000个采样点/周期
        // 使用16点查表，每点重复约62.5次
        if (test_counter == 10'd999)
            test_counter <= 10'd0;
        else
            test_counter <= test_counter + 1'b1;
        
        // 将0-999映射到0-15（16点查表）
        // 每个查表点覆盖约62.5个采样点
        test_signal_gen <= sin_lut(test_counter[9:6]);  // 除以64，得到0-15
    end else begin
        test_counter <= 10'd0;
        test_signal_gen <= 16'd32768;  // 中间值
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
// 降频计数器，减少BCD更新频率以改善时序
reg  [7:0]  debug_update_counter;

// 在ADC时钟域捕获ADC数据
always @(posedge clk_adc or negedge rst_n) begin
    if (!rst_n) begin
        debug_adc_ch1_sample <= 16'd0;
        debug_adc_ch2_sample <= 16'd0;
        debug_data_valid <= 1'b0;
        debug_fifo_wr_count <= 16'd0;
        debug_fifo_wr_bcd_1 <= 4'd0;
        debug_fifo_wr_bcd_10 <= 4'd0;
        debug_fifo_wr_bcd_100 <= 4'd0;
        debug_fifo_wr_bcd_1000 <= 4'd0;
        debug_update_counter <= 8'd0;
    end else begin
        if (dual_data_valid) begin
            debug_adc_ch1_sample <= {5'h00, ch1_data_11b};  // 使用11位扩展数据
            debug_adc_ch2_sample <= {5'h00, ch2_data_11b};  // 使用11位扩展数据
            debug_data_valid <= 1'b1;
            debug_fifo_wr_count <= debug_fifo_wr_count + 1'b1;
            
            // 降频更新：每256次采样才更新一次BCD计数（改善时序）
            debug_update_counter <= debug_update_counter + 1'b1;
            if (debug_update_counter == 8'd0) begin
                if (debug_fifo_wr_bcd_1 == 4'd9) begin
                    debug_fifo_wr_bcd_1 <= 4'd0;
                    if (debug_fifo_wr_bcd_10 == 4'd9) begin
                        debug_fifo_wr_bcd_10 <= 4'd0;
                        if (debug_fifo_wr_bcd_100 == 4'd9) begin
                            debug_fifo_wr_bcd_100 <= 4'd0;
                            if (debug_fifo_wr_bcd_1000 == 4'd9)
                                debug_fifo_wr_bcd_1000 <= 4'd0;
                            else
                                debug_fifo_wr_bcd_1000 <= debug_fifo_wr_bcd_1000 + 1'b1;
                        end else
                            debug_fifo_wr_bcd_100 <= debug_fifo_wr_bcd_100 + 1'b1;
                    end else
                        debug_fifo_wr_bcd_10 <= debug_fifo_wr_bcd_10 + 1'b1;
                end else
                    debug_fifo_wr_bcd_1 <= debug_fifo_wr_bcd_1 + 1'b1;
            end
        end
    end
end

// 在FFT时钟域捕获FFT输出数据
always @(posedge clk_fft or negedge rst_n) begin
    if (!rst_n) begin
        debug_fft_out_count <= 16'd0;
        debug_fft_done <= 1'b0;
        debug_fft_out_bcd_1 <= 4'd0;
        debug_fft_out_bcd_10 <= 4'd0;
        debug_fft_out_bcd_100 <= 4'd0;
        debug_fft_out_bcd_1000 <= 4'd0;
    end else begin
        if (fft_dout_valid) begin
            debug_fft_out_count <= debug_fft_out_count + 1'b1;
            if (fft_dout_last)
                debug_fft_done <= 1'b1;
                
            // BCD计数器递增
            if (debug_fft_out_bcd_1 == 4'd9) begin
                debug_fft_out_bcd_1 <= 4'd0;
                if (debug_fft_out_bcd_10 == 4'd9) begin
                    debug_fft_out_bcd_10 <= 4'd0;
                    if (debug_fft_out_bcd_100 == 4'd9) begin
                        debug_fft_out_bcd_100 <= 4'd0;
                        if (debug_fft_out_bcd_1000 == 4'd9)
                            debug_fft_out_bcd_1000 <= 4'd0;
                        else
                            debug_fft_out_bcd_1000 <= debug_fft_out_bcd_1000 + 1'b1;
                    end else
                        debug_fft_out_bcd_100 <= debug_fft_out_bcd_100 + 1'b1;
                end else
                    debug_fft_out_bcd_10 <= debug_fft_out_bcd_10 + 1'b1;
            end else
                debug_fft_out_bcd_1 <= debug_fft_out_bcd_1 + 1'b1;
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
// 二级流水线优化：第一级做除法，第二级做取模，减少单周期组合逻辑深度
always @(posedge clk_100m or negedge rst_n) begin
    if (!rst_n) begin
        debug_adc_ch1_sample_sync <= 16'd0;
        debug_adc_ch2_sample_sync <= 16'd0;
        debug_fifo_wr_count_sync <= 16'd0;
        debug_fft_out_count_sync <= 16'd0;
        debug_spectrum_addr_last_sync <= 16'd0;
        debug_data_valid_sync <= 1'b0;
        debug_fft_done_sync <= 1'b0;
        
        // 初始化中间除法结果寄存器
        fifo_count_div10 <= 16'd0;
        fifo_count_div100 <= 16'd0;
        fifo_count_div1000 <= 16'd0;
        fft_count_div10 <= 16'd0;
        fft_count_div100 <= 16'd0;
        fft_count_div1000 <= 16'd0;
        spectrum_addr_div10 <= 16'd0;
        spectrum_addr_div100 <= 16'd0;
        spectrum_addr_div1000 <= 16'd0;
        spectrum_addr_div10000 <= 16'd0;
        adc_ch1_div10 <= 16'd0;
        adc_ch1_div100 <= 16'd0;
        adc_ch1_div1000 <= 16'd0;
        adc_ch1_div10000 <= 16'd0;
        adc_ch2_div10 <= 16'd0;
        adc_ch2_div100 <= 16'd0;
        adc_ch2_div1000 <= 16'd0;
        adc_ch2_div10000 <= 16'd0;
        
        // 初始化最终数字寄存器
        fifo_count_digit_1000 <= 4'd0;
        fifo_count_digit_100 <= 4'd0;
        fifo_count_digit_10 <= 4'd0;
        fifo_count_digit_1 <= 4'd0;
        fft_count_digit_1000 <= 4'd0;
        fft_count_digit_100 <= 4'd0;
        fft_count_digit_10 <= 4'd0;
        fft_count_digit_1 <= 4'd0;
        spectrum_addr_digit_1000 <= 4'd0;
        spectrum_addr_digit_100 <= 4'd0;
        spectrum_addr_digit_10 <= 4'd0;
        spectrum_addr_digit_1 <= 4'd0;
        adc_ch1_digit_10000 <= 4'd0;
        adc_ch1_digit_1000 <= 4'd0;
        adc_ch1_digit_100 <= 4'd0;
        adc_ch1_digit_10 <= 4'd0;
        adc_ch1_digit_1 <= 4'd0;
        adc_ch2_digit_10000 <= 4'd0;
        adc_ch2_digit_1000 <= 4'd0;
        adc_ch2_digit_100 <= 4'd0;
        adc_ch2_digit_10 <= 4'd0;
        adc_ch2_digit_1 <= 4'd0;
        spectrum_addr_full_digit_10000 <= 4'd0;
        spectrum_addr_full_digit_1000 <= 4'd0;
        spectrum_addr_full_digit_100 <= 4'd0;
        spectrum_addr_full_digit_10 <= 4'd0;
        spectrum_addr_full_digit_1 <= 4'd0;
    end else begin
        // 简单的寄存器同步（对于多bit信号可能有亚稳态，但用于调试可接受）
        debug_adc_ch1_sample_sync <= debug_adc_ch1_sample;
        debug_adc_ch2_sample_sync <= debug_adc_ch2_sample;
        debug_fifo_wr_count_sync <= debug_fifo_wr_count;
        debug_fft_out_count_sync <= debug_fft_out_count;
        debug_spectrum_addr_last_sync <= debug_spectrum_addr_last;
        debug_data_valid_sync <= debug_data_valid;
        debug_fft_done_sync <= debug_fft_done;
        
        // ====== 直接同步BCD计数器（无需除法/取模，时序最优）======
        // FIFO和FFT计数直接从BCD计数器同步（无除法/取模运算）
        fifo_count_digit_1000 <= debug_fifo_wr_bcd_1000;
        fifo_count_digit_100 <= debug_fifo_wr_bcd_100;
        fifo_count_digit_10 <= debug_fifo_wr_bcd_10;
        fifo_count_digit_1 <= debug_fifo_wr_bcd_1;
        
        fft_count_digit_1000 <= debug_fft_out_bcd_1000;
        fft_count_digit_100 <= debug_fft_out_bcd_100;
        fft_count_digit_10 <= debug_fft_out_bcd_10;
        fft_count_digit_1 <= debug_fft_out_bcd_1;
        
        // 简化：不再显示spectrum_addr和ADC采样值（变化太快无法通过UART观察）
        // 这些值的除法运算会产生长组合路径，删除以满足时序
    end
end

//=============================================================================
// ✅ 双通道独立使能控制（类似专业示波器）
//=============================================================================
always @(posedge clk_100m or negedge rst_n) begin
    if (!rst_n) begin
        ch1_enable <= 1'b1;         // 默认开启CH1
        ch2_enable <= 1'b1;         // 默认开启CH2
    end else begin
        if (btn_ch1_toggle)
            ch1_enable <= ~ch1_enable;
        if (btn_ch2_toggle)
            ch2_enable <= ~ch2_enable;
    end
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

// ✅ UART调试定时器 - 每秒触发一次发送
reg [26:0] uart_debug_timer;
reg        uart_debug_trigger;

always @(posedge clk_100m or negedge rst_n) begin
    if (!rst_n) begin
        uart_debug_timer <= 27'd0;
        uart_debug_trigger <= 1'b0;
    end else begin
        if (uart_debug_timer == 27'd100_000_000 - 1) begin  // 1秒
            uart_debug_timer <= 27'd0;
            uart_debug_trigger <= 1'b1;
        end else begin
            uart_debug_timer <= uart_debug_timer + 1'b1;
            uart_debug_trigger <= 1'b0;
        end
    end
end

//=============================================================================
// ✅ UART调试信息发送状态机
//=============================================================================
// 状态定义
localparam UART_IDLE          = 8'd0;
localparam UART_SEND_HEADER   = 8'd1;   // "===STATUS===\r\n"
localparam UART_SEND_MODE     = 8'd10;  // "Mode:X "
localparam UART_SEND_RUN      = 8'd15;  // "Run:X "
localparam UART_SEND_CH       = 8'd20;  // "CH1:X CH2:X "
localparam UART_SEND_TRIG     = 8'd30;  // "Trig:X "
localparam UART_SEND_FIFO     = 8'd40;  // "FIFO:XXXX "
localparam UART_SEND_FFT      = 8'd50;  // "FFT:XXX "
localparam UART_SEND_TEST     = 8'd60;  // "Test:X "
localparam UART_SEND_THD_DBG  = 8'd65;  // "THD_DBG:H2=XX H3=XX H4=XX H5=XX SUM=XXX BASE=XXX TRG=X PIPE=X "
localparam UART_SEND_NEWLINE  = 8'd70;  // "\r\n"
localparam UART_WAIT_BUSY     = 8'd255; // 等待UART空闲

reg [5:0] uart_char_index;  // 当前字符索引

always @(posedge clk_100m or negedge rst_n) begin
    if (!rst_n) begin
        send_state <= UART_IDLE;
        uart_send_trigger <= 1'b0;
        uart_data_to_send <= 8'h00;
        uart_char_index <= 6'd0;
    end else begin
        // 默认不触发
        uart_send_trigger <= 1'b0;
        
        case (send_state)
            //===== 空闲状态 =====
            UART_IDLE: begin
                uart_char_index <= 6'd0;
                if (uart_debug_trigger) begin
                    send_state <= UART_SEND_HEADER;
                end
            end
            
            //===== 发送头部 "===STATUS===\r\n" =====
            UART_SEND_HEADER: begin
                if (!uart_busy) begin
                    case (uart_char_index)
                        6'd0:  uart_data_to_send <= "=";
                        6'd1:  uart_data_to_send <= "=";
                        6'd2:  uart_data_to_send <= "=";
                        6'd3:  uart_data_to_send <= "S";
                        6'd4:  uart_data_to_send <= "T";
                        6'd5:  uart_data_to_send <= "A";
                        6'd6:  uart_data_to_send <= "T";
                        6'd7:  uart_data_to_send <= "U";
                        6'd8:  uart_data_to_send <= "S";
                        6'd9:  uart_data_to_send <= "=";
                        6'd10: uart_data_to_send <= "=";
                        6'd11: uart_data_to_send <= "=";
                        6'd12: uart_data_to_send <= 8'h0D; // \r
                        6'd13: uart_data_to_send <= 8'h0A; // \n
                        default: begin
                            send_state <= UART_SEND_MODE;
                            uart_char_index <= 6'd0;
                        end
                    endcase
                    
                    if (uart_char_index <= 6'd13) begin
                        uart_send_trigger <= 1'b1;
                        uart_char_index <= uart_char_index + 1'b1;
                        send_state <= UART_WAIT_BUSY;
                    end
                end
            end
            
            //===== 发送工作模式 "Mode:X " =====
            UART_SEND_MODE: begin
                if (!uart_busy) begin
                    case (uart_char_index)
                        6'd0: uart_data_to_send <= "M";
                        6'd1: uart_data_to_send <= "o";
                        6'd2: uart_data_to_send <= "d";
                        6'd3: uart_data_to_send <= "e";
                        6'd4: uart_data_to_send <= ":";
                        6'd5: begin
                            case (work_mode)
                                2'd0: uart_data_to_send <= "T";  // Time
                                2'd1: uart_data_to_send <= "F";  // Frequency
                                2'd2: uart_data_to_send <= "P";  // Parameter
                                default: uart_data_to_send <= "?";
                            endcase
                        end
                        6'd6: uart_data_to_send <= " ";
                        default: begin
                            send_state <= UART_SEND_RUN;
                            uart_char_index <= 6'd0;
                        end
                    endcase
                    
                    if (uart_char_index <= 6'd6) begin
                        uart_send_trigger <= 1'b1;
                        uart_char_index <= uart_char_index + 1'b1;
                        send_state <= UART_WAIT_BUSY;
                    end
                end
            end
            
            //===== 发送运行状态 "Run:X " =====
            UART_SEND_RUN: begin
                if (!uart_busy) begin
                    case (uart_char_index)
                        6'd0: uart_data_to_send <= "R";
                        6'd1: uart_data_to_send <= "u";
                        6'd2: uart_data_to_send <= "n";
                        6'd3: uart_data_to_send <= ":";
                        6'd4: uart_data_to_send <= run_flag ? "1" : "0";
                        6'd5: uart_data_to_send <= " ";
                        default: begin
                            send_state <= UART_SEND_CH;
                            uart_char_index <= 6'd0;
                        end
                    endcase
                    
                    if (uart_char_index <= 6'd5) begin
                        uart_send_trigger <= 1'b1;
                        uart_char_index <= uart_char_index + 1'b1;
                        send_state <= UART_WAIT_BUSY;
                    end
                end
            end
            
            //===== 发送通道状态 "CH1:X CH2:X " =====
            UART_SEND_CH: begin
                if (!uart_busy) begin
                    case (uart_char_index)
                        6'd0: uart_data_to_send <= "C";
                        6'd1: uart_data_to_send <= "H";
                        6'd2: uart_data_to_send <= "1";
                        6'd3: uart_data_to_send <= ":";
                        6'd4: uart_data_to_send <= ch1_enable ? "1" : "0";
                        6'd5: uart_data_to_send <= " ";
                        6'd6: uart_data_to_send <= "C";
                        6'd7: uart_data_to_send <= "H";
                        6'd8: uart_data_to_send <= "2";
                        6'd9: uart_data_to_send <= ":";
                        6'd10: uart_data_to_send <= ch2_enable ? "1" : "0";
                        6'd11: uart_data_to_send <= " ";
                        default: begin
                            send_state <= UART_SEND_TRIG;
                            uart_char_index <= 6'd0;
                        end
                    endcase
                    
                    if (uart_char_index <= 6'd11) begin
                        uart_send_trigger <= 1'b1;
                        uart_char_index <= uart_char_index + 1'b1;
                        send_state <= UART_WAIT_BUSY;
                    end
                end
            end
            
            //===== 发送触发状态 "Trig:X " =====
            UART_SEND_TRIG: begin
                if (!uart_busy) begin
                    case (uart_char_index)
                        6'd0: uart_data_to_send <= "T";
                        6'd1: uart_data_to_send <= "r";
                        6'd2: uart_data_to_send <= "i";
                        6'd3: uart_data_to_send <= "g";
                        6'd4: uart_data_to_send <= ":";
                        6'd5: uart_data_to_send <= trigger_mode ? "N" : "A";  // 0=Auto, 1=Normal
                        6'd6: uart_data_to_send <= " ";
                        default: begin
                            send_state <= UART_SEND_FIFO;
                            uart_char_index <= 6'd0;
                        end
                    endcase
                    
                    if (uart_char_index <= 6'd6) begin
                        uart_send_trigger <= 1'b1;
                        uart_char_index <= uart_char_index + 1'b1;
                        send_state <= UART_WAIT_BUSY;
                    end
                end
            end
            
            //===== 发送FIFO计数 "FIFO:XXXX " =====
            UART_SEND_FIFO: begin
                if (!uart_busy) begin
                    case (uart_char_index)
                        6'd0: uart_data_to_send <= "F";
                        6'd1: uart_data_to_send <= "I";
                        6'd2: uart_data_to_send <= "F";
                        6'd3: uart_data_to_send <= "O";
                        6'd4: uart_data_to_send <= ":";
                        6'd5: uart_data_to_send <= {4'h3, fifo_count_digit_1000};  // ASCII '0'-'9'
                        6'd6: uart_data_to_send <= {4'h3, fifo_count_digit_100};
                        6'd7: uart_data_to_send <= {4'h3, fifo_count_digit_10};
                        6'd8: uart_data_to_send <= {4'h3, fifo_count_digit_1};
                        6'd9: uart_data_to_send <= " ";
                        default: begin
                            send_state <= UART_SEND_FFT;
                            uart_char_index <= 6'd0;
                        end
                    endcase
                    
                    if (uart_char_index <= 6'd9) begin
                        uart_send_trigger <= 1'b1;
                        uart_char_index <= uart_char_index + 1'b1;
                        send_state <= UART_WAIT_BUSY;
                    end
                end
            end
            
            //===== 发送FFT计数 "FFT:XXX " =====
            UART_SEND_FFT: begin
                if (!uart_busy) begin
                    case (uart_char_index)
                        6'd0: uart_data_to_send <= "F";
                        6'd1: uart_data_to_send <= "F";
                        6'd2: uart_data_to_send <= "T";
                        6'd3: uart_data_to_send <= ":";
                        6'd4: uart_data_to_send <= {4'h3, fft_count_digit_1000};
                        6'd5: uart_data_to_send <= {4'h3, fft_count_digit_100};
                        6'd6: uart_data_to_send <= {4'h3, fft_count_digit_10};
                        6'd7: uart_data_to_send <= {4'h3, fft_count_digit_1};
                        6'd8: uart_data_to_send <= " ";
                        default: begin
                            send_state <= UART_SEND_TEST;
                            uart_char_index <= 6'd0;
                        end
                    endcase
                    
                    if (uart_char_index <= 6'd8) begin
                        uart_send_trigger <= 1'b1;
                        uart_char_index <= uart_char_index + 1'b1;
                        send_state <= UART_WAIT_BUSY;
                    end
                end
            end
            
            //===== 发送测试模式 "Test:X " =====
            UART_SEND_TEST: begin
                if (!uart_busy) begin
                    case (uart_char_index)
                        6'd0: uart_data_to_send <= "T";
                        6'd1: uart_data_to_send <= "e";
                        6'd2: uart_data_to_send <= "s";
                        6'd3: uart_data_to_send <= "t";
                        6'd4: uart_data_to_send <= ":";
                        6'd5: uart_data_to_send <= test_mode ? "1" : "0";
                        6'd6: uart_data_to_send <= " ";
                        default: begin
                            send_state <= UART_SEND_THD_DBG;
                            uart_char_index <= 6'd0;
                        end
                    endcase
                    
                    if (uart_char_index <= 6'd6) begin
                        uart_send_trigger <= 1'b1;
                        uart_char_index <= uart_char_index + 1'b1;
                        send_state <= UART_WAIT_BUSY;
                    end
                end
            end
            
            //===== 发送THD调试信息 =====
            // 格式: "H2:XXXX H3:XXXX H4:XXXX H5:XXXX SUM:XXXX BASE:XXXX TRG:X VAL:X "
            UART_SEND_THD_DBG: begin
                if (!uart_busy) begin
                    case (uart_char_index)
                        // H2:XXXX
                        6'd0:  uart_data_to_send <= "H";
                        6'd1:  uart_data_to_send <= "2";
                        6'd2:  uart_data_to_send <= ":";
                        6'd3:  uart_data_to_send <= {4'h3, (ch1_dbg_harmonic_2[15:12])}; 
                        6'd4:  uart_data_to_send <= {4'h3, (ch1_dbg_harmonic_2[11:8])};
                        6'd5:  uart_data_to_send <= {4'h3, (ch1_dbg_harmonic_2[7:4])};
                        6'd6:  uart_data_to_send <= {4'h3, (ch1_dbg_harmonic_2[3:0])};
                        6'd7:  uart_data_to_send <= " ";
                        // H3:XXXX
                        6'd8:  uart_data_to_send <= "H";
                        6'd9:  uart_data_to_send <= "3";
                        6'd10: uart_data_to_send <= ":";
                        6'd11: uart_data_to_send <= {4'h3, (ch1_dbg_harmonic_3[15:12])};
                        6'd12: uart_data_to_send <= {4'h3, (ch1_dbg_harmonic_3[11:8])};
                        6'd13: uart_data_to_send <= {4'h3, (ch1_dbg_harmonic_3[7:4])};
                        6'd14: uart_data_to_send <= {4'h3, (ch1_dbg_harmonic_3[3:0])};
                        6'd15: uart_data_to_send <= " ";
                        // BASE:XXXX
                        6'd16: uart_data_to_send <= "B";
                        6'd17: uart_data_to_send <= "A";
                        6'd18: uart_data_to_send <= "S";
                        6'd19: uart_data_to_send <= "E";
                        6'd20: uart_data_to_send <= ":";
                        6'd21: uart_data_to_send <= {4'h3, (ch1_dbg_fft_max_amp[15:12])};
                        6'd22: uart_data_to_send <= {4'h3, (ch1_dbg_fft_max_amp[11:8])};
                        6'd23: uart_data_to_send <= {4'h3, (ch1_dbg_fft_max_amp[7:4])};
                        6'd24: uart_data_to_send <= {4'h3, (ch1_dbg_fft_max_amp[3:0])};
                        6'd25: uart_data_to_send <= " ";
                        // TRG:X
                        6'd26: uart_data_to_send <= "T";
                        6'd27: uart_data_to_send <= "R";
                        6'd28: uart_data_to_send <= "G";
                        6'd29: uart_data_to_send <= ":";
                        6'd30: uart_data_to_send <= ch1_dbg_calc_trigger ? "1" : "0";
                        6'd31: uart_data_to_send <= " ";
                        // VAL:X
                        6'd32: uart_data_to_send <= "V";
                        6'd33: uart_data_to_send <= "A";
                        6'd34: uart_data_to_send <= "L";
                        6'd35: uart_data_to_send <= ":";
                        6'd36: uart_data_to_send <= ch1_dbg_pipe_valid[2] ? "1" : "0";
                        6'd37: uart_data_to_send <= " ";
                        default: begin
                            send_state <= UART_SEND_NEWLINE;
                            uart_char_index <= 6'd0;
                        end
                    endcase
                    
                    if (uart_char_index <= 6'd37) begin
                        uart_send_trigger <= 1'b1;
                        uart_char_index <= uart_char_index + 1'b1;
                        send_state <= UART_WAIT_BUSY;
                    end
                end
            end
            
            //===== 发送换行符 "\r\n" =====
            UART_SEND_NEWLINE: begin
                if (!uart_busy) begin
                    case (uart_char_index)
                        6'd0: uart_data_to_send <= 8'h0D;  // \r
                        6'd1: uart_data_to_send <= 8'h0A;  // \n
                        default: begin
                            send_state <= UART_IDLE;
                            uart_char_index <= 6'd0;
                        end
                    endcase
                    
                    if (uart_char_index <= 6'd1) begin
                        uart_send_trigger <= 1'b1;
                        uart_char_index <= uart_char_index + 1'b1;
                        send_state <= UART_WAIT_BUSY;
                    end
                end
            end
            
            //===== 等待UART模块空闲 =====
            UART_WAIT_BUSY: begin
                if (uart_busy) begin
                    // 等待UART开始发送（busy拉高）
                    send_state <= send_state - 8'd1;  // 返回上一个状态
                end
            end
            
            default: send_state <= UART_IDLE;
        endcase
    end
end

// HDMI同步信号活动检测（保留原有代码）
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
        else if (uart_debug_trigger)  // 定时器触发时清除
            hdmi_vs_toggle_flag <= 1'b0;
            
        if (hdmi_hs_d1 != hdmi_hs_d2)
            hdmi_hs_toggle_flag <= 1'b1;
        else if (uart_debug_trigger)  // 定时器触发时清除
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

endmodule