// Copyright 2021 The CFU-Playground Authors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

`include "defines.v"
`include "dpram.v"
`include "controller.v"
`include "comefa.v"
`include "buffers.v"
`include "swizzle.d2c.only_top.v"
`include "swizzle.c2d.only_top.v"
`include "rf.v"

`define WRITE_TO_INST_RAM 7'd3
`define READ_FROM_INST_RAM 7'd4
`define WRITE_TO_CRAM 7'd5
`define READ_FROM_CRAM 7'd6
`define EXECUTE_INSTRUCTIONS 7'd7

module Cfu (
  input               cmd_valid,
  output  reg         cmd_ready,
  input      [9:0]    cmd_payload_function_id,
  input      [31:0]   cmd_payload_inputs_0,
  input      [31:0]   cmd_payload_inputs_1,
  output  reg         rsp_valid,
  input               rsp_ready,
  output  reg   [31:0]rsp_payload_outputs_0,
  input               clk,
  input               reset
);

wire resetn;
assign resetn = ~reset;

wire [6:0] funct7;
reg [6:0] funct7_reg;
wire [2:0] funct3;
reg [2:0] funct3_reg;

wire check;
reg done_reg;
reg start_reg;

//The function_id part of the payload is 10 bits, and is logically
//split into two parts: funct3 and funct7. 
assign funct7 = cmd_payload_function_id[9:3];
assign funct3 = cmd_payload_function_id[2:0];

wire funct7_ored = |funct7;

wire swizzle_d2c_ready;
wire swizzle_c2d_ready;

wire [`DWIDTH-1:0] dram_data_out;
wire [`DWIDTH-1:0] dram_data_out_c2d;
reg [`DWIDTH-1:0] dram_data_out_c2d_delayed;
wire [`AWIDTH-1:0] dram_addr_out;
wire dram_we_out;

reg [31:0]   cmd_payload_inputs_0_reg;
reg [31:0]   cmd_payload_inputs_1_reg;
reg [9:0]    cmd_payload_function_id_reg;

/////////////////////////////////////////
// Op0: byte sum (unsigned)
/////////////////////////////////////////
wire [31:0] cfu_test;
assign cfu_test[31:0] =  cmd_payload_inputs_0_reg[7:0]   + cmd_payload_inputs_1_reg[7:0];
                    // cmd_payload_inputs_0[15:8]  + cmd_payload_inputs_1[15:8] +
                    // cmd_payload_inputs_0[23:16] + cmd_payload_inputs_1[23:16] +
                    // cmd_payload_inputs_0[31:24] + cmd_payload_inputs_1[31:24];

/*
/////////////////////////////////////////
// Op1: byte swap
/////////////////////////////////////////
wire [31:0] cfu1;
assign cfu1[31:24] =     cmd_payload_inputs_0_reg[7:0];
assign cfu1[23:16] =     cmd_payload_inputs_0_reg[15:8];
assign cfu1[15:8] =      cmd_payload_inputs_0_reg[23:16];
assign cfu1[7:0] =       cmd_payload_inputs_0_reg[31:24];

/////////////////////////////////////////
// Op2: bit reverse
/////////////////////////////////////////
wire [31:0] cfu2;
genvar n;
generate
    for (n=0; n<32; n=n+1) begin
        assign cfu2[n] =     cmd_payload_inputs_0_reg[31-n];
    end
endgenerate
*/

/////////////////////////////////////////
// Select output 
/////////////////////////////////////////
wire   [31:0]   rsp_payload_outputs_0_wire;
wire [31:0] val;
assign rsp_payload_outputs_0_wire = 
                                    (funct3_reg==3'd7) ? ( 
                                      (funct7_reg==7'd0) ? {32{1'b1}} :
                                      (funct7_reg==7'd1) ? done_reg   :
                                      (funct7_reg==7'd2) ? {32{1'b1}} : 32'b0
                                    ) :
                                    (funct3_reg==3'd6) ? (
                                      (funct7_reg==3'd0) ? dram_data_out_c2d:  //MSB 8 bits are ignored
                                      (funct7_reg==3'd1) ? dram_data_out_c2d: 32'b0
                                    ) :
                                    (funct3_reg==3'd5) ? (
                                      (funct7_reg==3'd0) ? {32{1'b1}}:
                                      (funct7_reg==3'd1) ? {32{1'b1}}:
                                      (funct7_reg==3'd2) ? swizzle_d2c_ready : 32'b0
                                    ) :
                                    (funct3_reg==3'd4) ? val : 
                                    (funct3_reg==3'd3) ? {32{1'b1}} :
                                    (funct3_reg==3'd2) ? {32{1'b1}} :
                                    (funct3_reg==3'd1) ? {32{1'b1}} : 
                                    (funct3_reg==3'd0) ? cfu_test : 32'b0;

//////////////////////////////////////////////////////////
//The reset signal on top of the CFU doesn't assert for
//long enough (a few clocks). So, we need a longer reset.
//Thus, we create our longer reset programatically.
//Long reset is asserted with cfu_op0 (i.e. funct3=0) and funct7=1.
//////////////////////////////////////////////////////////
reg long_reset_n;
always @(posedge clk) begin
  if (cmd_valid) begin
    if ((funct3==3'd0) && (funct7==7'd1)) begin
      long_reset_n <= 0;
    end
    else begin
      long_reset_n <= 1;
    end
  end
end

/////////////////////////////////////////
// State machine that registers CFU inputs
// and also wiggles the handshaking signals
// based on the type of request (one cycle 
// latency or two cycle latency).
/////////////////////////////////////////
reg [1:0] state;
always @(posedge clk) begin
  if (~resetn) begin
    state <= 0;
    cmd_ready <= 1;
  end
  else begin
    case(state)
      0: begin
        if (cmd_valid) begin
          //Register the inputs
          cmd_payload_inputs_0_reg <= cmd_payload_inputs_0;
          cmd_payload_inputs_1_reg <= cmd_payload_inputs_1;
          cmd_payload_function_id_reg <= cmd_payload_function_id;
          funct7_reg <= funct7;
          funct3_reg <= funct3;

          //If it is a single cycle transaction,
          //then we send response in the next cycle.
          if ((funct3==3'd0) ||  //cfu_op0 -> add
              (funct3==3'd1) ||  //cfu_op1 -> swap
              (funct3==3'd2) ||  //cfu_op2 ->
              (funct3==3'd3) ||  //cfu_op3 -> write instruction memory 
              (funct3==3'd5) ||  //cfu_op5 -> write comefa
              (funct3==3'd7)     //cfu_op7 -> start execution, check execution, set registers
              ) begin
            state <= 1;
          end

          //If it is 2 cycle transaction
          //then we send the response in two cycles.
          if (funct3==3'd4) begin  //cfu_op4 -> read instruction memory
            state <= 2;
          end

          if (funct3==3'd6)  begin   //cfu_op6 -> read comefa
            state <= 3;
          end

          cmd_ready <= 1'b0;
          rsp_valid <= 1'b0;
        end
        else begin
          cmd_ready <= 1'b1;
          rsp_valid <= 1'b0;
        end
      end

      //Send response by asserting rsp_valid
      //and setting the output payload field.
      1: begin
        rsp_valid <= 1'b1;
        rsp_payload_outputs_0 <= rsp_payload_outputs_0_wire;
        state <= 0;
        cmd_ready <= 1'b1;
      end

      //Just wait for 1 clock
      2: begin
        state <= 1;
        rsp_valid <= 1'b0;
        cmd_ready <= 1'b0;
      end

      3: begin
        if (dram_we_out == 1'b1) begin
          rsp_valid <= 1'b1;
          rsp_payload_outputs_0 <= rsp_payload_outputs_0_wire;
          state <= 0;
          cmd_ready <= 1'b1;
        end
      end 

    endcase
    
  end
end

reg [`AWIDTH+`LOG_NUM_CRAMS-1:0] cram_addr_for_read_full;
wire [`AWIDTH-1:0] cram_addr_for_read;
wire [`LOG_NUM_CRAMS-1:0] ram_num_for_read;
assign cram_addr_for_read = cram_addr_for_read_full[`AWIDTH-1:0];
assign ram_num_for_read = cram_addr_for_read_full[`LOG_NUM_CRAMS+`AWIDTH-1:`AWIDTH];
wire pe_top;
wire pe_bot;
wire pe_ram0_to_ram1;
wire pe_ram1_to_ram2;
wire pe_ram2_to_ram3;
wire [`DWIDTH-1:0] cram0_q2;
wire [`DWIDTH-1:0] cram1_q2;
wire [`DWIDTH-1:0] cram2_q2;
wire [`DWIDTH-1:0] cram3_q2;


wire [`DWIDTH-1:0] stored_instruction;
reg [`AWIDTH-1:0] stored_instr_start_addr;
reg [`AWIDTH-1:0] stored_instr_end_addr;

