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
`include "axi_ram.v"
`include "axi_dma.v"
`include "axi_dma_rd.v"
`include "axi_dma_wr.v"

`define WRITE_TO_INST_RAM 7'd3
`define READ_FROM_INST_RAM 7'd4
`define WRITE_TO_CRAM 7'd5
`define READ_FROM_CRAM 7'd6
`define EXECUTE_INSTRUCTIONS 7'd7
`define START_DMA 7'd2

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

wire dma_mode;
assign dma_mode = 1;

wire [6:0] funct7;
reg [6:0] funct7_reg;
wire [2:0] funct3;
reg [2:0] funct3_reg;

wire check;
reg done_reg;
reg start_reg;

//////////////////////////////////////////////
// AXI related parameters
//////////////////////////////////////////////
parameter AXI_DATA_WIDTH = 64;
parameter AXI_ADDR_WIDTH = 16;
parameter AXI_STRB_WIDTH = (AXI_DATA_WIDTH/8);
parameter AXI_ID_WIDTH = 8;
parameter AXI_MAX_BURST_LEN = 16;
parameter AXIS_DATA_WIDTH = AXI_DATA_WIDTH;
parameter AXIS_KEEP_ENABLE = (AXIS_DATA_WIDTH>8);
parameter AXIS_KEEP_WIDTH = (AXIS_DATA_WIDTH/8);
parameter AXIS_LAST_ENABLE = 1;
parameter AXIS_ID_ENABLE = 1;
parameter AXIS_ID_WIDTH = 8;
parameter AXIS_DEST_ENABLE = 0;
parameter AXIS_DEST_WIDTH = 8;
parameter AXIS_USER_ENABLE = 1;
parameter AXIS_USER_WIDTH = 1;
parameter LEN_WIDTH = 20;
parameter TAG_WIDTH = 8;
parameter ENABLE_SG = 0;
parameter ENABLE_UNALIGNED = 0;

reg [AXI_ADDR_WIDTH-1:0] s_axis_read_desc_addr;
reg [LEN_WIDTH-1:0] s_axis_read_desc_len;
reg [TAG_WIDTH-1:0] s_axis_read_desc_tag;
reg [AXIS_ID_WIDTH-1:0] s_axis_read_desc_id;
reg [AXIS_DEST_WIDTH-1:0] s_axis_read_desc_dest;
reg [AXIS_USER_WIDTH-1:0] s_axis_read_desc_user;
reg s_axis_read_desc_valid;
wire m_axis_read_data_tready;
assign m_axis_read_data_tready = 1'b1; //we're always ready to receive data
reg [AXI_ADDR_WIDTH-1:0] s_axis_write_desc_addr;
reg [LEN_WIDTH-1:0] s_axis_write_desc_len;
reg [TAG_WIDTH-1:0] s_axis_write_desc_tag;
reg s_axis_write_desc_valid;
wire [AXIS_DATA_WIDTH-1:0] s_axis_write_data_tdata;
reg [AXIS_KEEP_WIDTH-1:0] s_axis_write_data_tkeep;
reg s_axis_write_data_tvalid;
reg s_axis_write_data_tlast;
reg [AXIS_ID_WIDTH-1:0] s_axis_write_data_tid;
wire [AXIS_DEST_WIDTH-1:0] s_axis_write_data_tdest;
wire [AXIS_USER_WIDTH-1:0] s_axis_write_data_tuser;

wire dramc_axi_awready;
wire dramc_axi_wready;
wire [AXI_ID_WIDTH-1:0] dramc_axi_bid;
wire [1:0] dramc_axi_bresp;
wire dramc_axi_bvalid;
wire dramc_axi_arready;
wire [AXI_ID_WIDTH-1:0] dramc_axi_rid;
wire [AXI_DATA_WIDTH-1:0] dramc_axi_rdata;
wire [1:0] dramc_axi_rresp;
wire dramc_axi_rlast;
wire dramc_axi_rvalid;

wire read_enable;
wire write_enable;
wire write_abort;

