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

`define STORE_VALS 7'd3
`define LOAD_VALS 7'd4

module Cfu (
  input               cmd_valid,
  output  reg            cmd_ready,
  input      [9:0]    cmd_payload_function_id,
  input      [31:0]   cmd_payload_inputs_0,
  input      [31:0]   cmd_payload_inputs_1,
  output  reg            rsp_valid,
  input               rsp_ready,
  output  reg   [31:0]   rsp_payload_outputs_0,
  input               clk,
  input               reset
);


wire [6:0] funct7;
reg [6:0] funct7_reg;
wire [2:0] funct3;
reg [2:0] funct3_reg;

assign funct7 = cmd_payload_function_id[9:3];
assign funct3 = cmd_payload_function_id[2:0];

wire funct7_ored = |funct7;

//  assign rsp_valid = cmd_valid;
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

  //  byte sum (unsigned)
  wire [31:0] cfu0;
  reg [31:0] cfu0_reg;
 // assign cfu0[31:0] =  cmd_payload_function_id_reg;
  assign cfu0[31:0] =  cmd_payload_inputs_0_reg[7:0]   + cmd_payload_inputs_1_reg[7:0];
                      // cmd_payload_inputs_0[15:8]  + cmd_payload_inputs_1[15:8] +
                      // cmd_payload_inputs_0[23:16] + cmd_payload_inputs_1[23:16] +
                      // cmd_payload_inputs_0[31:24] + cmd_payload_inputs_1[31:24];

  // byte swap
  wire [31:0] cfu1;
  reg [31:0] cfu1_reg;
  assign cfu1[31:24] =     cmd_payload_inputs_0_reg[7:0];
  assign cfu1[23:16] =     cmd_payload_inputs_0_reg[15:8];
  assign cfu1[15:8] =      cmd_payload_inputs_0_reg[23:16];
  assign cfu1[7:0] =       cmd_payload_inputs_0_reg[31:24];
//assign cfu1[31:0] =  cmd_payload_function_id_reg;

  // bit reverse
  wire [31:0] cfu2;
  reg [31:0] cfu2_reg;
  genvar n;
  generate
      for (n=0; n<32; n=n+1) begin
          assign cfu2[n] =     cmd_payload_inputs_0_reg[31-n];
      end
  endgenerate


  reg stage2;
  always @(posedge clk) begin
    stage2 <= stage1;
  end


  //
  // select output -- note that we're not fully decoding the 3 function_id bits
  //
  wire   [31:0]   rsp_payload_outputs_0_wire;
  reg [31:0] val;
  //assign rsp_payload_outputs_0_wire = cmd_payload_function_id_reg;
  assign rsp_payload_outputs_0_wire = (funct3_reg==3'd4) ? val :
                                      (funct3_reg==3'd3) ? {32{1'b1}} :
                                      (funct3_reg==3'd2) ? cfu2 :
                                      (funct3_reg==3'd1) ? cfu1 : 
                                      (funct3_reg==3'd0) ? cfu0 : 32'b0;

  always @(posedge clk) begin
    rsp_payload_outputs_0 <= rsp_payload_outputs_0_wire;
    rsp_valid <= stage2;
  end

//Input store
reg [31:0] inp_store_ram[511:0];
reg [8:0] inp_store_waddr;

//If writing to RAM
always @(posedge clk) begin
  if((funct3_reg==`STORE_VALS) & stage1) begin
    inp_store_ram[cmd_payload_inputs_0_reg]   <=  cmd_payload_inputs_1_reg;
  end
end                                    

//If reading from RAM
always @(posedge clk) begin
  if((funct3_reg==`LOAD_VALS) & stage1) begin
    val <= inp_store_ram[cmd_payload_inputs_0_reg];
  end
end  


endmodule