wire [`AWIDTH-1:0] exec_instr_addr;
wire [`DWIDTH-1:0] exec_instruction;

wire [`AWIDTH-1:0] cram_addr_in;
wire [`DWIDTH-1:0] cram_data_in;

wire [`AWIDTH-1:0] swz_cram_addr;
wire [`AWIDTH+`LOG_NUM_CRAMS-1:0] swz_cram_addr_full;
wire [`DWIDTH-1:0] swz_cram_data;
wire load_cram;
wire [`LOG_NUM_CRAMS-1:0] ram_num_for_write;

reg [`RF_MAX_PRECISION-1:0] rf0;
reg [`RF_MAX_PRECISION-1:0] rf1;
reg [`RF_MAX_PRECISION-1:0] rf2;
reg [`RF_MAX_PRECISION-1:0] rf3;

wire start;
wire done;
wire execute;
wire cram0_we;
wire cram1_we;
wire cram2_we;
wire cram3_we;

wire stored_instr_we_cpu;
wire [8:0] stored_instr_addr_cpu;
wire [31:0] stored_instr_datain_cpu;
wire [31:0] stored_instr_dataout_cpu;

wire stored_instr_we_internal;
wire [`AWIDTH-1:0] stored_instr_addr_internal;
wire [`DWIDTH-1:0] stored_instr_datain_internal;
wire [`DWIDTH-1:0] stored_instr_dataout_internal;

