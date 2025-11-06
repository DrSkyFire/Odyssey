//=============================================================================
// 文件名: waveform_classifier.v
// 描述: 波形分类器 - 基于决策树的AI信号识别
// 功能: 使用提取的特征进行波形类型分类
// 支持识别: 正弦波、方波、三角波、锯齿波、噪声信号
// 算法: 多级决策树 + 阈值判断
//=============================================================================

module waveform_classifier (
    input  wire        clk,
    input  wire        rst_n,
    
    // 特征输入
    input  wire [15:0] zcr,              // 过零率
    input  wire [15:0] crest_factor,     // 峰值因子
    input  wire [15:0] form_factor,      // 波形因子
    input  wire [15:0] mean_value,       // 平均值
    input  wire [15:0] std_dev,          // 标准差
    input  wire [15:0] thd,              // 总谐波失真
    input  wire [15:0] spectral_centroid, // 频谱质心
    input  wire [15:0] spectral_spread,  // 频谱展宽
    input  wire        features_valid,   // 特征有效标志
    
    // 分类结果输出
    output reg [2:0]   waveform_type,    // 波形类型编码
    output reg [7:0]   confidence,       // 置信度 (0-100%)
    output reg         classification_valid // 分类结果有效
);

//=============================================================================
// 波形类型编码
//=============================================================================
localparam TYPE_UNKNOWN  = 3'd0;
localparam TYPE_SINE     = 3'd1;  // 正弦波
localparam TYPE_SQUARE   = 3'd2;  // 方波
localparam TYPE_TRIANGLE = 3'd3;  // 三角波
localparam TYPE_SAWTOOTH = 3'd4;  // 锯齿波
localparam TYPE_NOISE    = 3'd5;  // 噪声信号

//=============================================================================
// 特征阈值定义（根据仿真和实验调整）
//=============================================================================
// 正弦波特征：
// - 低THD (<8%) - 修复: 放宽阈值以适应实际ADC噪声
// - 峰值因子 ≈ 1.414 (√2)
// - 波形因子 ≈ 1.11
localparam SINE_THD_MAX        = 16'd8;      // 修复: THD < 8% (原5%太严格)
localparam SINE_CF_MIN         = 16'd350;    // CF: 1.37 (Q8.8 = 350)
localparam SINE_CF_MAX         = 16'd400;    // CF: 1.56
localparam SINE_FF_MIN         = 16'd270;    // FF: 1.05
localparam SINE_FF_MAX         = 16'd300;    // FF: 1.17

// 方波特征：
// - 高THD (>30%)
// - 峰值因子 ≈ 1.0
// - 低过零率（稳定高低电平）
localparam SQUARE_THD_MIN      = 16'd30;     // THD > 30%
localparam SQUARE_CF_MAX       = 16'd280;    // CF: < 1.1
localparam SQUARE_ZCR_MAX      = 16'd2048;   // 低过零率

// 三角波特征：
// - 中等THD (10-25%)
// - 峰值因子 ≈ 1.732 (√3)
// - 波形因子 ≈ 1.15
localparam TRIANGLE_THD_MIN    = 16'd10;
localparam TRIANGLE_THD_MAX    = 16'd25;
localparam TRIANGLE_CF_MIN     = 16'd420;    // CF: 1.64
localparam TRIANGLE_CF_MAX     = 16'd480;    // CF: 1.88
localparam TRIANGLE_FF_MIN     = 16'd280;    // FF: 1.09
localparam TRIANGLE_FF_MAX     = 16'd320;    // FF: 1.25

// 锯齿波特征：
// - 高THD (>20%)
// - 峰值因子 ≈ 1.732
// - 线性变化（高过零率）
localparam SAWTOOTH_THD_MIN    = 16'd20;
localparam SAWTOOTH_CF_MIN     = 16'd400;    // CF: 1.56
localparam SAWTOOTH_ZCR_MIN    = 16'd1024;   // 中高过零率

// 噪声特征：
// - 极高THD (>60%)
// - 峰值因子分散
// - 高过零率
localparam NOISE_THD_MIN       = 16'd60;
localparam NOISE_ZCR_MIN       = 16'd8192;   // 高过零率

