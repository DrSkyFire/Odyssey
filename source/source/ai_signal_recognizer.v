//=============================================================================
// 文件名: ai_signal_recognizer.v
// 描述: AI信号识别器 - 顶层模块
// 功能: 整合特征提取和波形分类，实现自动信号识别
// 特点: 
//   - 并行特征提取（8个特征同时计算）
//   - 决策树分类器（5种波形类型）
//   - 流水线架构（3级延迟）
//   - 置信度输出
//=============================================================================

module ai_signal_recognizer #(
    parameter DATA_WIDTH = 11,
    parameter WINDOW_SIZE = 1024,
    parameter FFT_BINS = 512
)(
    input  wire                         clk,
    input  wire                         rst_n,
    
    // 信号输入
    input  wire signed [DATA_WIDTH-1:0] signal_in,
    input  wire                         signal_valid,
    
    // FFT频谱输入
    input  wire [15:0]                  fft_magnitude,
    input  wire [9:0]                   fft_bin_index,
    input  wire                         fft_valid,
    
    // 使能控制
    input  wire                         ai_enable,
    
    // 识别结果输出
    output wire [2:0]                   waveform_type,    // 波形类型
    output wire [7:0]                   confidence,       // 置信度
    output wire                         result_valid,     // 结果有效
    
    // 调试特征输出（可选）
    output wire [15:0]                  dbg_zcr,
    output wire [15:0]                  dbg_crest_factor,
    output wire [15:0]                  dbg_thd
);

//=============================================================================
// 特征信号
//=============================================================================
wire [15:0] zcr;
wire [15:0] crest_factor;
wire [15:0] form_factor;
wire [15:0] mean_value;
wire [15:0] std_dev;
wire [15:0] thd;
wire [15:0] spectral_centroid;
wire [15:0] spectral_spread;
wire        features_valid;

//=============================================================================
// 模块实例化
//=============================================================================

// 1. 特征提取器
waveform_feature_extractor #(
    .DATA_WIDTH   (DATA_WIDTH),
    .WINDOW_SIZE  (WINDOW_SIZE),
    .FFT_BINS     (FFT_BINS)
) u_feature_extractor (
    .clk               (clk),
    .rst_n             (rst_n && ai_enable),
    
    .signal_in         (signal_in),
    .signal_valid      (signal_valid),
    
    .fft_magnitude     (fft_magnitude),
    .fft_bin_index     (fft_bin_index),
    .fft_valid         (fft_valid),
    
    .zcr               (zcr),
    .crest_factor      (crest_factor),
    .form_factor       (form_factor),
    .mean_value        (mean_value),
    .std_dev           (std_dev),
    .thd               (thd),
    .spectral_centroid (spectral_centroid),
    .spectral_spread   (spectral_spread),
    .features_valid    (features_valid)
);

// 2. 波形分类器
waveform_classifier u_classifier (
    .clk                  (clk),
    .rst_n                (rst_n && ai_enable),
    
    .zcr                  (zcr),
    .crest_factor         (crest_factor),
    .form_factor          (form_factor),
    .mean_value           (mean_value),
    .std_dev              (std_dev),
    .thd                  (thd),
    .spectral_centroid    (spectral_centroid),
    .spectral_spread      (spectral_spread),
    .features_valid       (features_valid),
    
    .waveform_type        (waveform_type),
    .confidence           (confidence),
    .classification_valid (result_valid)
);

//=============================================================================
// 调试输出
//=============================================================================
assign dbg_zcr          = zcr;
assign dbg_crest_factor = crest_factor;
assign dbg_thd          = thd;

endmodule