//Choose what we do with the Comefa RAMs:
// (1) Execute instructions 
// (2) Read or write data
assign swz_cram_addr = swz_cram_addr_full[`AWIDTH-1:0];
assign ram_num_for_write = swz_cram_addr_full[`LOG_NUM_CRAMS+`AWIDTH-1:`AWIDTH];
assign cram_addr_in  = execute ? exec_instr_addr : swz_cram_addr;
assign cram_data_in  = execute ? exec_instruction : swz_cram_data;
assign cram0_we      = execute ? 1'b1 : (load_cram && (ram_num_for_write==0)) ? 1'b1 : 1'b0;
assign cram1_we      = execute ? 1'b1 : (load_cram && (ram_num_for_write==1)) ? 1'b1 : 1'b0;
assign cram2_we      = execute ? 1'b1 : (load_cram && (ram_num_for_write==2)) ? 1'b1 : 1'b0;
assign cram3_we      = execute ? 1'b1 : (load_cram && (ram_num_for_write==3)) ? 1'b1 : 1'b0;

/////////////////////////////////////////
//Comefa RAM - Will contain the data (inputs
//temporaries, results, etc). This is the RAM
//that will execute instructions on this data.
//Port 1 - Used to write into CRAM
//Port 2 - Used to read from CRAM
/////////////////////////////////////////
//We have separate address spaces for comefa
//RAMs, DRAM and instruction RAM.
//For comefa RAMs, the address bus with (while
//reading and writing) is 9 (512x40), but we
//add two extra bits to select one of the 4
//crams.
/////////////////////////////////////////
comefa u_comefa_ram0(
  .addr1(cram_addr_in),
  .d1(cram_data_in), 
  .we1(cram0_we), 
  .addr2(cram_addr_for_read),
  .q2(cram0_q2),
  .pe_top(pe_top),
  .pe_bot(pe_ram0_to_ram1),
  .clk(clk)
);

