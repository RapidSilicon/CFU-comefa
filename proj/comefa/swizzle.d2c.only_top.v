//Assumption: Currently the design works properly only if
//MEM_CTRL_DWIDTH == RAM_PORT_DWIDTH
`define MEM_CTRL_DWIDTH 40
`define MEM_CTRL_AWIDTH 9
`define RAM_PORT_DWIDTH 40
`define RAM_PORT_AWIDTH 9
`define NUM_BUFFERS     80
`define LOG_NUM_BUFFERS 7
`define COUNT_TO_SWITCH_BUFFERS 40
`define LOG_COUNT_TO_SWITCH_BUFFERS 6
`define RAM_NUM_WORDS 512
`define RAM_START_NUM 0

module swizzle_dram_to_cram(
  //this input tells whether the input data is valid or not
  input  data_valid,
  //clock and reset ports
  input  clk,
  input  resetn,
  //memory controller interface - data comes in
  input      [`MEM_CTRL_DWIDTH-1:0] mem_ctrl_data_in,
  input      mem_ctrl_data_last,
  //interface to the compute ram - data goes out
  input      [`RAM_PORT_AWIDTH+`LOG_NUM_CRAMS-1:0] ram_start_addr,
  output     [`RAM_PORT_DWIDTH-1:0] ram_data_out,
  output reg [`RAM_PORT_AWIDTH+`LOG_NUM_CRAMS-1:0] ram_addr,
  output reg                        ram_we,
  output      ready
);

//when direction_of_dataflow is 0, that means
//ping buffer will be loaded from dram (left
//to right flow of information). during this time,
//pong buffer will be shifting out data (top to bottom
//flow of information).
//but when the direction_of_dataflow is 1,
//the ping buffer will be unloaded and pong buffer 
//will be loaded.
reg direction_of_dataflow;
wire opp_direction_of_dataflow;
assign opp_direction_of_dataflow = ~direction_of_dataflow;

reg [`LOG_COUNT_TO_SWITCH_BUFFERS*2-1:0] in_data_counter;
reg [`LOG_COUNT_TO_SWITCH_BUFFERS*2-1:0] out_data_counter;
reg [`LOG_COUNT_TO_SWITCH_BUFFERS*2-1:0] out_data_counter_snap;
reg [`RAM_PORT_AWIDTH+`LOG_NUM_CRAMS-1:0] ram_start_addr_int;
      
/*
reg first_time_wait;
reg last_part;

always @(posedge clk) begin
  if (~resetn) begin
    in_data_counter  <= 0;
    out_data_counter  <= 0;
    ram_we <= 0;
    direction_of_dataflow <= 0;
    first_time_wait <= 0;
    last_part <= 0;
  end 
  else if (data_valid || last_part) begin
    if (~last_part) begin
      in_data_counter <= in_data_counter + 1;
    end
    if (first_time_wait) begin
      ram_we <= 1'b1;
      out_data_counter <= out_data_counter + 1;
	    ram_addr <= ram_addr + 1;
    end
    if (in_data_counter==(`COUNT_TO_SWITCH_BUFFERS)) begin
      direction_of_dataflow <= ~direction_of_dataflow;
    end
    if (out_data_counter==(2*`COUNT_TO_SWITCH_BUFFERS)) begin
      out_data_counter <= 0;
    end
    if (in_data_counter==(2*`COUNT_TO_SWITCH_BUFFERS)) begin
      direction_of_dataflow <= ~direction_of_dataflow;
      in_data_counter <= 0;
    end
    if (in_data_counter==(`COUNT_TO_SWITCH_BUFFERS-1)) begin
      first_time_wait <= 1;
      ram_we <= 1'b1;
      ram_addr <= ram_start_addr-1;
      out_data_counter <= out_data_counter+1;
    end
    if (((in_data_counter-out_data_counter)<(`COUNT_TO_SWITCH_BUFFERS-1)) && ((in_data_counter-out_data_counter)!=0)) begin
      last_part <= 1;
    end
  end    
end
*/

reg flushed;
reg [1:0] write_state;
always @(posedge clk) begin
  if (~resetn) begin
    in_data_counter  <= 0;
    direction_of_dataflow <= 0;
    write_state <= 0;
  end
  else begin
    case(write_state)
    0: begin
      if (data_valid && mem_ctrl_data_last) begin
        in_data_counter <= in_data_counter + 1;
        direction_of_dataflow <= ~direction_of_dataflow;
        write_state <= 1;
        //in_data_counter stays wherever it is
      end
      else if (data_valid) begin
        write_state <= 0;
        if (in_data_counter==(`COUNT_TO_SWITCH_BUFFERS-1)) begin
          direction_of_dataflow <= ~direction_of_dataflow;
        end
        if (in_data_counter==(2*`COUNT_TO_SWITCH_BUFFERS-1)) begin
          direction_of_dataflow <= ~direction_of_dataflow;
          in_data_counter <= 0;
        end
        else begin
          in_data_counter <= in_data_counter + 1;
        end
      end
    end

    1:  begin
      if (flushed) begin
        direction_of_dataflow <= 0;
        in_data_counter <= 0;
        write_state <= 0;
      end
      else begin
        write_state <= 1;
      end
    end
    endcase
  end
end

reg [1:0] read_state;
reg out_valid_internal;
reg mem_ctrl_data_last_delayed;
reg data_valid_delayed;
reg [`RAM_PORT_AWIDTH+`LOG_NUM_CRAMS-1:0] ram_addr_int;
reg ram_we_int;



