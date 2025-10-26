//=============================================================================
// 文件名: reciprocal_lut.v
// 描述: 倒数查找表 (Reciprocal Look-Up Table)
// 功能: 为除法运算提供高精度倒数近似，配合线性插值使用
// 
// 算法说明:
//   - 输入: 16位除数 (divisor)
//   - 输出: 倒数近似值 (格式: Q1.15定点数，表示 1/divisor)
//   - 精度: 配合线性插值可达 ±1% 误差
//   - 延迟: 1个时钟周期 (纯组合逻辑，建议后接寄存器)
//
// 使用方法:
//   1. 查表获取基础倒数: recip_base = lut[divisor[15:8]]
//   2. 获取下一个倒数: recip_next = lut[divisor[15:8] + 1]
//   3. 线性插值: recip = recip_base + (recip_next - recip_base) * (divisor[7:0] / 256)
//   4. 计算除法: quotient = dividend * recip >> 15
//=============================================================================

module reciprocal_lut (
    input  wire [15:0] divisor,      // 除数输入
    output wire [15:0] recip_base,   // 基础倒数值 (对应 divisor[15:8])
    output wire [15:0] recip_next    // 下一个倒数值 (用于插值)
);

//=============================================================================
// 倒数查找表 ROM
// 格式: Q1.15 定点数 (1个符号位 + 15个小数位)
// 计算: recip[i] = round((1 << 15) / ((i << 8) + 128))
// 范围: 倒数从 1/256 到 1/65535
//=============================================================================
reg [15:0] recip_rom [0:256];