comefa u_comefa_ram1(
  .addr1(cram_addr_in),
  .d1(cram_data_in), 
  .we1(cram1_we), 
  .addr2(cram_addr_for_read),
  .q2(cram1_q2),
  .pe_top(pe_ram0_to_ram1),
  .pe_bot(pe_ram1_to_ram2),
  .clk(clk)
);

comefa u_comefa_ram2(
  .addr1(cram_addr_in),
  .d1(cram_data_in), 
  .we1(cram2_we), 
  .addr2(cram_addr_for_read),
  .q2(cram2_q2),
  .pe_top(pe_ram1_to_ram2),
  .pe_bot(pe_ram2_to_ram3),
  .clk(clk)
);

comefa u_comefa_ram3(
  .addr1(cram_addr_in),
  .d1(cram_data_in), 
  .we1(cram3_we), 
  .addr2(cram_addr_for_read),
  .q2(cram3_q2),
  .pe_top(pe_ram2_to_ram3),
  .pe_bot(pe_bot),
  .clk(clk)
);

  
/////////////////////////////////////////
//Normal BRAM - Will store instructions
/////////////////////////////////////////
/////////////////////////////////////////
// Op3: Writing to RAM
/////////////////////////////////////////
/////////////////////////////////////////
// Op4: Reading from RAM
/////////////////////////////////////////
assign stored_instr_we_cpu = (funct3_reg==`WRITE_TO_INST_RAM) & (~(funct3_reg==`READ_FROM_INST_RAM)) & cmd_valid & cmd_ready;
assign stored_instr_addr_cpu = cmd_payload_inputs_0_reg;
assign stored_instr_datain_cpu = cmd_payload_inputs_1_reg;
assign val = stored_instr_dataout_cpu;

assign stored_instr_we_internal = 1'b0;
assign stored_instr_datain_internal = {`DWIDTH{1'b0}};

dpram #(.AWIDTH(`AWIDTH), .NUM_WORDS(`NUM_LOCATIONS), .DWIDTH(`STORED_INST_DATA_WIDTH)) u_instr_ram(
  .clk(clk),
  .address_a(stored_instr_addr_cpu), //port to write from cpu
  .wren_a(stored_instr_we_cpu),
  .data_a(stored_instr_datain_cpu),
  .out_a(stored_instr_dataout_cpu),
  .address_b(stored_instr_addr_internal), //port to read internally
  .wren_b(stored_instr_we_internal),
  .data_b(stored_instr_datain_internal),
  .out_b(stored_instr_dataout_internal)
);

//For now, instead of sending instructions from CPU,
//I'm just loading them from a file.
initial begin
  //$readmemb("/home/data1/aman/CFU-Playground/proj/comefa/instructions.eltwiseadd.dat", u_instr_ram.ram);
  $readmemb("/home/data1/aman/CFU-Playground/proj/comefa/instructions.rfadd.dat", u_instr_ram.ram);
end

/////////////////////////////////////////
// Register file (flop based).
// These registers are used in OOOR transactions.
/////////////////////////////////////////
wire [`RF_ADDR_WIDTH-1:0] rf_addr;
wire [`RF_DATA_WIDTH-1:0] rf_data;
wire [`RF_DATA_WIDTH-1:0] rf0;
wire [`RF_DATA_WIDTH-1:0] rf1;
wire [`RF_DATA_WIDTH-1:0] rf2;
wire [`RF_DATA_WIDTH-1:0] rf3;
wire rf_wren;

