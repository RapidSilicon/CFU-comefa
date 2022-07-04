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
`include "swizzle.d2c.passthrough.v"
`include "swizzle.c2d.passthrough.v"

`define WRITE_TO_INST_RAM 7'd3
`define READ_FROM_INST_RAM 7'd4
`define WRITE_TO_DATA_RAM 7'd5
`define READ_FROM_DATA_RAM 7'd6
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

wire [6:0] funct7;
reg [6:0] funct7_reg;
wire [2:0] funct3;
reg [2:0] funct3_reg;

wire check;
reg done_reg;
reg start_reg;

assign funct7 = cmd_payload_function_id[9:3];
assign funct3 = cmd_payload_function_id[2:0];

wire funct7_ored = |funct7;

//Reset on cfu_op0 when funct7 is sent as 1
assign resetn = ~((funct7_ored==1'b1) && (funct3==3'd0));


wire [`DWIDTH-1:0] dram_data;
wire [`AWIDTH-1:0] dram_addr;
wire dram_we;

assign cmd_ready = rsp_ready;

reg stage1;
reg [31:0]   cmd_payload_inputs_0_reg;
reg [31:0]   cmd_payload_inputs_1_reg;
reg [9:0]    cmd_payload_function_id_reg;
always @(posedge clk) begin
  if (cmd_valid & (~funct7_ored)) begin
    cmd_payload_inputs_0_reg <= cmd_payload_inputs_0;
    cmd_payload_inputs_1_reg <= cmd_payload_inputs_1;
    cmd_payload_function_id_reg <= cmd_payload_function_id;
  end
end

always @(posedge clk) begin
  if (cmd_valid) begin
    funct7_reg <= funct7;
    funct3_reg <= funct3;
  end
end

always @(posedge clk) begin
  if (cmd_valid) begin
    stage1 <= 1;
  end
  else begin
    stage1 <= 0;
  end
end

reg stage2;
always @(posedge clk) begin
  stage2 <= stage1;
end


/////////////////////////////////////////
// Op0: byte sum (unsigned)
/////////////////////////////////////////
wire [31:0] cfu0;
reg [31:0] cfu0_reg;
assign cfu0[31:0] =  cmd_payload_inputs_0_reg[7:0]   + cmd_payload_inputs_1_reg[7:0];
                    // cmd_payload_inputs_0[15:8]  + cmd_payload_inputs_1[15:8] +
                    // cmd_payload_inputs_0[23:16] + cmd_payload_inputs_1[23:16] +
                    // cmd_payload_inputs_0[31:24] + cmd_payload_inputs_1[31:24];

/////////////////////////////////////////
// Op1: byte swap
/////////////////////////////////////////
wire [31:0] cfu1;
reg [31:0] cfu1_reg;
assign cfu1[31:24] =     cmd_payload_inputs_0_reg[7:0];
assign cfu1[23:16] =     cmd_payload_inputs_0_reg[15:8];
assign cfu1[15:8] =      cmd_payload_inputs_0_reg[23:16];
assign cfu1[7:0] =       cmd_payload_inputs_0_reg[31:24];

/////////////////////////////////////////
// Op2: bit reverse
/////////////////////////////////////////
wire [31:0] cfu2;
reg [31:0] cfu2_reg;
genvar n;
generate
    for (n=0; n<32; n=n+1) begin
        assign cfu2[n] =     cmd_payload_inputs_0_reg[31-n];
    end
endgenerate


