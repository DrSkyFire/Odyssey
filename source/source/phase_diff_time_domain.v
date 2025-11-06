//==============================================================================
// 时域相位差测量模块 - 基于过零检测
//==============================================================================
// 功能：通过检测两个通道信号的上升沿过零点，计算相位差
// 方法：Phase = (Δt / T) × 360°
// 适用：单一频率正弦波信号（如 1kHz）
// 精度：采样率 35MHz，1kHz 信号理论精度 ~0.01°
//==============================================================================

module phase_diff_time_domain (
    input  wire         clk,            // 采样时钟 35MHz
    input  wire         rst_n,          // 异步复位，低有效
    
    // ADC 数据输入
    input  wire [7:0]   adc_ch1_data,   // 通道1 ADC 数据 (8位)
    input  wire [7:0]   adc_ch2_data,   // 通道2 ADC 数据 (8位)
    input  wire         adc_valid,      // ADC 数据有效信号
    
    // 相位差输出
    output reg  [15:0]  phase_diff,     // 相位差输出 (-1800 ~ +1800 表示 -180.0° ~ +180.0°)
    output reg          phase_valid,    // 相位差有效标志
    output reg  [7:0]   confidence      // 置信度 (0-255)
);

//==============================================================================
// 参数定义
//==============================================================================
parameter SAMPLE_RATE = 35_000_000;     // 采样率 35MHz
parameter MIN_PERIOD = 1000;            // 最小周期计数（对应 35kHz）
parameter MAX_PERIOD = 350000;          // 最大周期计数（对应 100Hz）
parameter ZERO_THRESHOLD = 8'd128;      // 过零阈值（中点）
parameter HYSTERESIS = 8'd5;            // 滞回区间，防止抖动

//==============================================================================
// 信号定义
//==============================================================================
// 通道1 过零检测
reg [7:0]   ch1_data_d1, ch1_data_d2;
reg         ch1_above_zero;             // 信号是否在零点以上
reg         ch1_zero_cross;             // 上升沿过零检测
reg [19:0]  ch1_period_cnt;             // 周期计数器
reg [19:0]  ch1_period;                 // 测量的周期

// 通道2 过零检测
reg [7:0]   ch2_data_d1, ch2_data_d2;
reg         ch2_above_zero;
reg         ch2_zero_cross;
reg [19:0]  ch2_period_cnt;             // 周期计数器（也是相位计数器）
reg [19:0]  ch2_period;                 // 测量的周期

// 相位差计算
reg [19:0]  time_diff;                  // 两个过零点的时间差
reg [19:0]  avg_period;                 // 平均周期
reg         calc_valid;                 // 计算有效标志
reg [19:0]  ch1_zero_snapshot;          // CH1过零时的CH2位置快照
reg [19:0]  ch2_zero_snapshot;          // CH2过零时的CH1位置快照（用于双向验证）
reg         ch1_has_crossed;            // CH1已过零标志
reg         ch2_has_crossed;            // CH2已过零标志

//==============================================================================
// 通道1 过零检测与周期测量
//==============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        ch1_data_d1 <= 8'd128;
        ch1_data_d2 <= 8'd128;
        ch1_above_zero <= 1'b0;
        ch1_zero_cross <= 1'b0;
        ch1_period_cnt <= 20'd0;
        ch1_period <= 20'd35000;  // 默认1kHz周期
    end else if (adc_valid) begin
        // 数据延迟链
        ch1_data_d1 <= adc_ch1_data;
        ch1_data_d2 <= ch1_data_d1;
        
        // 带滞回的过零判断
        if (ch1_data_d1 > ZERO_THRESHOLD + HYSTERESIS)
            ch1_above_zero <= 1'b1;
        else if (ch1_data_d1 < ZERO_THRESHOLD - HYSTERESIS)
            ch1_above_zero <= 1'b0;
        
        // 上升沿过零检测：从负到正
        if (!ch1_above_zero && (ch1_data_d1 > ZERO_THRESHOLD + HYSTERESIS)) begin
            ch1_zero_cross <= 1'b1;
            
            // 周期测量：上升沿到上升沿
            if (ch1_period_cnt >= MIN_PERIOD && ch1_period_cnt <= MAX_PERIOD)
                ch1_period <= ch1_period_cnt;
            
            ch1_period_cnt <= 20'd0;  // 重置周期计数器
        end else begin
            ch1_zero_cross <= 1'b0;
            if (ch1_period_cnt < MAX_PERIOD)
                ch1_period_cnt <= ch1_period_cnt + 1'b1;
        end
    end
end