assign rf_wren = ((funct3_reg==`EXECUTE_INSTRUCTIONS) & (funct7_reg==2) & cmd_valid & cmd_ready);
assign rf_data = cmd_payload_inputs_0_reg;
assign rf_addr = cmd_payload_inputs_1_reg;

rf u_rf (
  .clk(clk),
  .resetn(long_reset_n),
  .addr(rf_addr),
  .wren(rf_wren),
  .data(rf_data),
  .rf0(rf0),
  .rf1(rf1),
  .rf2(rf2),
  .rf3(rf3)
);

/////////////////////////////////////////
//Controller - Will read stored instructions
//from normal BRAM and send executable (micro)instructions
//to Comefa RAM
/////////////////////////////////////////
reg [`AWIDTH-1:0] stored_inst_start_addr;
reg [`AWIDTH-1:0] stored_inst_end_addr;

always @(posedge clk) begin
  if (~resetn) begin
    stored_inst_start_addr <= 0;
    stored_inst_end_addr <= 0;
  end
  else if ((funct3_reg==`EXECUTE_INSTRUCTIONS) & (funct7_reg==2) & cmd_valid) begin
    stored_inst_start_addr <= cmd_payload_inputs_0_reg;
    stored_inst_end_addr <= cmd_payload_inputs_1_reg;
  end
  else if (done) begin
    stored_inst_start_addr <= 0;
    stored_inst_end_addr <= 0;
  end
end

always @(posedge clk) begin
  if (~resetn) begin
    start_reg <= 1'b0;
  end
  else if ((funct3_reg==`EXECUTE_INSTRUCTIONS) & (funct7_reg==0) & cmd_valid) begin
    start_reg <= 1'b1;
  end
  else if (done) begin
    start_reg <= 1'b0;
  end
end

assign check = ((funct3_reg==`EXECUTE_INSTRUCTIONS) & (funct7_reg==1) & cmd_valid);

always @(posedge clk) begin
  if (~resetn) begin
    done_reg <= 1'b0;
  end
  else if (done) begin
    done_reg <= 1'b1;
  end
end


//TODO: Change start and end addr come from the CPU
//instead of being hardcoded
controller u_ctrl (
  .clk(clk),
  .rstn(long_reset_n),
  .start(start_reg),
  .done(done),
  .stored_instr_addr(stored_instr_addr_internal),
  .stored_instr_start_addr(stored_inst_start_addr),
  .stored_instr_end_addr(stored_inst_end_addr),
  .stored_instruction(stored_instr_dataout_internal),
  .exec_instr_addr(exec_instr_addr),
  .exec_instruction(exec_instruction),
  .execute(execute),
  .rf0(rf0),
  .rf1(rf1),
  .rf2(rf2),
  .rf3(rf3)
);

/////////////////////////////////////////
//Swizzle logic to transpose data coming
//from DRAM into CRAM
/////////////////////////////////////////

reg dram_data_valid;
reg dram_data_last;
always @(posedge clk) begin
  if (~long_reset_n) begin
    dram_data_valid <= 0;
    dram_data_last <= 0;
  end
  else if (cmd_valid & cmd_ready) begin
    dram_data_valid <= (funct3==`WRITE_TO_CRAM) & ((funct7==0) || (funct7==1));
    dram_data_last <= (funct3==`WRITE_TO_CRAM) & (funct7==1);
  end
  else begin
    dram_data_valid <= 0;
    dram_data_last <= 0;
  end