wire s_axis_read_desc_ready;
wire [TAG_WIDTH-1:0] m_axis_read_desc_status_tag;
wire [3:0] m_axis_read_desc_status_error;
wire m_axis_read_desc_status_valid;
wire [AXIS_DATA_WIDTH-1:0] m_axis_read_data_tdata;
wire [AXIS_KEEP_WIDTH-1:0] m_axis_read_data_tkeep;
wire m_axis_read_data_tvalid;
wire m_axis_read_data_tlast;
wire [AXIS_ID_WIDTH-1:0] m_axis_read_data_tid;
wire [AXIS_DEST_WIDTH-1:0] m_axis_read_data_tdest;
wire [AXIS_USER_WIDTH-1:0] m_axis_read_data_tuser;
wire s_axis_write_desc_ready;
wire [LEN_WIDTH-1:0] m_axis_write_desc_status_len;
wire [TAG_WIDTH-1:0] m_axis_write_desc_status_tag;
wire [AXIS_ID_WIDTH-1:0] m_axis_write_desc_status_id;
wire [AXIS_DEST_WIDTH-1:0] m_axis_write_desc_status_dest;
wire [AXIS_USER_WIDTH-1:0] m_axis_write_desc_status_user;
wire [3:0] m_axis_write_desc_status_error;
wire m_axis_write_desc_status_valid;
wire s_axis_write_data_tready;

wire [AXI_ID_WIDTH-1:0] dramc_axi_awid;
wire [AXI_ADDR_WIDTH-1:0] dramc_axi_awaddr;
wire [7:0] dramc_axi_awlen;
wire [2:0] dramc_axi_awsize;
wire [1:0] dramc_axi_awburst;
wire dramc_axi_awlock;
wire [3:0] dramc_axi_awcache;
wire [2:0] dramc_axi_awprot;
wire dramc_axi_awvalid;
wire [AXI_DATA_WIDTH-1:0] dramc_axi_wdata;
wire [AXI_STRB_WIDTH-1:0] dramc_axi_wstrb;
wire dramc_axi_wlast;
wire dramc_axi_wvalid;
wire dramc_axi_bready;
wire [AXI_ID_WIDTH-1:0] dramc_axi_arid;
wire [AXI_ADDR_WIDTH-1:0] dramc_axi_araddr;
wire [7:0] dramc_axi_arlen;
wire [2:0] dramc_axi_arsize;
wire [1:0] dramc_axi_arburst;
wire dramc_axi_arlock;
wire [3:0] dramc_axi_arcache;
wire [2:0] dramc_axi_arprot;
wire dramc_axi_arvalid;
wire dramc_axi_rready;

reg dma_read_status;
reg dma_write_status;

reg [AXI_ADDR_WIDTH-1:0] dram_addr_to_read;
reg [15:0] dram_data_bytes_to_read;

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
wire [`MEM_CTRL_AWIDTH-1:0] dram_addr_out;
wire dram_we_out;
reg dram_we_out_dly1;
reg dram_we_out_dly2;
reg dram_we_out_dly3;
reg dram_we_out_dly4;

reg [31:0]   cmd_payload_inputs_0_reg;
reg [31:0]   cmd_payload_inputs_1_reg;
reg [9:0]    cmd_payload_function_id_reg;

/////////////////////////////////////////
// Op0: byte sum (unsigned) -> this is dummy now
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
// Select output for the CPU interface 
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
                                    (funct3_reg==3'd2) ? (
                                      (funct7_reg==3'd0) ? {32{1'b0}} : //trigger dma read
                                      (funct7_reg==3'd1) ? dma_read_status: //check dma read status
                                      (funct7_reg==3'd2) ? {32{1'b0}} :
                                      (funct7_reg==3'd3) ? dma_write_status: 32'b0 //check dma write status
                                    ) :
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
              ((funct3==3'd2) && (funct7!=2) ) ||  //cfu_op2 -> trigger dma 
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

          if ((funct3==3'd6) || ((funct3==3'd2) && (funct7==2)))  begin   //cfu_op6 -> read comefa
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

wire start;
wire done;
wire execute;
wire cram0_we;
wire cram1_we;
wire cram2_we;
wire cram3_we;

wire stored_instr_we_cpu;
wire [8:0] stored_instr_addr_cpu;
wire [`STORED_INST_DATA_WIDTH-1:0] stored_instr_datain_cpu;
wire [`STORED_INST_DATA_WIDTH-1:0] stored_instr_dataout_cpu;

wire stored_instr_we_internal;
wire [`AWIDTH-1:0] stored_instr_addr_internal;
wire [`DWIDTH-1:0] stored_instr_datain_internal;
wire [`DWIDTH-1:0] stored_instr_dataout_internal;

