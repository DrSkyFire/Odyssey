//=============================================================================
// 文件名: char_rom_minimal.v
// 描述: 极简字符ROM - 仅包含42个实际使用的字符
// 优化: 从128字符减少到42字符，节省67.2%资源
// 生成时间: 自动生成
//=============================================================================

module char_rom_minimal (
    input  wire [7:0]   ascii_code,     // 标准ASCII码输入
    output reg  [5:0]   char_index,     // 紧凑索引输出 (0-41)
    output reg          char_valid      // 字符有效标志
);

// ASCII码到紧凑索引的查找表
always @(*) begin
    char_valid = 1'b1;  // 默认有效
    case (ascii_code)
        8'd 32: char_index = 6'd 0;  // ' '
        8'd 37: char_index = 6'd 1;  // '%'
        8'd 46: char_index = 6'd 2;  // '.'
        8'd 48: char_index = 6'd 3;  // '0'
        8'd 49: char_index = 6'd 4;  // '1'
        8'd 50: char_index = 6'd 5;  // '2'
        8'd 51: char_index = 6'd 6;  // '3'
        8'd 52: char_index = 6'd 7;  // '4'
        8'd 53: char_index = 6'd 8;  // '5'
        8'd 54: char_index = 6'd 9;  // '6'
        8'd 55: char_index = 6'd10;  // '7'
        8'd 56: char_index = 6'd11;  // '8'
        8'd 57: char_index = 6'd12;  // '9'
        8'd 58: char_index = 6'd13;  // ':'
        8'd 65: char_index = 6'd14;  // 'A'
        8'd 67: char_index = 6'd15;  // 'C'
        8'd 68: char_index = 6'd16;  // 'D'
        8'd 70: char_index = 6'd17;  // 'F'
        8'd 72: char_index = 6'd18;  // 'H'
        8'd 78: char_index = 6'd19;  // 'N'
        8'd 80: char_index = 6'd20;  // 'P'
        8'd 83: char_index = 6'd21;  // 'S'
        8'd 84: char_index = 6'd22;  // 'T'
        8'd 85: char_index = 6'd23;  // 'U'
        8'd 97: char_index = 6'd24;  // 'a'
        8'd101: char_index = 6'd25;  // 'e'
        8'd104: char_index = 6'd26;  // 'h'
        8'd105: char_index = 6'd27;  // 'i'
        8'd107: char_index = 6'd28;  // 'k'
        8'd108: char_index = 6'd29;  // 'l'
        8'd109: char_index = 6'd30;  // 'm'
        8'd110: char_index = 6'd31;  // 'n'
        8'd111: char_index = 6'd32;  // 'o'
        8'd112: char_index = 6'd33;  // 'p'
        8'd113: char_index = 6'd34;  // 'q'
        8'd114: char_index = 6'd35;  // 'r'
        8'd115: char_index = 6'd36;  // 's'
        8'd116: char_index = 6'd37;  // 't'
        8'd117: char_index = 6'd38;  // 'u'
        8'd119: char_index = 6'd39;  // 'w'
        8'd121: char_index = 6'd40;  // 'y'
        8'd122: char_index = 6'd41;  // 'z'
        default: begin
            char_index = 6'd0;   // 默认映射到空格
            char_valid = 1'b0;   // 标记为无效字符
        end
    endcase
end

endmodule
