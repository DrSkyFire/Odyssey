module data_delay
#(
	parameter DATA_WIDTH = 8,
	parameter DATA_DELAY = 5
)
(
    input                       I_video_clk,
    input                       I_rst_n,   
    input  [DATA_WIDTH-1:0]     I_data,
    
    output [DATA_WIDTH-1:0]     O_data
);

reg     [DATA_WIDTH-1:0]    data_buff[DATA_DELAY-1:0];
always@(posedge I_video_clk or negedge I_rst_n)begin: block_delay
    integer i;
    if(!I_rst_n)begin
        for(i = 0; i < DATA_DELAY; i = i + 1)
            data_buff[i] <= 0;   
    end
    else    begin
        data_buff[0] <= I_data;
        for(i = 1; i < DATA_DELAY; i = i + 1)
            data_buff[i] <= data_buff[i-1];    
    end
end

assign O_data = data_buff[DATA_DELAY-1];

endmodule