//==============================================================================
// 通道2 过零检测与周期测量
//==============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        ch2_data_d1 <= 8'd128;
        ch2_data_d2 <= 8'd128;
        ch2_above_zero <= 1'b0;
        ch2_zero_cross <= 1'b0;
        ch2_period_cnt <= 20'd0;
        ch2_period <= 20'd35000;
    end else if (adc_valid) begin
        ch2_data_d1 <= adc_ch2_data;
        ch2_data_d2 <= ch2_data_d1;
        
        if (ch2_data_d1 > ZERO_THRESHOLD + HYSTERESIS)
            ch2_above_zero <= 1'b1;
        else if (ch2_data_d1 < ZERO_THRESHOLD - HYSTERESIS)
            ch2_above_zero <= 1'b0;
        
        // CH2 过零检测
        if (!ch2_above_zero && (ch2_data_d1 > ZERO_THRESHOLD + HYSTERESIS)) begin
            ch2_zero_cross <= 1'b1;
            
            if (ch2_period_cnt >= MIN_PERIOD && ch2_period_cnt <= MAX_PERIOD)
                ch2_period <= ch2_period_cnt;
            
            ch2_period_cnt <= 20'd0;  // 重置周期计数器
        end else begin
            ch2_zero_cross <= 1'b0;
            if (ch2_period_cnt < MAX_PERIOD)
                ch2_period_cnt <= ch2_period_cnt + 1'b1;
        end
        
        // 【注释】删除未使用的 ch2_phase_at_ch1_cross 采样
        // 因为我们在相位差计算模块中使用 ch1_zero_snapshot 记录同样的数据
    end
end