end
wire [`DWIDTH-1:0] dram_data_in;
//assign dram_data_in = {cmd_payload_inputs_1_reg[7:0], cmd_payload_inputs_0_reg[31:0]};
//Need to do the following. Using generate statements below.
//assign dram_data_in = {cmd_payload_inputs_0_reg[0:31], cmd_payload_inputs_1_reg[0:7]};
genvar i;
generate for (i=0;i<32;i=i+1) begin
  assign dram_data_in[8+i] = cmd_payload_inputs_0_reg[31-i];
end endgenerate
generate for (i=0;i<8;i=i+1) begin
  assign dram_data_in[i] = cmd_payload_inputs_1_reg[7-i];
end endgenerate

//+LOG_NUM_CRAMS below because higher order bits
//to decode which of the N crams to address.
wire [`RAM_PORT_AWIDTH+`LOG_NUM_CRAMS-1:0] cram_start_wr_addr;
assign cram_start_wr_addr = cmd_payload_inputs_1_reg[`RAM_PORT_AWIDTH+`LOG_NUM_CRAMS+8-1:8];

//TODO: Need to fix the interface to be cleaner. May be based on address.
swizzle_dram_to_cram u_swz_d2c (
  .data_valid(dram_data_valid),
  .clk(clk),
  .resetn(long_reset_n),
  .mem_ctrl_data_in(dram_data_in),
  .mem_ctrl_data_last(dram_data_last),
  .ram_start_addr(cram_start_wr_addr),
  .ram_data_out(swz_cram_data),
  .ram_addr(swz_cram_addr_full),
  .ram_we(load_cram),
  .ready(swizzle_d2c_ready)
);

/////////////////////////////////////////
//Swizzle logic to transpose data coming
//from CRAM into DRAM
/////////////////////////////////////////

reg cram_data_valid;
reg[31:0] num_elements_to_read;
reg [`AWIDTH-1:0] starting_addr_while_reading;
reg [31:0] data_read_count;
reg ram_data_last;
reg first_time;
/*
always @(posedge clk) begin
  if (~long_reset_n) begin
    cram_data_valid <= 0;
    data_read_count <= 0;
    cram_addr_for_read_full <= 0;
    ram_data_last <= 0;
    first_time <= 0;
  end
  else if (swizzle_c2d_ready) begin
    cram_data_valid <= 0;
  end
  else if (cmd_valid & cmd_ready & (funct3==`READ_FROM_CRAM) & (funct7==0)) begin
    if (first_time==0) begin
    cram_data_valid <= 1;
    first_time <= 1; 
    data_read_count <= 0;
    starting_addr_while_reading <= cmd_payload_inputs_0;
    cram_addr_for_read_full <= cmd_payload_inputs_0;
    num_elements_to_read <= cmd_payload_inputs_1;
    ram_data_last <= 0;
    end
    else begin
    cram_data_valid <= 1;
    cram_addr_for_read_full <= cram_addr_for_read + 4;
    data_read_count <= data_read_count + 1;
    first_time <= 0;
    end
  end
  //else if (cmd_valid & cmd_ready & (funct3==`READ_FROM_CRAM) & (funct7==0)) begin
  //  cram_data_valid <= 1;
  //  first_time <= 0;
  //  cram_addr_for_read_full <= cram_addr_for_read + 4;
  //  ram_data_last <= 0;
  //end
  else if (cmd_valid & cmd_ready & (funct3==`READ_FROM_CRAM) & (funct7==1)) begin
    cram_data_valid <= 1;
    ram_data_last <= 1;
    first_time <= 0;
    cram_addr_for_read_full <= cmd_payload_inputs_0; //starting address
    num_elements_to_read <= cmd_payload_inputs_1;
  end
  else if (cram_data_valid && first_time) begin
    data_read_count <= data_read_count + 1;
    cram_addr_for_read_full <= cram_addr_for_read + 4;
    ram_data_last <= 0;
  end
  else begin
    cram_data_valid <= 0;
  end
end
*/

reg [2:0] cram_read_state;