initial begin
    // 前128个条目 (除数 0-32767，倒数较大)
    recip_rom[0]   = 16'hFFFF;  // 特殊值: 除以0保护
    recip_rom[1]   = 16'h8000;  // 1/512 ≈ 0.00195
    recip_rom[2]   = 16'h5555;  // 1/768 ≈ 0.00130
    recip_rom[3]   = 16'h4000;  // 1/1024 ≈ 0.00098
    recip_rom[4]   = 16'h3333;  // 1/1280 ≈ 0.00078
    recip_rom[5]   = 16'h2AAA;  // 1/1536 ≈ 0.00065
    recip_rom[6]   = 16'h2492;  // 1/1792 ≈ 0.00056
    recip_rom[7]   = 16'h2000;  // 1/2048 ≈ 0.00049
    recip_rom[8]   = 16'h1C71;  // 1/2304 ≈ 0.00043
    recip_rom[9]   = 16'h1999;  // 1/2560 ≈ 0.00039
    recip_rom[10]  = 16'h1745;  // 1/2816 ≈ 0.00036
    recip_rom[11]  = 16'h1555;  // 1/3072 ≈ 0.00033
    recip_rom[12]  = 16'h13B1;  // 1/3328 ≈ 0.00030
    recip_rom[13]  = 16'h1249;  // 1/3584 ≈ 0.00028
    recip_rom[14]  = 16'h1111;  // 1/3840 ≈ 0.00026
    recip_rom[15]  = 16'h1000;  // 1/4096 ≈ 0.00024
    recip_rom[16]  = 16'h0F0F;  // 1/4352
    recip_rom[17]  = 16'h0E38;  // 1/4608
    recip_rom[18]  = 16'h0D79;  // 1/4864
    recip_rom[19]  = 16'h0CCC;  // 1/5120
    recip_rom[20]  = 16'h0C30;  // 1/5376
    recip_rom[21]  = 16'h0BA2;  // 1/5632
    recip_rom[22]  = 16'h0B21;  // 1/5888
    recip_rom[23]  = 16'h0AAA;  // 1/6144
    recip_rom[24]  = 16'h0A3D;  // 1/6400
    recip_rom[25]  = 16'h09D8;  // 1/6656
    recip_rom[26]  = 16'h097B;  // 1/6912
    recip_rom[27]  = 16'h0924;  // 1/7168
    recip_rom[28]  = 16'h08D3;  // 1/7424
    recip_rom[29]  = 16'h0888;  // 1/7680
    recip_rom[30]  = 16'h0842;  // 1/7936
    recip_rom[31]  = 16'h0800;  // 1/8192
    
    // 32-63: 除数 8192-16383
    recip_rom[32]  = 16'h07C1;  recip_rom[33]  = 16'h0787;
    recip_rom[34]  = 16'h0750;  recip_rom[35]  = 16'h071C;
    recip_rom[36]  = 16'h06EB;  recip_rom[37]  = 16'h06BC;
    recip_rom[38]  = 16'h0690;  recip_rom[39]  = 16'h0666;
    recip_rom[40]  = 16'h063E;  recip_rom[41]  = 16'h0618;
    recip_rom[42]  = 16'h05F4;  recip_rom[43]  = 16'h05D1;
    recip_rom[44]  = 16'h05B0;  recip_rom[45]  = 16'h0590;
    recip_rom[46]  = 16'h0572;  recip_rom[47]  = 16'h0555;
    recip_rom[48]  = 16'h0539;  recip_rom[49]  = 16'h051E;
    recip_rom[50]  = 16'h0505;  recip_rom[51]  = 16'h04EC;
    recip_rom[52]  = 16'h04D4;  recip_rom[53]  = 16'h04BD;
    recip_rom[54]  = 16'h04A7;  recip_rom[55]  = 16'h0492;
    recip_rom[56]  = 16'h047D;  recip_rom[57]  = 16'h0469;
    recip_rom[58]  = 16'h0456;  recip_rom[59]  = 16'h0444;
    recip_rom[60]  = 16'h0432;  recip_rom[61]  = 16'h0421;
    recip_rom[62]  = 16'h0410;  recip_rom[63]  = 16'h0400;
    
    // 64-127: 除数 16384-32767
    recip_rom[64]  = 16'h03F0;  recip_rom[65]  = 16'h03E0;
    recip_rom[66]  = 16'h03D2;  recip_rom[67]  = 16'h03C3;
    recip_rom[68]  = 16'h03B5;  recip_rom[69]  = 16'h03A8;
    recip_rom[70]  = 16'h039B;  recip_rom[71]  = 16'h038E;
    recip_rom[72]  = 16'h0381;  recip_rom[73]  = 16'h0375;
    recip_rom[74]  = 16'h0369;  recip_rom[75]  = 16'h035E;
    recip_rom[76]  = 16'h0353;  recip_rom[77]  = 16'h0348;
    recip_rom[78]  = 16'h033D;  recip_rom[79]  = 16'h0333;
    recip_rom[80]  = 16'h0329;  recip_rom[81]  = 16'h031F;
    recip_rom[82]  = 16'h0315;  recip_rom[83]  = 16'h030C;
    recip_rom[84]  = 16'h0303;  recip_rom[85]  = 16'h02FA;
    recip_rom[86]  = 16'h02F1;  recip_rom[87]  = 16'h02E8;
    recip_rom[88]  = 16'h02E0;  recip_rom[89]  = 16'h02D8;
    recip_rom[90]  = 16'h02D0;  recip_rom[91]  = 16'h02C8;
    recip_rom[92]  = 16'h02C0;  recip_rom[93]  = 16'h02B9;
    recip_rom[94]  = 16'h02B1;  recip_rom[95]  = 16'h02AA;
    recip_rom[96]  = 16'h02A3;  recip_rom[97]  = 16'h029C;
    recip_rom[98]  = 16'h0295;  recip_rom[99]  = 16'h028F;
    recip_rom[100] = 16'h0288;  recip_rom[101] = 16'h0282;
    recip_rom[102] = 16'h027C;  recip_rom[103] = 16'h0276;
    recip_rom[104] = 16'h0270;  recip_rom[105] = 16'h026A;
    recip_rom[106] = 16'h0264;  recip_rom[107] = 16'h025E;
    recip_rom[108] = 16'h0259;  recip_rom[109] = 16'h0253;
    recip_rom[110] = 16'h024E;  recip_rom[111] = 16'h0249;
    recip_rom[112] = 16'h0243;  recip_rom[113] = 16'h023E;
    recip_rom[114] = 16'h0239;  recip_rom[115] = 16'h0234;
    recip_rom[116] = 16'h0230;  recip_rom[117] = 16'h022B;
    recip_rom[118] = 16'h0226;  recip_rom[119] = 16'h0222;
    recip_rom[120] = 16'h021D;  recip_rom[121] = 16'h0219;
    recip_rom[122] = 16'h0214;  recip_rom[123] = 16'h0210;
    recip_rom[124] = 16'h020C;  recip_rom[125] = 16'h0208;
    recip_rom[126] = 16'h0204;  recip_rom[127] = 16'h0200;
    
    // 128-255: 除数 32768-65535
    recip_rom[128] = 16'h01FC;  recip_rom[129] = 16'h01F8;
    recip_rom[130] = 16'h01F4;  recip_rom[131] = 16'h01F0;
    recip_rom[132] = 16'h01EC;  recip_rom[133] = 16'h01E9;
    recip_rom[134] = 16'h01E5;  recip_rom[135] = 16'h01E1;
    recip_rom[136] = 16'h01DE;  recip_rom[137] = 16'h01DA;
    recip_rom[138] = 16'h01D7;  recip_rom[139] = 16'h01D4;
    recip_rom[140] = 16'h01D0;  recip_rom[141] = 16'h01CD;
    recip_rom[142] = 16'h01CA;  recip_rom[143] = 16'h01C7;
    recip_rom[144] = 16'h01C3;  recip_rom[145] = 16'h01C0;
    recip_rom[146] = 16'h01BD;  recip_rom[147] = 16'h01BA;
    recip_rom[148] = 16'h01B7;  recip_rom[149] = 16'h01B4;
    recip_rom[150] = 16'h01B2;  recip_rom[151] = 16'h01AF;
    recip_rom[152] = 16'h01AC;  recip_rom[153] = 16'h01A9;
    recip_rom[154] = 16'h01A6;  recip_rom[155] = 16'h01A4;
    recip_rom[156] = 16'h01A1;  recip_rom[157] = 16'h019E;
    recip_rom[158] = 16'h019C;  recip_rom[159] = 16'h0199;
    recip_rom[160] = 16'h0197;  recip_rom[161] = 16'h0194;
    recip_rom[162] = 16'h0192;  recip_rom[163] = 16'h018F;
    recip_rom[164] = 16'h018D;  recip_rom[165] = 16'h018A;
    recip_rom[166] = 16'h0188;  recip_rom[167] = 16'h0186;
    recip_rom[168] = 16'h0183;  recip_rom[169] = 16'h0181;
    recip_rom[170] = 16'h017F;  recip_rom[171] = 16'h017D;
    recip_rom[172] = 16'h017A;  recip_rom[173] = 16'h0178;
    recip_rom[174] = 16'h0176;  recip_rom[175] = 16'h0174;
    recip_rom[176] = 16'h0172;  recip_rom[177] = 16'h0170;
    recip_rom[178] = 16'h016E;  recip_rom[179] = 16'h016C;
    recip_rom[180] = 16'h016A;  recip_rom[181] = 16'h0168;
    recip_rom[182] = 16'h0166;  recip_rom[183] = 16'h0164;
    recip_rom[184] = 16'h0162;  recip_rom[185] = 16'h0160;
    recip_rom[186] = 16'h015E;  recip_rom[187] = 16'h015C;
    recip_rom[188] = 16'h015A;  recip_rom[189] = 16'h0158;
    recip_rom[190] = 16'h0157;  recip_rom[191] = 16'h0155;
    recip_rom[192] = 16'h0153;  recip_rom[193] = 16'h0151;
    recip_rom[194] = 16'h0150;  recip_rom[195] = 16'h014E;
    recip_rom[196] = 16'h014C;  recip_rom[197] = 16'h014A;
    recip_rom[198] = 16'h0149;  recip_rom[199] = 16'h0147;
    recip_rom[200] = 16'h0145;  recip_rom[201] = 16'h0144;
    recip_rom[202] = 16'h0142;  recip_rom[203] = 16'h0141;
    recip_rom[204] = 16'h013F;  recip_rom[205] = 16'h013D;
    recip_rom[206] = 16'h013C;  recip_rom[207] = 16'h013A;
    recip_rom[208] = 16'h0139;  recip_rom[209] = 16'h0137;
    recip_rom[210] = 16'h0136;  recip_rom[211] = 16'h0134;
    recip_rom[212] = 16'h0133;  recip_rom[213] = 16'h0131;
    recip_rom[214] = 16'h0130;  recip_rom[215] = 16'h012E;
    recip_rom[216] = 16'h012D;  recip_rom[217] = 16'h012C;
    recip_rom[218] = 16'h012A;  recip_rom[219] = 16'h0129;
    recip_rom[220] = 16'h0127;  recip_rom[221] = 16'h0126;
    recip_rom[222] = 16'h0125;  recip_rom[223] = 16'h0123;
    recip_rom[224] = 16'h0122;  recip_rom[225] = 16'h0121;
    recip_rom[226] = 16'h011F;  recip_rom[227] = 16'h011E;
    recip_rom[228] = 16'h011D;  recip_rom[229] = 16'h011B;
    recip_rom[230] = 16'h011A;  recip_rom[231] = 16'h0119;
    recip_rom[232] = 16'h0118;  recip_rom[233] = 16'h0116;
    recip_rom[234] = 16'h0115;  recip_rom[235] = 16'h0114;
    recip_rom[236] = 16'h0113;  recip_rom[237] = 16'h0112;
    recip_rom[238] = 16'h0110;  recip_rom[239] = 16'h010F;
    recip_rom[240] = 16'h010E;  recip_rom[241] = 16'h010D;
    recip_rom[242] = 16'h010C;  recip_rom[243] = 16'h010B;
    recip_rom[244] = 16'h010A;  recip_rom[245] = 16'h0109;
    recip_rom[246] = 16'h0108;  recip_rom[247] = 16'h0106;
    recip_rom[248] = 16'h0105;  recip_rom[249] = 16'h0104;
    recip_rom[250] = 16'h0103;  recip_rom[251] = 16'h0102;
    recip_rom[252] = 16'h0101;  recip_rom[253] = 16'h0100;
    recip_rom[254] = 16'h00FF;  recip_rom[255] = 16'h00FE;
    
    // 第256个条目 (用于插值边界)
    recip_rom[256] = 16'h00FD;
end

//=============================================================================
// 查表逻辑 (纯组合逻辑)
//=============================================================================
wire [7:0] lut_index = divisor[15:8];

assign recip_base = recip_rom[lut_index];
assign recip_next = recip_rom[lut_index + 8'd1];

endmodule
