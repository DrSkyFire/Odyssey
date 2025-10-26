module  cordic_In
#(    
    parameter PIPELINE  = 16                        //pipe数，最大支持16
)
(
    input                               clk         ,
    input                               rst_n       ,
    
    input       signed  [31:0]          iData       ,   //16位小数位,0.1~9.58    
    input                               pre_vaild   ,

    output  reg signed  [31:0]          In          , 
    output  reg                         post_vaild

);//延迟PIPELINE+2拍

wire signed [31:0]  alpha_array[15:0];

assign alpha_array[0]   =   32'sd35999; 
assign alpha_array[1]   =   32'sd16739; 
assign alpha_array[2]   =   32'sd8235;
assign alpha_array[3]   =   32'sd4101;
assign alpha_array[4]   =   32'sd2049;
assign alpha_array[5]   =   32'sd1024;
assign alpha_array[6]   =   32'sd512;
assign alpha_array[7]   =   32'sd256;
assign alpha_array[8]   =   32'sd128;
assign alpha_array[9]   =   32'sd64;
assign alpha_array[10]  =   32'sd32;
assign alpha_array[11]  =   32'sd16;
assign alpha_array[12]  =   32'sd8;
assign alpha_array[13]  =   32'sd4;
assign alpha_array[14]  =   32'sd2;
assign alpha_array[15]  =   32'sd1;

localparam K = 32'sd79137;      //1.207534*65536

reg signed 	[31:0] 		            currentX[PIPELINE:0];
reg signed 	[31:0] 		            currentY[PIPELINE:0];
reg signed 	[31:0] 		            currentZ[PIPELINE:0];
wire signed [31:0]                  nextX[PIPELINE-1:0];  
wire signed [31:0]                  tempX[PIPELINE-1:0]; 
wire signed [31:0]                  nextY[PIPELINE-1:0];  
wire signed [31:0]                  tempY[PIPELINE-1:0];
wire signed [31:0]                  nextZ[PIPELINE-1:0];  
wire signed [31:0]                  tempZ[PIPELINE-1:0];

always@(posedge clk or negedge rst_n)begin
   if(!rst_n)begin
       currentX[0]  <=  32'sd0;
       currentY[0]  <=  32'sd0;
       currentZ[0]  <=  32'sd0;     
   end
   else    begin
       currentX[0]  <=   iData + 32'sd65536;
       currentY[0]  <=   iData - 32'sd65536;
       currentZ[0]  <=   32'sd0;
   end
end

genvar i;
generate
    for (i = 1; i < PIPELINE + 1; i = i + 1) begin : cal_xyz 

        assign nextX[i-1] = (~currentY[i-1][31]) ? (currentX[i-1] - (currentY[i-1] >>> i)) : (currentX[i-1] + (currentY[i-1] >>> i));
        assign nextY[i-1] = (~currentY[i-1][31]) ? (currentY[i-1] - (currentX[i-1] >>> i)) : (currentY[i-1] + (currentX[i-1] >>> i));
        assign nextZ[i-1] = (~currentY[i-1][31]) ? (currentZ[i-1] + alpha_array[i-1]) : (currentZ[i-1] - alpha_array[i-1]);

        // 再迭代, 在 i % 4 == 0 时再进行一次计算
        assign tempX[i-1] = (~nextY[i-1][31]) ? (nextX[i-1] - (nextY[i-1] >>> i)) : (nextX[i-1] + (nextY[i-1] >>> i));
        assign tempY[i-1] = (~nextY[i-1][31]) ? (nextY[i-1] - (nextX[i-1] >>> i)) : (nextY[i-1] + (nextX[i-1] >>> i));
        assign tempZ[i-1] = (~nextY[i-1][31]) ? (nextZ[i-1] + alpha_array[i-1]) : (nextZ[i-1] - alpha_array[i-1]);

        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                currentX[i] <= 32'sd0;
                currentY[i] <= 32'sd0;
                currentZ[i] <= 32'sd0;
            end else if (i % 4 == 0) begin
                // i % 4 == 0 时，选择再迭代
                currentX[i] <= tempX[i-1];
                currentY[i] <= tempY[i-1];
                currentZ[i] <= tempZ[i-1];
            end else begin
                currentX[i] <= nextX[i-1];
                currentY[i] <= nextY[i-1];
                currentZ[i] <= nextZ[i-1];
            end
        end
    end
endgenerate

reg     [PIPELINE:0]      vaild_r;

always@(posedge clk )begin
    vaild_r <=  {vaild_r[PIPELINE-1:0],pre_vaild};   
end

always@(posedge clk or negedge rst_n)begin
    if(!rst_n)
        post_vaild  <=  0;
    else
        post_vaild  <=  vaild_r[PIPELINE];
end

always@(posedge clk or negedge rst_n)begin
    if(!rst_n)begin
        In <=  0;
    end
    else    if(~vaild_r[PIPELINE])begin
        In <=  0;
    end
    else    begin
        In <=  currentZ[PIPELINE] <<< 1;
    end
end




endmodule