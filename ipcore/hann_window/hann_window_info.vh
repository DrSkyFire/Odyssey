// Hann窗ROM使用说明
// 由于Hann窗对称性，可以只存储前4096个值
// 读取时: addr >= 4096 ? window[8191-addr] : window[addr]

// 窗长度: 8192
// 数据位宽: 16位 (Q15定点数)
// 地址位宽: 13位 (0-8191)

// ROM初始化文件:
// - hann_window_8192.coe (Xilinx)
// - hann_window_8192.mif (Altera/Gowin)
// - hann_window_8192.hex (Verilog $readmemh)

// 使用示例 (Verilog):
//   reg [15:0] window_rom [0:8191];
//   initial $readmemh("hann_window_8192.hex", window_rom);
//   wire [15:0] window_coeff = window_rom[addr];

// 乘法使用:
//   // ADC数据是11位有符号数，扩展到16位
//   wire signed [15:0] adc_signed = {{5{adc_data[10]}}, adc_data};
//   // Hann窗系数是16位无符号数 (Q15)
//   wire [15:0] window_coeff;
//   // 乘法结果是32位，取高16位（去掉Q15的15位小数）
//   wire signed [31:0] mult_result = adc_signed * $signed({1'b0, window_coeff});
//   wire signed [15:0] windowed_data = mult_result[30:15];  // 取[30:15]保留符号