///////////////////////////////////////////////////
//Choose what we do with the Comefa RAMs:
// (1) Execute instructions 
// (2) Read or write data
///////////////////////////////////////////////////
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
  //$readmemb("/home/data1/aman/CFU-Playground/proj/comefa/instructions.rfadd.dat", u_instr_ram.ram);
  $readmemb("/home/data1/aman/comefa/comefa/software/instructions.dotprod.dat", u_instr_ram.ram);
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

/////////////////////////////////////////////////////////
//Controller - Will read stored instructions
//from normal BRAM and send executable (micro)instructions
//to Comefa RAM
////////////////////////////////////////////////////////
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
  assign dram_data_in[8+i] = dma_mode ? m_axis_read_data_tdata[31-i] : cmd_payload_inputs_0_reg[31-i];
end endgenerate
generate for (i=0;i<8;i=i+1) begin                       //39,38,..32
  assign dram_data_in[i] = dma_mode ? m_axis_read_data_tdata[39-i] : cmd_payload_inputs_1_reg[7-i];
end endgenerate

//+LOG_NUM_CRAMS below because higher order bits
//to decode which of the N crams to address.
wire [`RAM_PORT_AWIDTH+`LOG_NUM_CRAMS-1:0] cram_start_wr_addr_nondma;
wire [`RAM_PORT_AWIDTH+`LOG_NUM_CRAMS-1:0] cram_start_wr_addr_muxed;
reg [`RAM_PORT_AWIDTH+`LOG_NUM_CRAMS-1:0] cram_start_addr_to_write_dma;
assign cram_start_wr_addr_nondma = cmd_payload_inputs_1_reg[`RAM_PORT_AWIDTH+`LOG_NUM_CRAMS+8-1:8];
assign cram_start_wr_addr_muxed = dma_mode ? cram_start_addr_to_write_dma : cram_start_wr_addr_nondma;

wire dram_data_valid_final;
assign dram_data_valid_final = dma_mode ? m_axis_read_data_tvalid : dram_data_valid;

wire dram_data_last_final;
assign dram_data_last_final = dma_mode ? m_axis_read_data_tlast : dram_data_last;

//TODO: Need to fix the interface to be cleaner. May be based on address.
swizzle_dram_to_cram u_swz_d2c (
  .data_valid(dram_data_valid_final),
  .clk(clk),
  .resetn(long_reset_n),
  .mem_ctrl_data_in(dram_data_in),
  .mem_ctrl_data_last(dram_data_last_final),
  .ram_start_addr(cram_start_wr_addr_muxed),
  .ram_data_out(swz_cram_data),
  .ram_addr(swz_cram_addr_full),
  .ram_we(load_cram),
  .ready(swizzle_d2c_ready),
  .dma_mode(dma_mode)
);

/////////////////////////////////////////
//Swizzle logic to transpose data coming
//from CRAM into DRAM
/////////////////////////////////////////

reg cram_data_valid;
reg[31:0] num_elements_to_read;
reg [`AWIDTH+`LOG_NUM_CRAMS-1:0] starting_addr_while_reading;
reg [31:0] data_read_count;
reg ram_data_last;
reg first_time;
reg [2:0] cram_read_state;

wire read_from_cram;
assign read_from_cram = 
      dma_mode ? 
      (cmd_valid & cmd_ready & (funct3==`START_DMA) & (funct7==2)) :
      (cmd_valid & cmd_ready & (funct3==`READ_FROM_CRAM) & (funct7==0));