//==============================================================================
// 相位差计算（改进：等待双通道都过零后计算）
//==============================================================================
reg [19:0]  ch2_phase_latched;  // 锁存的CH2相位值
reg [2:0]   calc_counter;        // 计算周期计数器
reg         ch1_leading;         // CH1超前标志（CH1先过零）
reg         ch2_leading;         // CH2超前标志（CH2先过零）
reg [19:0]  phase_snapshot;      // 相位快照（后过零通道的计数值）

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        time_diff <= 20'd0;
        avg_period <= 20'd35000;
        ch2_phase_latched <= 20'd0;
        ch1_zero_snapshot <= 20'd0;
        ch2_zero_snapshot <= 20'd0;
        ch1_has_crossed <= 1'b0;
        ch2_has_crossed <= 1'b0;
        ch1_leading <= 1'b0;
        ch2_leading <= 1'b0;
        phase_snapshot <= 20'd0;
        calc_counter <= 3'd0;
        calc_valid <= 1'b0;
    end else begin
        // 【关键修复】记录过零事件和过零顺序
        if (ch1_zero_cross && !ch1_has_crossed) begin
            ch1_zero_snapshot <= ch2_period_cnt;  // CH1过零时CH2的位置
            ch1_has_crossed <= 1'b1;
            
            // 【新增】如果CH2还未过零，说明CH1先过零（CH1超前）
            if (!ch2_has_crossed) begin
                ch1_leading <= 1'b1;
                ch2_leading <= 1'b0;
            end
        end
        
        if (ch2_zero_cross && !ch2_has_crossed) begin
            ch2_zero_snapshot <= ch1_period_cnt;  // CH2过零时CH1的位置
            ch2_has_crossed <= 1'b1;
            
            // 【新增】如果CH1还未过零，说明CH2先过零（CH2超前）
            if (!ch1_has_crossed) begin
                ch2_leading <= 1'b1;
                ch1_leading <= 1'b0;
            end
        end
        
        // 【修复】当两个通道都过零后，根据过零顺序计算相位差
        if (ch1_has_crossed && ch2_has_crossed) begin
            // 根据过零顺序选择正确的相位差计算方式
            if (ch1_leading) begin
                // CH1先过零 → CH1超前 → 正相位差
                // 使用CH2过零时CH1的计数值
                time_diff <= ch2_zero_snapshot;
                phase_snapshot <= ch2_zero_snapshot;
            end else begin
                // CH2先过零 → CH2超前 → 负相位差
                // 使用CH1过零时CH2的计数值
                time_diff <= ch1_zero_snapshot;
                phase_snapshot <= ch1_zero_snapshot;
            end
            
            avg_period <= (ch1_period + ch2_period) >> 1;
            calc_counter <= 3'd4;
            calc_valid <= 1'b1;
            
            // 清除标志，准备下一轮
            ch1_has_crossed <= 1'b0;
            ch2_has_crossed <= 1'b0;
            ch1_leading <= 1'b0;
            ch2_leading <= 1'b0;
        end else if (calc_counter > 3'd0) begin
            calc_counter <= calc_counter - 1'b1;
            calc_valid <= 1'b1;
        end else begin
            calc_valid <= 1'b0;
        end
    end
end

//==============================================================================
// 相位差输出 - 优化算法（避免除法器）
// 算法：phase = (time_diff * 3600) / period
// 优化：使用动态计算 phase ≈ (time_diff * 3600 * 1024) / (avg_period * 1024)
//       简化为 (time_diff << 10) * 3600 / (avg_period << 10)
// 进一步优化：phase ≈ (time_diff * k) >> 10, 其中 k = 3600*1024/avg_period
// 【改进v2】符号判断逻辑：基于过零顺序，而非时间差大小
//==============================================================================
reg [31:0]  phase_calc_step1;   // (time_diff × 系数) 中间结果
reg [31:0]  phase_calc_step2;   // 移位结果（近似除法）
reg [31:0]  scale_factor;       // 动态计算的缩放系数
reg [19:0]  time_diff_d1;       // 时间差延迟（用于符号判断）
reg [19:0]  avg_period_d1;      // 周期延迟
reg         ch1_leading_d1, ch1_leading_d2;  // CH1超前标志延迟
reg         ch2_leading_d1, ch2_leading_d2;  // CH2超前标志延迟
reg         calc_valid_d1, calc_valid_d2;
reg [19:0]  period_diff;        // 周期差异（用于置信度计算）

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        phase_calc_step1 <= 32'd0;
        phase_calc_step2 <= 32'd0;
        scale_factor <= 32'd103;  // 默认值，对应 period=35000
        time_diff_d1 <= 20'd0;
        avg_period_d1 <= 20'd35000;
        ch1_leading_d1 <= 1'b0;
        ch1_leading_d2 <= 1'b0;
        ch2_leading_d1 <= 1'b0;
        ch2_leading_d2 <= 1'b0;
        period_diff <= 20'd0;
        calc_valid_d1 <= 1'b0;
        calc_valid_d2 <= 1'b0;
        phase_diff <= 16'sd0;
        phase_valid <= 1'b0;
        confidence <= 8'd0;
    end else begin
        // 流水线延迟
        calc_valid_d1 <= calc_valid;
        calc_valid_d2 <= calc_valid_d1;
        ch1_leading_d1 <= ch1_leading;
        ch1_leading_d2 <= ch1_leading_d1;
        ch2_leading_d1 <= ch2_leading;
        ch2_leading_d2 <= ch2_leading_d1;
        
        // 步骤1：计算缩放系数和时间差乘法
        // scale_factor ≈ 3686400 / avg_period (3686400 = 3600 * 1024)
        // 为了避免除法，使用查找表或近似值
        if (calc_valid) begin
            // 根据周期范围选择近似系数
            if (avg_period < 20'd10000)          // > 3.5kHz
                scale_factor <= 32'd370;         // 3686400/10000
            else if (avg_period < 20'd35000)     // 1kHz - 3.5kHz
                scale_factor <= 32'd103;         // 3686400/35000
            else if (avg_period < 20'd70000)     // 500Hz - 1kHz
                scale_factor <= 32'd52;          // 3686400/70000
            else                                 // < 500Hz
                scale_factor <= 32'd26;          // 3686400/140000
                
            phase_calc_step1 <= time_diff * scale_factor;
            time_diff_d1 <= time_diff;
            avg_period_d1 <= avg_period;
        end
        
        // 步骤2：右移10位（除以1024）
        if (calc_valid_d1) begin
            phase_calc_step2 <= phase_calc_step1 >> 10;
        end
        
        // 步骤3：180°环绕处理和符号判断
        if (calc_valid_d2) begin
            // 【修复v2】符号判断逻辑：基于过零顺序
            // ch1_leading=1：CH1先过零，CH1超前，相位差为正
            // ch2_leading=1：CH2先过零，CH2超前，相位差为负
            
            // 【新增】单通道检测：如果time_diff接近满周期，说明另一通道无信号
            if (time_diff_d1 > (avg_period_d1 - (avg_period_d1 >> 4))) begin
                // 单通道模式：time_diff > 93.75% of period
                phase_diff <= 16'sd0;        // 输出0°（无效相位差）
                confidence <= 8'd0;          // 置信度为0
            end else if (ch1_leading_d1) begin
                // CH1超前 = 正相位差
                if (phase_calc_step2 > 32'd1800)
                    phase_diff <= 16'sd1800;   // 限制在+180°
                else
                    phase_diff <= phase_calc_step2[15:0];
            end else begin
                // CH2超前 = 负相位差
                if (phase_calc_step2 > 32'd1800)
                    phase_diff <= -16'sd1800;  // 限制在-180°
                else
                    phase_diff <= -phase_calc_step2[15:0];
            end
            
            // 【改进】置信度：综合周期稳定性和数据有效性
            if (ch1_period > ch2_period)
                period_diff <= ch1_period - ch2_period;
            else
                period_diff <= ch2_period - ch1_period;
            
            // 周期差异 < 1% → 高置信度
            if (period_diff < (avg_period_d1 >> 7))      // < 0.78%
                confidence <= 8'd255;
            else if (period_diff < (avg_period_d1 >> 6)) // < 1.56%
                confidence <= 8'd200;
            else if (period_diff < (avg_period_d1 >> 5)) // < 3.12%
                confidence <= 8'd150;
            else if (period_diff < (avg_period_d1 >> 4)) // < 6.25%
                confidence <= 8'd100;
            else
                confidence <= 8'd50;  // 周期不稳定
            
            phase_valid <= 1'b1;
        end else begin
            phase_valid <= 1'b0;
        end
    end
end

endmodule
