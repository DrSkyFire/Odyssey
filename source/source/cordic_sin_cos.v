module  cordic_sin_cos
#(    
    parameter PIPELINE  = 16                        //pipe数，最大支持16
)
(
    input                               clk,
    input                               rst_n,
    
    input       signed  [31:0]          angle,      //角度输入，16位小数位，范围：-180~+180
    input                               pre_vaild,

    output  reg signed  [31:0]          sin, 
    output  reg signed  [31:0]          cos,
    output  reg                         post_vaild

);//延迟PIPELINE+3拍

wire signed [31:0]  angle_array[15:0];

assign angle_array[0]  = 32'sd2949120;    //45度*2^16
assign angle_array[1]  = 32'sd1740992;    //26.5651度*2^16
assign angle_array[2]  = 32'sd919872;     //14.0362度*2^16
assign angle_array[3]  = 32'sd466944;     //7.1250度*2^16
assign angle_array[4]  = 32'sd234368;     //3.5763度*2^16
assign angle_array[5]  = 32'sd117312;     //1.7899度*2^16
assign angle_array[6]  = 32'sd58688;      //0.8952度*2^16
assign angle_array[7]  = 32'sd29312;      //0.4476度*2^16
assign angle_array[8]  = 32'sd14656;      //0.2238度*2^16
assign angle_array[9]  = 32'sd7360;       //0.1119度*2^16
assign angle_array[10] = 32'sd3648;       //0.0560度*2^16
assign angle_array[11] = 32'sd1856;	     //0.0280度*2^16
assign angle_array[12] = 32'sd896;        //0.0140度*2^16
assign angle_array[13] = 32'sd448;        //0.0070度*2^16
assign angle_array[14] = 32'sd256;        //0.0035度*2^16
assign angle_array[15] = 32'sd128;        //0.0018度*2^16

localparam K        = 32'h09b74;	  //0.607253*2^16         

reg signed  [31:0]  angle_map;
reg         [1:0]   site;

wire signed [15:0]  angle_t;

assign  angle_t = angle >>> 16;
  
always@(posedge clk or negedge rst_n)begin 
    if(!rst_n)begin
        angle_map   <=  0;
        site        <=  2'd1;
    end
    else    if((angle_t >= (-16'sd90))&&(angle_t <= 16'sd90))begin
        angle_map   <=  angle;
        site        <=  2'd1;
    end
    else    if(angle_t > 16'sd90 && angle_t <= 16'sd180)begin
        angle_map   <=  32'sd11796480 - angle;                  //180*65536 = 11796480
        site        <=  2'd2;
    end
    else    begin
        angle_map   <=  -32'sd11796480 - angle;
        site        <=  2'd3;
    end
end   

reg signed 	[31:0] 		x[PIPELINE:0];
reg signed 	[31:0] 		y[PIPELINE:0];
reg signed 	[31:0] 		z[PIPELINE:0];

always@(posedge clk or negedge rst_n)begin
   if(!rst_n)begin
       x[0]    <=  32'sd0;
       y[0]    <=  32'sd0;
       z[0]    <=  32'sd0;
   end
   else    begin
       x[0]    <=   K;
       y[0]    <=   32'sd0;
       z[0]    <=   angle_map;
   end
end

genvar i;
generate
    for(i = 1;i < PIPELINE+1;i = i + 1)begin:cal_xyz
        always@(posedge clk or negedge rst_n)begin
            if(!rst_n)begin
                x[i]    <=  32'sd0;
                y[i]    <=  32'sd0;
                z[i]    <=  32'sd0;
            end
            else    if(z[i-1][31])begin
                x[i]    <=  x[i-1] + (y[i-1] >>> (i-1));
                y[i]    <=  y[i-1] - (x[i-1] >>> (i-1));
                z[i]    <=  z[i-1] + angle_array[i-1];
            end
            else    begin
                x[i]    <=  x[i-1] - (y[i-1] >>> (i-1));
                y[i]    <=  y[i-1] + (x[i-1] >>> (i-1));
                z[i]    <=  z[i-1] - angle_array[i-1];
            end
        end 
    end
endgenerate

reg     [PIPELINE+1:0]      vaild_r;
reg     [2*PIPELINE+1:0]    site_r;

always@(posedge clk )begin
    vaild_r <=  {vaild_r[PIPELINE:0],pre_vaild};
    site_r  <=  {site_r[2*PIPELINE-1:0],site};   
end

always@(posedge clk or negedge rst_n)begin
    if(!rst_n)
        post_vaild  <=  0;
    else
        post_vaild  <=  vaild_r[PIPELINE+1];
end

always@(posedge clk or negedge rst_n)begin
    if(!rst_n)begin
        sin <=  0;
        cos <=  0;
    end
    else    if(~vaild_r[PIPELINE+1])begin
        sin <=  0;
        cos <=  0;
    end
    else    begin
        case(site_r[2*PIPELINE+1:2*PIPELINE])
            2'd1:begin
                sin <=  y[PIPELINE];
                cos <=  x[PIPELINE];
            end
            2'd2:begin
                sin <=  y[PIPELINE];
                cos <=  ~x[PIPELINE] + 1;
            end
            2'd3:begin
                sin <=  y[PIPELINE];
                cos <=  ~x[PIPELINE] + 1;
            end      
            default:begin
                sin <=  y[PIPELINE];
                cos <=  x[PIPELINE];
            end
        endcase  
    end
end


endmodule