/////////////////////////////////////////
// Select output 
/////////////////////////////////////////
wire   [31:0]   rsp_payload_outputs_0_wire;
wire [31:0] val;
assign rsp_payload_outputs_0_wire = 
                                    (funct3_reg==3'd7) ? ( funct7_reg ? done_reg : {32{1'b1}} ) :
                                    
                                    (funct3_reg==3'd6) ? dram_data : 
                                    (funct3_reg==3'd5) ? {32{1'b1}}:
                                    (funct3_reg==3'd4) ? val : 
                                    (funct3_reg==3'd3) ? {32{1'b1}} :
                                    (funct3_reg==3'd2) ? cfu2 :
                                    (funct3_reg==3'd1) ? cfu1 : 
                                    (funct3_reg==3'd0) ? cfu0 : 32'b0;

always @(posedge clk) begin
  rsp_payload_outputs_0 <= rsp_payload_outputs_0_wire;
  rsp_valid <= stage2;
end

/////////////////////////////////////////
// Comefa related logic
/////////////////////////////////////////

wire [`AWIDTH-1:0] addr2;
assign addr2 = {`AWIDTH{1'b0}};
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
wire [`AWIDTH-1:0] stored_instr_addr;
reg [`AWIDTH-1:0] stored_instr_start_addr;
reg [`AWIDTH-1:0] stored_instr_end_addr;

wire [`AWIDTH-1:0] exec_instr_addr;
wire [`DWIDTH-1:0] exec_instruction;

wire [`AWIDTH-1:0] cram_addr_in;
wire [`DWIDTH-1:0] cram_data_in;

wire [`AWIDTH-1:0] swz_cram_addr;
wire [`DWIDTH-1:0] swz_cram_data;
wire load_cram;
wire [31:0] ram_num;

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

reg dram_data_valid;
reg [`DWIDTH-1:0] dram_data;

wire stored_instr_we_cpu;
wire [8:0] stored_instr_addr_cpu;
wire [31:0] stored_instr_datain_cpu;
wire [31:0] stored_instr_dataout_cpu;

wire stored_instr_we_internal;
wire [`AWIDTH-1:0] stored_instr_addr_internal;
wire [`DWIDTH-1:0] stored_instr_datain_internal;
wire [`DWIDTH-1:0] stored_instr_dataout_internal;

assign cram_addr_in = execute ? exec_instr_addr : swz_cram_addr;
assign cram_data_in = execute ? exec_instruction : swz_cram_data;
assign cram0_we      = execute ? 1'b1 : (load_cram && (ram_num==0)) ? 1'b1 : 1'b0;
assign cram1_we      = execute ? 1'b1 : (load_cram && (ram_num==1)) ? 1'b1 : 1'b0;
assign cram2_we      = execute ? 1'b1 : (load_cram && (ram_num==2)) ? 1'b1 : 1'b0;
assign cram3_we      = execute ? 1'b1 : (load_cram && (ram_num==3)) ? 1'b1 : 1'b0;

/////////////////////////////////////////
//Comefa RAM - Will execute instructions
/////////////////////////////////////////
comefa u_comefa_ram0(
  .addr1(cram_addr_in),
  .d1(cram_data_in), 
  .we1(cram0_we), 
  .addr2(addr2),
  .q2(cram0_q2),
  .pe_top(pe_top),
  .pe_bot(pe_ram0_to_ram1),
  .clk(clk)
);

comefa u_comefa_ram1(
  .addr1(cram_addr_in),
  .d1(cram_data_in), 
  .we1(cram1_we), 
  .addr2(addr2),
  .q2(cram1_q2),
  .pe_top(pe_ram0_to_ram1),
  .pe_bot(pe_ram1_to_ram2),
  .clk(clk)
);

comefa u_comefa_ram2(
  .addr1(cram_addr_in),
  .d1(cram_data_in), 
  .we1(cram2_we), 
  .addr2(addr2),
  .q2(cram2_q2),
  .pe_top(pe_ram1_to_ram2),
  .pe_bot(pe_ram2_to_ram3),
  .clk(clk)
);

comefa u_comefa_ram3(
  .addr1(cram_addr_in),
  .d1(cram_data_in), 
  .we1(cram3_we), 
  .addr2(addr2),
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
assign stored_instr_we_cpu = ((funct3_reg==`WRITE_TO_INST_RAM) & stage1);
assign stored_instr_addr_cpu = cmd_payload_inputs_0_reg;
assign stored_instr_datain_cpu = cmd_payload_inputs_1_reg;
assign val = stored_instr_dataout_cpu;

assign stored_instr_we_internal = 1'b0;
assign stored_instr_datain_internal = {`DWIDTH{1'b0}};


dpram #(.AWIDTH(`AWIDTH), .NUM_WORDS(`NUM_LOCATIONS), .DWIDTH(`DWIDTH)) u_instr_ram(
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


initial begin
  $readmemb("/home/data1/aman/CFU-Playground/proj/comefa/instructions.dat", u_instr_ram.ram);
end

/////////////////////////////////////////
//Controller - Will read stored instructions
//from normal BRAM and send executable (micro)instructions
//to Comefa RAM
/////////////////////////////////////////

assign start = ((funct3_reg==`EXECUTE_INSTRUCTIONS) & (funct7_reg==0) & stage1);

always @(posedge clk) begin
  if (~resetn) begin
    start_reg <= 1'b0;
  end
  else if (start) begin
    start_reg <= 1'b1;
  end
  else if (done) begin
    start_reg <= 1'b0;
  end
end

assign check = ((funct3_reg==`EXECUTE_INSTRUCTIONS) & (funct7_reg==1) & stage1);

always @(posedge clk) begin
  if (~resetn) begin
    done_reg <= 1'b0;
  end
  else if (done) begin
    done_reg <= 1'b1;
  end
end

//TODO: Change all register settings to come from the CPU
//instead of being hardcoded
controller u_ctrl (
  .clk(clk),
  .rstn(resetn),
  .start(start_reg),
  .done(done),
  .stored_instr_addr(stored_instr_addr_internal),
  .stored_instr_start_addr(9'd3),
  .stored_instr_end_addr(9'd7),
  .stored_instruction(stored_instr_dataout_internal),
  .exec_instr_addr(exec_instr_addr),
  .exec_instruction(exec_instruction),
  .execute(execute),
  .rf0(8'b0),
  .rf1(8'b0),
  .rf2(8'b0),
  .rf3(8'b0)
);

/////////////////////////////////////////
//Swizzle logic (transposes data)
/////////////////////////////////////////

wire data_ram_data_valid;
assign data_ram_data_valid = ((funct3_reg==`WRITE_TO_DATA_RAM) & stage1);
wire [`DWIDTH-1:0] data_ram_datain_cpu;
assign data_ram_datain_cpu = {cmd_payload_inputs_1_reg[7:0], cmd_payload_inputs_0_reg[31:0]};

//TODO: Need to fix the interface to be cleaner. May be based on address.
swizzle_dram_to_cram u_swz_d2c (
  .data_valid(data_ram_data_valid),
  .clk(clk),
  .resetn(resetn),
  .mem_ctrl_data_in(data_ram_datain_cpu),
  .ram_data_out(swz_cram_data),
  .ram_addr(swz_cram_addr),
  .ram_we(load_cram),
  .ram_num(ram_num)
);

wire cram_data_valid;
assign cram_data_valid = ((funct3_reg==`READ_FROM_DATA_RAM) & stage1);
wire [31:0] num_elements_to_read;
assign num_elements_to_read = cmd_payload_inputs_1_reg;
reg [1:0] ram_num;
reg [31:0] data_read_count;

always @(posedge clk) begin
  if (~resetn) begin
     data_read_count <= 0;
     ram_num <= 0;
  end  
  else if (cram_data_valid) begin
    data_read_count <= data_read_count + 1;
    if (data_read_count == (num_elements_to_read-1)) begin
      ram_num <= ram_num + 1;
      data_read_count <= 0;
    end
  end
end


wire [`DWIDTH-1:0] ram_data_in;
assign ram_data_in = (ram_num==0) ? cram0_q2 :
                     (ram_num==1) ? cram1_q2 :
                     (ram_num==2) ? cram2_q2 :
                     (ram_num==3) ? cram3_q2 : 40'b0;

//TODO: Need to fix the interface to be cleaner. May be based on address.
swizzle_cram_to_dram u_swz_c2d (
  .data_valid(cram_data_valid),
  .clk(clk),
  .resetn(resetn),
  .ram_data_in(ram_data_in),
  .mem_ctrl_data_out(dram_data),
  .mem_ctrl_addr(dram_addr),
  .mem_ctrl_we(dram_we)
);

endmodule
