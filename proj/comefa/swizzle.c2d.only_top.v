//Assumption: Currently the design works properly only if
//MEM_CTRL_DWIDTH == RAM_PORT_DWIDTH
`define MEM_CTRL_DWIDTH 40
`define MEM_CTRL_AWIDTH 16
`define RAM_PORT_DWIDTH 40
`define RAM_PORT_AWIDTH 9
`define NUM_BUFFERS     80
`define LOG_NUM_BUFFERS 7
`define MEM_CTRL_START_ADDR  12'h0
`define COUNT_TO_SWITCH_BUFFERS 40
`define LOG_COUNT_TO_SWITCH_BUFFERS 6
`define MEM_CTRL_NUM_WORDS 512

module swizzle_cram_to_dram(
  //this input tells whether the input data is valid or not
  input  data_valid,
  //clock and reset ports
  input  clk,
  input  resetn,
  //ram interface - data comes in
  input       [`RAM_PORT_DWIDTH-1:0] ram_data_in,
  input       ram_data_last,
  //memory controller interface - data goes out
  output      [`MEM_CTRL_DWIDTH-1:0] mem_ctrl_data_out,
  output  reg [`MEM_CTRL_AWIDTH-1:0] mem_ctrl_addr,
  input       [`MEM_CTRL_AWIDTH-1:0] mem_ctrl_addr_start,
  output  reg                        mem_ctrl_we,
  output  reg ready,
  input       dma_mode
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


reg [1:0] write_state;
always @(posedge clk) begin
  if (~resetn) begin
    in_data_counter  <= 0;
    direction_of_dataflow <= 0;
    write_state <= 0;
    ready <= 0;
  end
  else begin
    case(write_state)
    0: begin
      if (data_valid && (in_data_counter==(`COUNT_TO_SWITCH_BUFFERS-1))) begin
        ready <= 1;
        in_data_counter <= in_data_counter + 1;
      end
      else if (data_valid && (in_data_counter==(`COUNT_TO_SWITCH_BUFFERS))) begin
        write_state <= 2;
        direction_of_dataflow <= ~direction_of_dataflow;
        //in_data_counter <= in_data_counter + 1;
        ready <= 0;
      end
      else if (data_valid) begin
        in_data_counter <= in_data_counter + 1;
        write_state <= 0;
      end
    end

    1:  begin
      if (data_valid & ram_data_last) begin
          write_state <= 0;
          in_data_counter  <= 0;
          direction_of_dataflow <= 0;
      end
      else if (data_valid) begin
        write_state <= 1;
        if (in_data_counter==(`COUNT_TO_SWITCH_BUFFERS-1)) begin
          direction_of_dataflow <= ~direction_of_dataflow;
          in_data_counter <= in_data_counter + 1;
        end
        else if (in_data_counter==(2*`COUNT_TO_SWITCH_BUFFERS-1)) begin
          direction_of_dataflow <= ~direction_of_dataflow;
          in_data_counter <= 0;
        end
        else begin
          in_data_counter <= in_data_counter + 1;
        end
      end  
      ready <= 0;
    end

    2: begin
      //dont want to increment in_data_counter
      write_state <= 1;
    end
    endcase
  end
end

reg [1:0] read_state;
reg flag;
always @(posedge clk) begin
  if (~resetn) begin
    out_data_counter  <= 0;
    mem_ctrl_we <= 0;
    read_state <= 0;
    flag <= 0;
  end
  else begin
    case(read_state)
    0: begin
        if (data_valid & (in_data_counter==(`COUNT_TO_SWITCH_BUFFERS))) begin
          mem_ctrl_addr <= mem_ctrl_addr_start;
          read_state <= 1;
          if (dma_mode) begin
            flag <= 0;
            mem_ctrl_we <= 1'b1;
            out_data_counter <= 1;
          end
          else begin
            flag <= 1;
            mem_ctrl_we <= 1'b0;
            out_data_counter <= 0;
          end
        end
        else begin
          mem_ctrl_we <= 1'b0;
        end
    end

    1: begin
        if (flag) begin //one extra here
          flag <= 0;
          mem_ctrl_we <= 1'b1;
          out_data_counter <= out_data_counter+1;
          read_state <= 1;
        end
        else if (data_valid && ram_data_last) begin
          read_state <= 2;
          if (dma_mode) begin
            mem_ctrl_we <= 1'b0;
          end
          else begin
            mem_ctrl_we <= 1'b1;
          end
	        mem_ctrl_addr <= mem_ctrl_addr + 1;
          out_data_counter <= 0;
        end
        else if (data_valid) begin
          read_state <= 1;
          mem_ctrl_we <= 1'b1;
          if (out_data_counter == (`COUNT_TO_SWITCH_BUFFERS-1)) begin
            //mem_ctrl_addr <= mem_ctrl_addr_start;
	          mem_ctrl_addr <= mem_ctrl_addr + 1;
          end
          else begin
	          mem_ctrl_addr <= mem_ctrl_addr + 1;
          end
          if (out_data_counter==(2*`COUNT_TO_SWITCH_BUFFERS-1)) begin
            out_data_counter <= 0;
          end
          else begin
            out_data_counter <= out_data_counter+1;
          end
        end 
        else begin
          mem_ctrl_we <= 1'b0;
        end
    end

    2: begin
          read_state <= 0;
          mem_ctrl_we <= 0;
          mem_ctrl_addr <= 0;
          out_data_counter <= 0;
    end

    endcase
  end
end

wire [`RAM_PORT_DWIDTH-1:0] data_out_ping;
wire [`RAM_PORT_DWIDTH-1:0] data_out_pong;
assign mem_ctrl_data_out = direction_of_dataflow ? data_out_ping : data_out_pong;

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

wire data_valid_internal;
assign data_valid_internal = data_valid & ~(ready);

wire ping_valid;
//assign ping_valid = direction_of_dataflow ? out_valid : data_valid;
assign ping_valid = data_valid_internal;

//this is the left of the figure of swizzle logic we drew in the mantra paper
ping_buffer u_ping (
  .data_in(ram_data_in),
  .data_out(data_out_ping),
  .load_unload(direction_of_dataflow),
  .valid(ping_valid),
  .clk(clk)
);

wire pong_valid;
//assign pong_valid = opp_direction_of_dataflow ? out_valid : data_valid;
assign pong_valid = data_valid_internal;

//this is the right of the figure of swizzle logic we drew in the mantra paper
pong_buffer u_pong (
  .data_in(ram_data_in),
  .data_out(data_out_pong),
  .load_unload(opp_direction_of_dataflow),
  .valid(pong_valid),
  .clk(clk)
);

endmodule
