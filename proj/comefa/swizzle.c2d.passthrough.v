//Assumption: Currently the design works properly only if
//MEM_CTRL_DWIDTH == RAM_PORT_DWIDTH

`define MEM_CTRL_DWIDTH 40
`define MEM_CTRL_AWIDTH 9
`define RAM_PORT_DWIDTH 40
`define RAM_PORT_AWIDTH 9
`define NUM_BUFFERS     80
`define LOG_NUM_BUFFERS 7
`define RAM_START_ADDR        9'h0
`define MEM_CTRL_START_ADDR   9'h0
`define COUNT_TO_SWITCH_BUFFERS 40
`define LOG_COUNT_TO_SWITCH_BUFFERS 6

module swizzle_cram_to_dram(
  //this input tells whether the input data is valid or not
  input  data_valid,
  //clock and reset ports
  input  clk,
  input  resetn,
  //ram interface - data comes in
  input       [`RAM_PORT_DWIDTH-1:0] ram_data_in,
  //memory controller interface - data goes out
  output      [`MEM_CTRL_DWIDTH-1:0] mem_ctrl_data_out,
  output  reg [`MEM_CTRL_AWIDTH-1:0] mem_ctrl_addr,
  output  reg                        mem_ctrl_we
);

//when direction_of_dataflow is 0, that means
//ping buffer will be loaded from dram (left
//to right flow of information). during this time,
//pong buffer will be shifting out data (top to bottom
//flow of information).
//but when the direction_of_dataflow is 1,
//the ping buffer will be unloaded and pong buffer 
//will be loaded.
//reg direction_of_dataflow;
//wire opp_direction_of_dataflow;
//assign opp_direction_of_dataflow = ~direction_of_dataflow;

//reg [`LOG_COUNT_TO_SWITCH_BUFFERS-1:0] counter;

always @(posedge clk) begin
  if (resetn == 1'b0) begin
    //counter  <= 0;
    mem_ctrl_we <= 0;
    mem_ctrl_addr <= `MEM_CTRL_START_ADDR;
    //direction_of_dataflow <= 0;
  end 
  else if (data_valid) begin
    //counter <= counter + 1;
    mem_ctrl_we <= 1'b1;
	  mem_ctrl_addr <= mem_ctrl_addr + 1;
    //if (counter==`COUNT_TO_SWITCH_BUFFERS) begin
    //  direction_of_dataflow <= ~direction_of_dataflow;
    //  counter <= 0;
    //end
  end    
  else begin
    mem_ctrl_we <= 0;
  end
end

//wire [`RAM_PORT_DWIDTH-1:0] data_out_ping;
//wire [`RAM_PORT_DWIDTH-1:0] data_out_pong;
//assign mem_ctrl_data_out = direction_of_dataflow ? data_out_ping : data_out_pong;
assign mem_ctrl_data_out = ram_data_in;

//we are faning out the mem_ctrl_data_in to both buffers
//since we don't stop clock, does this mean that the data in the buffers
//will keep getting overwritten even when we don't want to.
//for example, when we are reading from (or unloading) ping buffers,
//we don't want to override them with the values being loaded into pong
//buffers. the answer is no. that's because we change the mux select
//on the flops in the buffers, so they will start taking data from a 
//different source (flops above them), even though the mem_ctrl_data
//is connected to data_in. that's why we also don't enable signals 
//for the flops in the buffers

////this is the left of the figure of swizzle logic we drew in the mantra paper
//ping_buffer u_ping (
//  .data_in(ram_data_in),
//  .data_out(data_out_ping),
//  .load_unload(direction_of_dataflow),
//  .clk(clk)
//);
//
////this is the right of the figure of swizzle logic we drew in the mantra paper
//pong_buffer u_pong (
//  .data_in(ram_data_in),
//  .data_out(data_out_pong),
//  .load_unload(opp_direction_of_dataflow),
//  .clk(clk)
//);

endmodule