always @(posedge clk) begin
  if (~long_reset_n) begin
    cram_data_valid <= 0;
    data_read_count <= 0;
    cram_addr_for_read_full <= 0;
    cram_read_state <= 0;
  end
  else begin
    case (cram_read_state)
    0: begin
      if (cmd_valid & cmd_ready & (funct3==`READ_FROM_CRAM) & (funct7==0)) begin
        cram_data_valid <= 0;
        data_read_count <= 0;
        starting_addr_while_reading <= cmd_payload_inputs_0;
        cram_addr_for_read_full <= cmd_payload_inputs_0;
        num_elements_to_read <= cmd_payload_inputs_1;
        cram_read_state <= 1;
      end
      else begin
        ram_data_last <= 0;
        cram_data_valid <= 0;  
      end
    end  

    1: begin
      if (data_read_count == `COUNT_TO_SWITCH_BUFFERS+1) begin
        cram_read_state <= 3;
        cram_data_valid <= 0;
        cram_addr_for_read_full <= starting_addr_while_reading+1;
        starting_addr_while_reading<=starting_addr_while_reading+1;
      end 
      else begin
        cram_data_valid <= 1;
        cram_addr_for_read_full <= cram_addr_for_read + 4;
        data_read_count <= data_read_count + 1;
      end
      ram_data_last <= 0;
    end 

    2: begin
      if (cmd_valid & cmd_ready & (funct3==`READ_FROM_CRAM) & (funct7==0)) begin 
        cram_data_valid <= 1;
        data_read_count <= data_read_count + 1;
        ram_data_last <= 0;
        if ((data_read_count == 2*`COUNT_TO_SWITCH_BUFFERS) || (data_read_count == 3*`COUNT_TO_SWITCH_BUFFERS)) begin
          cram_addr_for_read_full <= starting_addr_while_reading+1;
          starting_addr_while_reading<=starting_addr_while_reading+1;
        end
        else begin
          cram_addr_for_read_full <= cram_addr_for_read + 4;
        end
      end
      else if (cmd_valid & cmd_ready & (funct3==`READ_FROM_CRAM) & (funct7==1)) begin //last
        cram_data_valid <= 1;
        data_read_count <= data_read_count + 1;
        cram_addr_for_read_full <= cram_addr_for_read + 4;
        ram_data_last <= 1;
        cram_read_state <= 0;
      end
      else begin
        cram_data_valid <= 0;
      end
    end

    3: begin
      cram_data_valid <= 0;
      cram_read_state <= 2;
    end
    endcase
  end
end


wire [`DWIDTH-1:0] transposed_data_from_cram;
assign transposed_data_from_cram = (ram_num_for_read==0) ? cram0_q2 :
                                   (ram_num_for_read==1) ? cram1_q2 :
                                   (ram_num_for_read==2) ? cram2_q2 :
                                   (ram_num_for_read==3) ? cram3_q2 : 40'b0;

reg cram_data_valid_delayed;
always @(posedge clk) begin
  cram_data_valid_delayed <= cram_data_valid;
end

wire [`DWIDTH-1:0] transposed_data_c2d;
generate for (i=0;i<`DWIDTH;i=i+1) begin
  assign transposed_data_c2d[i] = transposed_data_from_cram[`DWIDTH-1-i];
end endgenerate

reg ram_data_last_delayed;
always @(posedge clk) begin
  ram_data_last_delayed <= ram_data_last;
end

//TODO: Need to fix the interface to be cleaner. May be based on address.
swizzle_cram_to_dram u_swz_c2d (
  .data_valid(cram_data_valid),
  .clk(clk),
  .resetn(long_reset_n),
  .ram_data_in(transposed_data_c2d),
  .ram_data_last(ram_data_last),
  .mem_ctrl_data_out(dram_data_out), //goes to CPU for now
  .mem_ctrl_addr(dram_addr_out), //unconnected for now
  .mem_ctrl_addr_start(0), //TODO: hardcoding for now; need to be configured by CPU
  .mem_ctrl_we(dram_we_out), //unconnected for now
  .ready(swizzle_c2d_ready)
);

generate for (i=0;i<`DWIDTH;i=i+1) begin
  assign dram_data_out_c2d[i] = dram_data_out[`DWIDTH-1-i];
end endgenerate

always @(posedge clk) begin
  dram_data_out_c2d_delayed <= dram_data_out_c2d;
end

endmodule