wire read_from_cram_last;
assign read_from_cram_last = 
      dma_mode ?
      //s_axis_write_data_tlast :
      //(write_data_count == ((num_bytes*8/AXI_DATA_WIDTH)-1)) :
      (data_read_count == (num_elements_to_read-1)) :
      (cmd_valid & cmd_ready & (funct3==`READ_FROM_CRAM) & (funct7==1));

reg [`MEM_CTRL_AWIDTH-1:0] dram_addr_to_write;

//State machine that assists the swizzle logic
//in reading data from CRAMs and sending it to
//swizzle logic
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
      if (read_from_cram) begin
        cram_data_valid <= 0;
        data_read_count <= 0;
        starting_addr_while_reading <= cmd_payload_inputs_0[31:16];
        cram_addr_for_read_full <= cmd_payload_inputs_0[31:16];
        num_elements_to_read <= cmd_payload_inputs_0[15:0];
        dram_addr_to_write <= cmd_payload_inputs_1;
        if (dma_mode) begin
          cram_read_state <= 5;
        end
        else begin
          cram_read_state <= 1;
        end
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
        cram_addr_for_read_full <= cram_addr_for_read_full + 4;
        data_read_count <= data_read_count + 1;
      end
      ram_data_last <= 0;
    end 

    2: begin
      if (read_from_cram) begin 
        cram_data_valid <= 1;
        data_read_count <= data_read_count + 1;
        ram_data_last <= 0;
        if ((data_read_count == 2*`COUNT_TO_SWITCH_BUFFERS) || (data_read_count == 3*`COUNT_TO_SWITCH_BUFFERS)) begin
          cram_addr_for_read_full <= starting_addr_while_reading+1;
          starting_addr_while_reading<=starting_addr_while_reading+1;
        end
        else begin
          cram_addr_for_read_full <= cram_addr_for_read_full + 4;
        end
      end
      else if (read_from_cram_last) begin //last
        cram_data_valid <= 1;
        data_read_count <= data_read_count + 1;
        cram_addr_for_read_full <= cram_addr_for_read_full + 4;
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

    4: begin
      if (read_from_cram_last) begin //last
        cram_data_valid <= 1;
        data_read_count <= data_read_count + 1;
        cram_addr_for_read_full <= cram_addr_for_read_full + 4;
        ram_data_last <= 1;
        cram_read_state <= 0;
      end
      else if (s_axis_write_data_tready) begin
        cram_data_valid <= 1;
        data_read_count <= data_read_count + 1;
        ram_data_last <= 0;
        if ((data_read_count == 2*`COUNT_TO_SWITCH_BUFFERS) || (data_read_count == 3*`COUNT_TO_SWITCH_BUFFERS)) begin
          cram_addr_for_read_full <= starting_addr_while_reading+1;
          starting_addr_while_reading<=starting_addr_while_reading+1;
        end
        else begin
          cram_addr_for_read_full <= cram_addr_for_read_full + 4;
        end
        cram_read_state <= 4;
      end
      else begin
        cram_data_valid <= 0;
      end
    end

    5: begin
      if (data_read_count == `COUNT_TO_SWITCH_BUFFERS+1) begin
        cram_read_state <= 4;
        cram_data_valid <= 0;
        cram_addr_for_read_full <= starting_addr_while_reading+1;
        starting_addr_while_reading<=starting_addr_while_reading+1;
      end 
      else begin
        cram_data_valid <= 1;
        cram_addr_for_read_full <= cram_addr_for_read_full + 4;
        data_read_count <= data_read_count + 1;
      end
      ram_data_last <= 0;
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
  .mem_ctrl_data_out(dram_data_out), 
  .mem_ctrl_addr(dram_addr_out), 
  .mem_ctrl_addr_start(dram_addr_to_write), 
  .mem_ctrl_we(dram_we_out), 
  .ready(swizzle_c2d_ready), //unconnected for now
  .dma_mode(dma_mode)
);

always @(posedge clk) begin
  dram_we_out_dly1 <= dram_we_out;
  dram_we_out_dly2 <= dram_we_out_dly1;
  dram_we_out_dly3 <= dram_we_out_dly2;
  dram_we_out_dly4 <= dram_we_out_dly3;
end

generate for (i=0;i<`DWIDTH;i=i+1) begin
  assign dram_data_out_c2d[i] = dram_data_out[`DWIDTH-1-i];
end endgenerate

always @(posedge clk) begin
  dram_data_out_c2d_delayed <= dram_data_out_c2d;
end

////////////////////////////////////////////////////////
// DMA engine - Perfoms two functions: 
// (1) Reads input data from DRAM and loads it in CRAMs
// (2) Reads outputs from CRAMs and stores it in DRAM
////////////////////////////////////////////////////////
axi_dma #(
    .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
    .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
    .AXI_STRB_WIDTH(AXI_STRB_WIDTH),
    .AXI_ID_WIDTH(AXI_ID_WIDTH),
    .AXI_MAX_BURST_LEN(AXI_MAX_BURST_LEN),
    .AXIS_DATA_WIDTH(AXIS_DATA_WIDTH),
    .AXIS_KEEP_ENABLE(AXIS_KEEP_ENABLE),
    .AXIS_KEEP_WIDTH(AXIS_KEEP_WIDTH),
    .AXIS_LAST_ENABLE(AXIS_LAST_ENABLE),
    .AXIS_ID_ENABLE(AXIS_ID_ENABLE),
    .AXIS_ID_WIDTH(AXIS_ID_WIDTH),
    .AXIS_DEST_ENABLE(AXIS_DEST_ENABLE),
    .AXIS_DEST_WIDTH(AXIS_DEST_WIDTH),
    .AXIS_USER_ENABLE(AXIS_USER_ENABLE),
    .AXIS_USER_WIDTH(AXIS_USER_WIDTH),
    .LEN_WIDTH(LEN_WIDTH),
    .TAG_WIDTH(TAG_WIDTH),
    .ENABLE_SG(ENABLE_SG),
    .ENABLE_UNALIGNED(ENABLE_UNALIGNED)
)
dma_engine (
    .clk(clk),
    .rst(~long_reset_n),

    /*
     * AXI read descriptor input
     */
    .s_axis_read_desc_addr(s_axis_read_desc_addr),
    .s_axis_read_desc_len(s_axis_read_desc_len),
    .s_axis_read_desc_tag(s_axis_read_desc_tag),
    .s_axis_read_desc_id(s_axis_read_desc_id),
    .s_axis_read_desc_dest(s_axis_read_desc_dest),
    .s_axis_read_desc_user(s_axis_read_desc_user),
    .s_axis_read_desc_valid(s_axis_read_desc_valid),
    .s_axis_read_desc_ready(s_axis_read_desc_ready),

    /*
     * AXI read descriptor status output
     */
    .m_axis_read_desc_status_tag(m_axis_read_desc_status_tag),
    .m_axis_read_desc_status_error(m_axis_read_desc_status_error),
    .m_axis_read_desc_status_valid(m_axis_read_desc_status_valid),

    /*
     * AXI stream read data output
     */
    .m_axis_read_data_tdata(m_axis_read_data_tdata),
    .m_axis_read_data_tkeep(m_axis_read_data_tkeep),
    .m_axis_read_data_tvalid(m_axis_read_data_tvalid),
    .m_axis_read_data_tready(m_axis_read_data_tready),
    .m_axis_read_data_tlast(m_axis_read_data_tlast),
    .m_axis_read_data_tid(m_axis_read_data_tid),
    .m_axis_read_data_tdest(m_axis_read_data_tdest),
    .m_axis_read_data_tuser(m_axis_read_data_tuser),

    /*
     * AXI write descriptor input
     */
    .s_axis_write_desc_addr(s_axis_write_desc_addr),
    .s_axis_write_desc_len(s_axis_write_desc_len),
    .s_axis_write_desc_tag(s_axis_write_desc_tag),
    .s_axis_write_desc_valid(s_axis_write_desc_valid),
    .s_axis_write_desc_ready(s_axis_write_desc_ready),

    /*
     * AXI write descriptor status output
     */
    .m_axis_write_desc_status_len(m_axis_write_desc_status_len),
    .m_axis_write_desc_status_tag(m_axis_write_desc_status_tag),
    .m_axis_write_desc_status_id(m_axis_write_desc_status_id),
    .m_axis_write_desc_status_dest(m_axis_write_desc_status_dest),
    .m_axis_write_desc_status_user(m_axis_write_desc_status_user),
    .m_axis_write_desc_status_error(m_axis_write_desc_status_error),
    .m_axis_write_desc_status_valid(m_axis_write_desc_status_valid),

    /*
     * AXI stream write data input
     */
    .s_axis_write_data_tdata(s_axis_write_data_tdata),
    .s_axis_write_data_tkeep(s_axis_write_data_tkeep),
    .s_axis_write_data_tvalid(s_axis_write_data_tvalid),
    .s_axis_write_data_tready(s_axis_write_data_tready),
    .s_axis_write_data_tlast(s_axis_write_data_tlast),
    .s_axis_write_data_tid(s_axis_write_data_tid),
    .s_axis_write_data_tdest(s_axis_write_data_tdest),
    .s_axis_write_data_tuser(s_axis_write_data_tuser),

    /*
     * AXI master interface
     */
    .m_axi_awid(dramc_axi_awid),
    .m_axi_awaddr(dramc_axi_awaddr),
    .m_axi_awlen(dramc_axi_awlen),
    .m_axi_awsize(dramc_axi_awsize),
    .m_axi_awburst(dramc_axi_awburst),
    .m_axi_awlock(dramc_axi_awlock),
    .m_axi_awcache(dramc_axi_awcache),
    .m_axi_awprot(dramc_axi_awprot),
    .m_axi_awvalid(dramc_axi_awvalid),
    .m_axi_awready(dramc_axi_awready),
    .m_axi_wdata(dramc_axi_wdata),
    .m_axi_wstrb(dramc_axi_wstrb),
    .m_axi_wlast(dramc_axi_wlast),
    .m_axi_wvalid(dramc_axi_wvalid),
    .m_axi_wready(dramc_axi_wready),
    .m_axi_bid(dramc_axi_bid),
    .m_axi_bresp(dramc_axi_bresp),
    .m_axi_bvalid(dramc_axi_bvalid),
    .m_axi_bready(dramc_axi_bready),
    .m_axi_arid(dramc_axi_arid),
    .m_axi_araddr(dramc_axi_araddr),
    .m_axi_arlen(dramc_axi_arlen),
    .m_axi_arsize(dramc_axi_arsize),
    .m_axi_arburst(dramc_axi_arburst),
    .m_axi_arlock(dramc_axi_arlock),
    .m_axi_arcache(dramc_axi_arcache),
    .m_axi_arprot(dramc_axi_arprot),
    .m_axi_arvalid(dramc_axi_arvalid),
    .m_axi_arready(dramc_axi_arready),
    .m_axi_rid(dramc_axi_rid),
    .m_axi_rdata(dramc_axi_rdata),
    .m_axi_rresp(dramc_axi_rresp),
    .m_axi_rlast(dramc_axi_rlast),
    .m_axi_rvalid(dramc_axi_rvalid),
    .m_axi_rready(dramc_axi_rready),

    /*
     * Configuration
     */
    .read_enable(1'b1),
    .write_enable(1'b1),
    .write_abort(1'b0)
);

//////////////////////////////////////////////////
//This is a RAM with an AXI interface. It models
//a DDR controller with an AXI interface towards
//user logic
//////////////////////////////////////////////////
axi_ram #(
    .DATA_WIDTH(AXI_DATA_WIDTH),
    .ADDR_WIDTH(AXI_ADDR_WIDTH),
    .STRB_WIDTH(AXI_STRB_WIDTH),
    .ID_WIDTH(AXI_ID_WIDTH),
    .PIPELINE_OUTPUT(0)
)
ddr_memory_controller (
    .clk(clk),
    .rst(~long_reset_n),
    .s_axi_awid(dramc_axi_awid),
    .s_axi_awaddr(dramc_axi_awaddr),
    .s_axi_awlen(dramc_axi_awlen),
    .s_axi_awsize(dramc_axi_awsize),
    .s_axi_awburst(dramc_axi_awburst),
    .s_axi_awlock(dramc_axi_awlock),
    .s_axi_awcache(dramc_axi_awcache),
    .s_axi_awprot(dramc_axi_awprot),
    .s_axi_awvalid(dramc_axi_awvalid),
    .s_axi_awready(dramc_axi_awready),
    .s_axi_wdata(dramc_axi_wdata),
    .s_axi_wstrb(dramc_axi_wstrb),
    .s_axi_wlast(dramc_axi_wlast),
    .s_axi_wvalid(dramc_axi_wvalid),
    .s_axi_wready(dramc_axi_wready),
    .s_axi_bid(dramc_axi_bid),
    .s_axi_bresp(dramc_axi_bresp),
    .s_axi_bvalid(dramc_axi_bvalid),
    .s_axi_bready(dramc_axi_bready),
    .s_axi_arid(dramc_axi_arid),
    .s_axi_araddr(dramc_axi_araddr),
    .s_axi_arlen(dramc_axi_arlen),
    .s_axi_arsize(dramc_axi_arsize),
    .s_axi_arburst(dramc_axi_arburst),
    .s_axi_arlock(dramc_axi_arlock),
    .s_axi_arcache(dramc_axi_arcache),
    .s_axi_arprot(dramc_axi_arprot),
    .s_axi_arvalid(dramc_axi_arvalid),
    .s_axi_arready(dramc_axi_arready),
    .s_axi_rid(dramc_axi_rid),
    .s_axi_rdata(dramc_axi_rdata),
    .s_axi_rresp(dramc_axi_rresp),
    .s_axi_rlast(dramc_axi_rlast),
    .s_axi_rvalid(dramc_axi_rvalid),
    .s_axi_rready(dramc_axi_rready)
);

/////////////////////////////////////////////////
// Logic to configure and control the DMA engine
// for reading from DRAM
/////////////////////////////////////////////////
reg start_dma_read_reg;
reg check_dma_read_reg;
reg [2:0] dma_read_ctrl_state;

always @(posedge clk) begin
  if (~long_reset_n) begin
    s_axis_read_desc_addr <= 0;
    s_axis_read_desc_len <= 0;
    s_axis_read_desc_tag <= 0;
    s_axis_read_desc_id <= 0;
    s_axis_read_desc_dest <= 0;
    s_axis_read_desc_user <= 0;
    s_axis_read_desc_valid <= 0;
  end
  else begin
    case(dma_read_ctrl_state)
    0: begin
      if (start_dma_read_reg && s_axis_read_desc_ready) begin
        s_axis_read_desc_addr <= dram_addr_to_read;
        s_axis_read_desc_len <= dram_data_bytes_to_read;
        s_axis_read_desc_tag <= 2;
        s_axis_read_desc_id <= 2;
        s_axis_read_desc_dest <= 0;
        s_axis_read_desc_user <= 0;
        s_axis_read_desc_valid <= 1;
        dma_read_ctrl_state <= 1;
      end
      dma_read_status <= 0;
    end

    1: begin
        s_axis_read_desc_addr <= 0;
        s_axis_read_desc_len <= 0;
        s_axis_read_desc_tag <= 0;
        s_axis_read_desc_id <= 0;
        s_axis_read_desc_dest <= 0;
        s_axis_read_desc_user <= 0;
        s_axis_read_desc_valid <= 0;
        if (m_axis_read_desc_status_valid) begin
          dma_read_status <= 1;
          dma_read_ctrl_state <= 2;
        end 
    end

    2: begin
        if (check_dma_read_reg) begin
          dma_read_status <= 1;
          dma_read_ctrl_state <= 0;
        end
    end

    endcase 
  end
end

//When to start the DMA engine
always @(posedge clk) begin
  if (~resetn) begin
    start_dma_read_reg <= 1'b0;
  end
  else if ((funct3_reg==`START_DMA) & (funct7_reg==0) & cmd_valid & cmd_ready) begin
    start_dma_read_reg <= 1'b1;
    dram_addr_to_read <= cmd_payload_inputs_0_reg[15:0];
    dram_data_bytes_to_read <= cmd_payload_inputs_0_reg[31:16]; //Only support 160*8 bytes for now
    cram_start_addr_to_write_dma <= cmd_payload_inputs_1_reg;
  end
  else begin
    start_dma_read_reg <= 1'b0;
  end