always @(posedge clk) begin
  mem_ctrl_data_last_delayed <= mem_ctrl_data_last;
  data_valid_delayed <= data_valid;
  ram_addr <= ram_addr_int;
  ram_we <= ram_we_int;
end

always @(posedge clk) begin
  if (~resetn) begin
    out_data_counter  <= 0;
    ram_we_int <= 0;
    read_state <= 0;
    out_valid_internal <= 0;
    flushed <= 1;
    ram_start_addr_int <= 0;
  end
  else begin
    case(read_state)
    0: begin
        if (data_valid & (in_data_counter==(`COUNT_TO_SWITCH_BUFFERS-1))) begin
          ram_we_int <= 1'b1;
          ram_addr_int <= ram_start_addr;
          ram_start_addr_int <= ram_start_addr+1;
          out_data_counter <= 0;
          read_state <= 1;
          flushed <= 0;
        end
        else begin
          ram_we_int <= 1'b0;
        end
    end

    1: begin
        if (data_valid && mem_ctrl_data_last) begin
          read_state <= 2;
          ram_we_int <= 1'b1;
          ram_addr_int <= ram_start_addr_int;
          ram_start_addr_int <= ram_start_addr_int+1;
          out_data_counter <= out_data_counter+1;
          out_data_counter_snap <= out_data_counter+1;
        end
        else if (data_valid) begin
          read_state <= 1;
          ram_we_int <= 1'b1;
          if (out_data_counter==(2*`COUNT_TO_SWITCH_BUFFERS-1)) begin
            ram_addr_int <= ram_start_addr_int;
            ram_start_addr_int <= ram_start_addr_int+1;
          end
          else if (out_data_counter == (`COUNT_TO_SWITCH_BUFFERS-1)) begin
            ram_addr_int <= ram_start_addr_int;
            ram_start_addr_int <= ram_start_addr_int+1;
          end
          else begin
	          ram_addr_int <= ram_addr_int + 4;
          end
          if (out_data_counter==(2*`COUNT_TO_SWITCH_BUFFERS-1)) begin
            out_data_counter <= 0;
          end
          else begin
            out_data_counter <= out_data_counter+1;
          end
        end 
        else begin
          ram_we_int <= 1'b0;
        end
        flushed <= 0;
    end

    2: begin
        //we want to go for 40 more cycles
        if (out_data_counter==(out_data_counter_snap+`COUNT_TO_SWITCH_BUFFERS-1)) begin
          out_data_counter <= 0;
          read_state <= 0;
          out_valid_internal <= 0;
          flushed <= 1;
          ram_we_int <= 1'b0;
        end
        else begin
          out_data_counter <= out_data_counter+1;
          read_state <= 2;
          out_valid_internal <= 1;
          ram_we_int <= 1'b1;
	        ram_addr_int <= ram_addr_int + 4;
          flushed <= 0;
        end
    end
    endcase
  end
end


wire out_valid;
assign out_valid = data_valid | out_valid_internal;

assign ready = flushed;

wire [`RAM_PORT_DWIDTH-1:0] data_out_ping;
wire [`RAM_PORT_DWIDTH-1:0] data_out_pong;
wire [`RAM_PORT_DWIDTH-1:0] ram_data_out_internal;
assign ram_data_out_internal = direction_of_dataflow ? data_out_ping : data_out_pong;

genvar i;
generate for (i=0;i<`RAM_PORT_DWIDTH;i=i+1) begin
  assign ram_data_out[i] = ram_data_out_internal[`RAM_PORT_DWIDTH-1-i];
end endgenerate

//always @(posedge clk) begin
//  ram_data_out <= ram_data_out_wire;
//end

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

wire ping_valid;
// if load_unload is 0 (i.e. direction_of_data_flow is 0), then
// data is being loaded (left to right). so, we need to use
// the data_valid signal.
// if load_unload is 1 (i.e. direction_of_data_flow is 1), then
// data is being unloaded (top to bottom). so, we need to use
// the out_valid signal.                 
assign ping_valid = direction_of_dataflow ? out_valid : data_valid;


//reg [`MEM_CTRL_DWIDTH-1:0] mem_ctrl_data_in_reg;
//always @(posedge clk) begin
//  mem_ctrl_data_in_reg <= mem_ctrl_data_in;
//end

//this is the left of the figure of swizzle logic we drew in the mantra paper
ping_buffer u_ping (
  .data_in(mem_ctrl_data_in),
  .data_out(data_out_ping),
  .load_unload(direction_of_dataflow),
  .valid(ping_valid),
  .clk(clk)
);

wire pong_valid;
// if load_unload is 0 (i.e. opp_direction_of_data_flow is 0), then
// data is being loaded (left to right). so, we need to use
// the data_valid signal.
// if load_unload is 1 (i.e. opp_direction_of_data_flow is 1), then
// data is being unloaded (top to bottom). so, we need to use
// the out_valid signal.                 
assign pong_valid = opp_direction_of_dataflow ? out_valid : data_valid;

//this is the right of the figure of swizzle logic we drew in the mantra paper
pong_buffer u_pong (
  .data_in(mem_ctrl_data_in),
  .data_out(data_out_pong),
  .load_unload(opp_direction_of_dataflow),
  .valid(pong_valid),
  .clk(clk)
);

endmodule