//=============================================================================
// 决策树分类逻辑
//=============================================================================
reg [2:0] classify_result;
reg [7:0] score;
reg [3:0] match_count;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        classify_result     = TYPE_UNKNOWN;
        score               = 0;
        match_count         = 0;
        waveform_type       <= TYPE_UNKNOWN;
        confidence          <= 0;
        classification_valid <= 1'b0;
    end else if (features_valid) begin
        // 重置匹配计数
        match_count = 0;
        
        //=====================================================================
        // 决策树第1级：THD粗分类
        //=====================================================================
        
        // 规则1：正弦波检测（最高优先级）
        if (thd < SINE_THD_MAX) begin
            // 检查峰值因子
            if ((crest_factor >= SINE_CF_MIN) && (crest_factor <= SINE_CF_MAX))
                match_count = match_count + 2;  // 权重2
            
            // 检查波形因子
            if ((form_factor >= SINE_FF_MIN) && (form_factor <= SINE_FF_MAX))
                match_count = match_count + 2;
            
            // 正弦波需要满足2个条件以上
            if (match_count >= 3) begin
                classify_result = TYPE_SINE;
                score = 90 + (match_count * 2);  // 90-100分
            end
        end
        
        // 规则2：方波检测
        else if (thd >= SQUARE_THD_MIN && zcr < SQUARE_ZCR_MAX) begin
            match_count = 2;  // THD和ZCR满足
            
            // 检查峰值因子（方波接近1）
            if (crest_factor <= SQUARE_CF_MAX)
                match_count = match_count + 2;
            
            if (match_count >= 3) begin
                classify_result = TYPE_SQUARE;
                score = 85 + (match_count * 2);
            end
        end
        
        // 规则3：三角波检测
        else if ((thd >= TRIANGLE_THD_MIN) && (thd <= TRIANGLE_THD_MAX)) begin
            // 检查峰值因子
            if ((crest_factor >= TRIANGLE_CF_MIN) && (crest_factor <= TRIANGLE_CF_MAX))
                match_count = match_count + 2;
            
            // 检查波形因子
            if ((form_factor >= TRIANGLE_FF_MIN) && (form_factor <= TRIANGLE_FF_MAX))
                match_count = match_count + 2;
            
            if (match_count >= 2) begin
                classify_result = TYPE_TRIANGLE;
                score = 80 + (match_count * 3);
            end
        end
        
        // 规则4：锯齿波检测
        else if ((thd >= SAWTOOTH_THD_MIN) && (crest_factor >= SAWTOOTH_CF_MIN) && 
                 (zcr >= SAWTOOTH_ZCR_MIN)) begin
            classify_result = TYPE_SAWTOOTH;
            score = 75;
        end
        
        // 规则5：噪声信号检测
        else if ((thd >= NOISE_THD_MIN) || (zcr >= NOISE_ZCR_MIN)) begin
            classify_result = TYPE_NOISE;
            score = 70;
        end
        
        // 规则6：无法分类
        else begin
            classify_result = TYPE_UNKNOWN;
            score = 50;
        end
        
        //=====================================================================
        // 决策树第2级：置信度修正
        //=====================================================================
        // 基于多个特征的一致性调整置信度
        
        // 如果频谱集中（低频谱展宽），提高置信度
        if (spectral_spread < 16'd256 && classify_result != TYPE_NOISE)
            score = (score < 95) ? (score + 5) : 8'd100;
        
        // 如果平均值接近0（交流信号），提高置信度
        if ((mean_value < 16'd100) && (mean_value > -16'd100))
            score = (score < 98) ? (score + 2) : 8'd100;
        
        // 输出最终结果
        waveform_type        <= classify_result;
        confidence           <= (score > 100) ? 8'd100 : score;
        classification_valid <= 1'b1;
        
    end else begin
        classification_valid <= 1'b0;
    end
end

//=============================================================================
// 调试输出（可选）
//=============================================================================
`ifdef SIMULATION
always @(posedge clk) begin
    if (classification_valid) begin
        case (waveform_type)
            TYPE_SINE:     $display("[AI] Detected: SINE WAVE, Confidence: %d%%", confidence);
            TYPE_SQUARE:   $display("[AI] Detected: SQUARE WAVE, Confidence: %d%%", confidence);
            TYPE_TRIANGLE: $display("[AI] Detected: TRIANGLE WAVE, Confidence: %d%%", confidence);
            TYPE_SAWTOOTH: $display("[AI] Detected: SAWTOOTH WAVE, Confidence: %d%%", confidence);
            TYPE_NOISE:    $display("[AI] Detected: NOISE SIGNAL, Confidence: %d%%", confidence);
            default:       $display("[AI] Detected: UNKNOWN, Confidence: %d%%", confidence);
        endcase
        $display("    Features: ZCR=%d, CF=%d, FF=%d, THD=%d%%", 
                 zcr, crest_factor, form_factor, thd);
    end
end
`endif

endmodule