end

//Checking if the DMA engine is done
always @(posedge clk) begin
  if (~resetn) begin
    check_dma_read_reg <= 1'b0;
  end
  else if ((funct3_reg==`START_DMA) & (funct7_reg==1) & cmd_valid & cmd_ready) begin
    check_dma_read_reg <= 1'b1;
  end
  else begin
    check_dma_read_reg <= 1'b0;
  end
end

/////////////////////////////////////////////////
// Logic to configure and control the DMA engine
// for writing to DRAM
/////////////////////////////////////////////////
reg start_dma_write_reg;
reg check_dma_write_reg;
reg [2:0] dma_write_ctrl_state;

reg [7:0] write_data_count;
wire [LEN_WIDTH-1:0] num_bytes = 160*8; //TODO: hardcoding for now
wire [TAG_WIDTH-1:0] mytag = 3;
reg put_new_data;
wire [AXI_DATA_WIDTH-1:0] mydata;
assign mydata = write_data_count + 100;

always @(posedge clk) begin
  if (~long_reset_n) begin
    s_axis_write_desc_addr <= 0;
    s_axis_write_desc_len <= 0;
    s_axis_write_desc_tag <= 0;
    s_axis_write_desc_valid <= 0;
    write_data_count <= 0;
    put_new_data <= 0;
    dma_write_status <= 0;
  end
  else begin
    case(dma_write_ctrl_state)
    //Set descriptor when ready
    0: begin
      //first time we check dram_we_out
      if (dram_we_out && s_axis_write_desc_ready) begin
        //Set descriptor
        s_axis_write_desc_addr <= dram_addr_out;
        s_axis_write_desc_len <= num_bytes;
        s_axis_write_desc_tag <= mytag;
        s_axis_write_desc_valid <= 1;
        put_new_data <= 1;
        write_data_count <= 1;

        //Put data on the bus
        s_axis_write_data_tkeep <= {AXIS_KEEP_WIDTH{1'b1}};
        s_axis_write_data_tid <= mytag;
        s_axis_write_data_tvalid <= 1'b1;
        s_axis_write_data_tlast <= 1'b0;

        dma_write_ctrl_state <= 1;
      end
      dma_write_status <= 0; 
    end

    1: begin
        s_axis_write_desc_valid <= 0;

        if (s_axis_write_data_tready) begin
          //write_data_count <= write_data_count + 1;
          s_axis_write_data_tkeep <= {AXIS_KEEP_WIDTH{1'b1}};
          s_axis_write_data_tid <= mytag;
          s_axis_write_data_tvalid <= 0;
          s_axis_write_data_tlast <= 1'b0;
          dma_write_ctrl_state <= 4;
        end
    end

    4: begin
        s_axis_write_desc_valid <= 0;

        if (s_axis_write_data_tready) begin
          write_data_count <= write_data_count + 1;
          s_axis_write_data_tkeep <= {AXIS_KEEP_WIDTH{1'b1}};
          s_axis_write_data_tid <= mytag;
          s_axis_write_data_tvalid <= 1;
          if (write_data_count == ((num_bytes*8/AXI_DATA_WIDTH)-1)) begin
            s_axis_write_data_tlast <= 1'b1;
            dma_write_ctrl_state <= 5;
          end
          else begin
            s_axis_write_data_tlast <= 1'b0;
            dma_write_ctrl_state <= 4;
          end
        end
      
    end

    5: begin
        //wait for status valid to assert
        if (m_axis_write_desc_status_valid) begin
          dma_write_status <= 1;
          dma_write_ctrl_state <= 6;
        end 
    end

    6: begin
        if (check_dma_write_reg) begin
          dma_write_status <= 1; 
          dma_write_ctrl_state <= 0;
        end
    end
    endcase 
  end
end

assign s_axis_write_data_tdata = dram_data_out;

//When to start the DMA engine
always @(posedge clk) begin
  if (~resetn) begin
    start_dma_write_reg <= 1'b0;
  end
  else if ((funct3_reg==`START_DMA) & (funct7_reg==2) & cmd_valid & cmd_ready) begin
    start_dma_write_reg <= 1'b1;
  end
  else begin
    start_dma_write_reg <= 1'b0;
  end
end

//Checking if the DMA engine is done
always @(posedge clk) begin
  if (~resetn) begin
    check_dma_write_reg <= 1'b0;
  end
  else if ((funct3_reg==`START_DMA) & (funct7_reg==3) & cmd_valid & cmd_ready) begin
    check_dma_write_reg <= 1'b1;
  end
  else begin
    check_dma_write_reg <= 1'b0;
  end
end

`ifdef VCS
initial begin
  $vcdpluson;
  $vcdplusmemon;
end
`endif

endmodule