/*

Copyright (c) 2018 Alex Forencich

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

*/

// Language: Verilog 2001


/*
 * AXI4 RAM
 */
module axi_ram #
(
    // Width of data bus in bits
    parameter DATA_WIDTH = 32,
    // Width of address bus in bits
    parameter ADDR_WIDTH = 16,
    // Width of wstrb (width of data bus in words)
    parameter STRB_WIDTH = (DATA_WIDTH/8),
    // Width of ID signal
    parameter ID_WIDTH = 8,
    // Extra pipeline register on output
    parameter PIPELINE_OUTPUT = 0
)
(
    input  wire                   clk,
    input  wire                   rst,

    input  wire [ID_WIDTH-1:0]    s_axi_awid,
    input  wire [ADDR_WIDTH-1:0]  s_axi_awaddr,
    input  wire [7:0]             s_axi_awlen,
    input  wire [2:0]             s_axi_awsize,
    input  wire [1:0]             s_axi_awburst,
    input  wire                   s_axi_awlock,
    input  wire [3:0]             s_axi_awcache,
    input  wire [2:0]             s_axi_awprot,
    input  wire                   s_axi_awvalid,
    output wire                   s_axi_awready,
    input  wire [DATA_WIDTH-1:0]  s_axi_wdata,
    input  wire [STRB_WIDTH-1:0]  s_axi_wstrb,
    input  wire                   s_axi_wlast,
    input  wire                   s_axi_wvalid,
    output wire                   s_axi_wready,
    output wire [ID_WIDTH-1:0]    s_axi_bid,
    output wire [1:0]             s_axi_bresp,
    output wire                   s_axi_bvalid,
    input  wire                   s_axi_bready,
    input  wire [ID_WIDTH-1:0]    s_axi_arid,
    input  wire [ADDR_WIDTH-1:0]  s_axi_araddr,
    input  wire [7:0]             s_axi_arlen,
    input  wire [2:0]             s_axi_arsize,
    input  wire [1:0]             s_axi_arburst,
    input  wire                   s_axi_arlock,
    input  wire [3:0]             s_axi_arcache,
    input  wire [2:0]             s_axi_arprot,
    input  wire                   s_axi_arvalid,
    output wire                   s_axi_arready,
    output wire [ID_WIDTH-1:0]    s_axi_rid,
    output wire [DATA_WIDTH-1:0]  s_axi_rdata,
    output wire [1:0]             s_axi_rresp,
    output wire                   s_axi_rlast,
    output wire                   s_axi_rvalid,
    input  wire                   s_axi_rready
);

parameter VALID_ADDR_WIDTH = ADDR_WIDTH - $clog2(STRB_WIDTH);
parameter WORD_WIDTH = STRB_WIDTH;
parameter WORD_SIZE = DATA_WIDTH/WORD_WIDTH;

// bus width assertions
initial begin
    if (WORD_SIZE * STRB_WIDTH != DATA_WIDTH) begin
        $error("Error: AXI data width not evenly divisble (instance %m)");
        $finish;
    end

    if (2**$clog2(WORD_WIDTH) != WORD_WIDTH) begin
        $error("Error: AXI word width must be even power of two (instance %m)");
        $finish;
    end
end

localparam [0:0]
    READ_STATE_IDLE = 1'd0,
    READ_STATE_BURST = 1'd1;

reg [0:0] read_state_reg = READ_STATE_IDLE, read_state_next;

localparam [1:0]
    WRITE_STATE_IDLE = 2'd0,
    WRITE_STATE_BURST = 2'd1,
    WRITE_STATE_RESP = 2'd2;

reg [1:0] write_state_reg = WRITE_STATE_IDLE, write_state_next;

reg mem_wr_en;
reg mem_rd_en;

reg [ID_WIDTH-1:0] read_id_reg = {ID_WIDTH{1'b0}}, read_id_next;
reg [ADDR_WIDTH-1:0] read_addr_reg = {ADDR_WIDTH{1'b0}}, read_addr_next;
reg [7:0] read_count_reg = 8'd0, read_count_next;
reg [2:0] read_size_reg = 3'd0, read_size_next;
reg [1:0] read_burst_reg = 2'd0, read_burst_next;
reg [ID_WIDTH-1:0] write_id_reg = {ID_WIDTH{1'b0}}, write_id_next;
reg [ADDR_WIDTH-1:0] write_addr_reg = {ADDR_WIDTH{1'b0}}, write_addr_next;
reg [7:0] write_count_reg = 8'd0, write_count_next;
reg [2:0] write_size_reg = 3'd0, write_size_next;
reg [1:0] write_burst_reg = 2'd0, write_burst_next;

reg s_axi_awready_reg = 1'b0, s_axi_awready_next;
reg s_axi_wready_reg = 1'b0, s_axi_wready_next;
reg [ID_WIDTH-1:0] s_axi_bid_reg = {ID_WIDTH{1'b0}}, s_axi_bid_next;
reg s_axi_bvalid_reg = 1'b0, s_axi_bvalid_next;
reg s_axi_arready_reg = 1'b0, s_axi_arready_next;
reg [ID_WIDTH-1:0] s_axi_rid_reg = {ID_WIDTH{1'b0}}, s_axi_rid_next;
reg [DATA_WIDTH-1:0] s_axi_rdata_reg = {DATA_WIDTH{1'b0}}, s_axi_rdata_next;
reg s_axi_rlast_reg = 1'b0, s_axi_rlast_next;
reg s_axi_rvalid_reg = 1'b0, s_axi_rvalid_next;
reg [ID_WIDTH-1:0] s_axi_rid_pipe_reg = {ID_WIDTH{1'b0}};
reg [DATA_WIDTH-1:0] s_axi_rdata_pipe_reg = {DATA_WIDTH{1'b0}};
reg s_axi_rlast_pipe_reg = 1'b0;
reg s_axi_rvalid_pipe_reg = 1'b0;

// (* RAM_STYLE="BLOCK" *)
reg [DATA_WIDTH-1:0] mem[(2**VALID_ADDR_WIDTH)-1:0];

wire [VALID_ADDR_WIDTH-1:0] s_axi_awaddr_valid = s_axi_awaddr >> (ADDR_WIDTH - VALID_ADDR_WIDTH);
wire [VALID_ADDR_WIDTH-1:0] s_axi_araddr_valid = s_axi_araddr >> (ADDR_WIDTH - VALID_ADDR_WIDTH);
wire [VALID_ADDR_WIDTH-1:0] read_addr_valid = read_addr_reg >> (ADDR_WIDTH - VALID_ADDR_WIDTH);
wire [VALID_ADDR_WIDTH-1:0] write_addr_valid = write_addr_reg >> (ADDR_WIDTH - VALID_ADDR_WIDTH);

assign s_axi_awready = s_axi_awready_reg;
assign s_axi_wready = s_axi_wready_reg;
assign s_axi_bid = s_axi_bid_reg;
assign s_axi_bresp = 2'b00;
assign s_axi_bvalid = s_axi_bvalid_reg;
assign s_axi_arready = s_axi_arready_reg;
assign s_axi_rid = PIPELINE_OUTPUT ? s_axi_rid_pipe_reg : s_axi_rid_reg;
assign s_axi_rdata = PIPELINE_OUTPUT ? s_axi_rdata_pipe_reg : s_axi_rdata_reg;
assign s_axi_rresp = 2'b00;
assign s_axi_rlast = PIPELINE_OUTPUT ? s_axi_rlast_pipe_reg : s_axi_rlast_reg;
assign s_axi_rvalid = PIPELINE_OUTPUT ? s_axi_rvalid_pipe_reg : s_axi_rvalid_reg;

integer i, j;

initial begin

  reg[7:0] A[160*4];
  reg[7:0] X[160*4];
  reg[7:0] B[160*4];
  reg[7:0] Y[160*4];
  reg [31:0] C_expect[160*4];
  reg [31:0] C[160*4];
  reg [63:0] val;

  for (int i=0; i<160; i++) begin
    //Keeping all 4 parts of the arrays the same for easy debug.
    //This ensures that the contents of each RAM are the same.
    A[i+0*160] = i;
    X[i+0*160] = i;
    B[i+0*160] = i+10;
    Y[i+0*160] = i+10;

    A[i+1*160] = i;
    X[i+1*160] = i;
    B[i+1*160] = i+10;
    Y[i+1*160] = i+10;
    
    A[i+2*160] = i;
    X[i+2*160] = i;
    B[i+2*160] = i+10;
    Y[i+2*160] = i+10;

    A[i+3*160] = i;
    X[i+3*160] = i;
    B[i+3*160] = i+10;
    Y[i+3*160] = i+10;

    C_expect[i+0*160] = A[i+0*160]*X[i+0*160] + B[i+0*160]*Y[i+0*160];
    C_expect[i+1*160] = A[i+1*160]*X[i+1*160] + B[i+1*160]*Y[i+1*160];
    C_expect[i+2*160] = A[i+2*160]*X[i+2*160] + B[i+2*160]*Y[i+2*160];
    C_expect[i+3*160] = A[i+3*160]*X[i+3*160] + B[i+3*160]*Y[i+3*160];
    //C_expect[i+0*160] = int(B[i+0*160])*int(Y[i+0*160]);
    //C_expect[i+1*160] = int(B[i+1*160])*int(Y[i+1*160]);
    //C_expect[i+2*160] = int(B[i+2*160])*int(Y[i+2*160]);
    //C_expect[i+3*160] = int(B[i+3*160])*int(Y[i+3*160]);
  end

    // two nested loops for smaller number of iterations per loop
    // workaround for synthesizer complaints about large loop counts
    for (i = 0; i < 2**VALID_ADDR_WIDTH; i = i + 2**(VALID_ADDR_WIDTH/2)) begin
        for (j = i; j < i + 2**(VALID_ADDR_WIDTH/2); j = j + 1) begin
            mem[j] = 0;
        end
    end

    //Load real values into the memory
    //Each location is 64 bit wide
    for (int i=0; i<160*4; i++) begin
      val = {Y[i][7:0], B[i][7:0], X[i][7:0], A[i][7:0]};
      mem[i] = val;
    end
end



//Debug signals
wire [DATA_WIDTH-1:0] mem_0; assign mem_0 = mem[0];
wire [DATA_WIDTH-1:0] mem_1; assign mem_1 = mem[1];
wire [DATA_WIDTH-1:0] mem_2; assign mem_2 = mem[2];
wire [DATA_WIDTH-1:0] mem_3; assign mem_3 = mem[3];
wire [DATA_WIDTH-1:0] mem_4; assign mem_4 = mem[4];
wire [DATA_WIDTH-1:0] mem_5; assign mem_5 = mem[5];
wire [DATA_WIDTH-1:0] mem_6; assign mem_6 = mem[6];
wire [DATA_WIDTH-1:0] mem_7; assign mem_7 = mem[7];
wire [DATA_WIDTH-1:0] mem_8; assign mem_8 = mem[8];
wire [DATA_WIDTH-1:0] mem_9; assign mem_9 = mem[9];
wire [DATA_WIDTH-1:0] mem_10; assign mem_10 = mem[10];
wire [DATA_WIDTH-1:0] mem_11; assign mem_11 = mem[11];
wire [DATA_WIDTH-1:0] mem_12; assign mem_12 = mem[12];
wire [DATA_WIDTH-1:0] mem_13; assign mem_13 = mem[13];
wire [DATA_WIDTH-1:0] mem_14; assign mem_14 = mem[14];
wire [DATA_WIDTH-1:0] mem_15; assign mem_15 = mem[15];
wire [DATA_WIDTH-1:0] mem_16; assign mem_16 = mem[16];
wire [DATA_WIDTH-1:0] mem_17; assign mem_17 = mem[17];
wire [DATA_WIDTH-1:0] mem_18; assign mem_18 = mem[18];
wire [DATA_WIDTH-1:0] mem_19; assign mem_19 = mem[19];
wire [DATA_WIDTH-1:0] mem_20; assign mem_20 = mem[20];
wire [DATA_WIDTH-1:0] mem_21; assign mem_21 = mem[21];
wire [DATA_WIDTH-1:0] mem_22; assign mem_22 = mem[22];
wire [DATA_WIDTH-1:0] mem_23; assign mem_23 = mem[23];
wire [DATA_WIDTH-1:0] mem_24; assign mem_24 = mem[24];
wire [DATA_WIDTH-1:0] mem_25; assign mem_25 = mem[25];
wire [DATA_WIDTH-1:0] mem_26; assign mem_26 = mem[26];
wire [DATA_WIDTH-1:0] mem_27; assign mem_27 = mem[27];
wire [DATA_WIDTH-1:0] mem_28; assign mem_28 = mem[28];
wire [DATA_WIDTH-1:0] mem_29; assign mem_29 = mem[29];
wire [DATA_WIDTH-1:0] mem_30; assign mem_30 = mem[30];
wire [DATA_WIDTH-1:0] mem_31; assign mem_31 = mem[31];
wire [DATA_WIDTH-1:0] mem_32; assign mem_32 = mem[32];
wire [DATA_WIDTH-1:0] mem_33; assign mem_33 = mem[33];
wire [DATA_WIDTH-1:0] mem_34; assign mem_34 = mem[34];
wire [DATA_WIDTH-1:0] mem_35; assign mem_35 = mem[35];
wire [DATA_WIDTH-1:0] mem_36; assign mem_36 = mem[36];
wire [DATA_WIDTH-1:0] mem_37; assign mem_37 = mem[37];
wire [DATA_WIDTH-1:0] mem_38; assign mem_38 = mem[38];
wire [DATA_WIDTH-1:0] mem_39; assign mem_39 = mem[39];
wire [DATA_WIDTH-1:0] mem_40; assign mem_40 = mem[40];
wire [DATA_WIDTH-1:0] mem_41; assign mem_41 = mem[41];
wire [DATA_WIDTH-1:0] mem_42; assign mem_42 = mem[42];
wire [DATA_WIDTH-1:0] mem_43; assign mem_43 = mem[43];
wire [DATA_WIDTH-1:0] mem_44; assign mem_44 = mem[44];
wire [DATA_WIDTH-1:0] mem_45; assign mem_45 = mem[45];
wire [DATA_WIDTH-1:0] mem_46; assign mem_46 = mem[46];
wire [DATA_WIDTH-1:0] mem_47; assign mem_47 = mem[47];
wire [DATA_WIDTH-1:0] mem_48; assign mem_48 = mem[48];
wire [DATA_WIDTH-1:0] mem_49; assign mem_49 = mem[49];
wire [DATA_WIDTH-1:0] mem_50; assign mem_50 = mem[50];
wire [DATA_WIDTH-1:0] mem_51; assign mem_51 = mem[51];
wire [DATA_WIDTH-1:0] mem_52; assign mem_52 = mem[52];
wire [DATA_WIDTH-1:0] mem_53; assign mem_53 = mem[53];
wire [DATA_WIDTH-1:0] mem_54; assign mem_54 = mem[54];
wire [DATA_WIDTH-1:0] mem_55; assign mem_55 = mem[55];
wire [DATA_WIDTH-1:0] mem_56; assign mem_56 = mem[56];
wire [DATA_WIDTH-1:0] mem_57; assign mem_57 = mem[57];
wire [DATA_WIDTH-1:0] mem_58; assign mem_58 = mem[58];
wire [DATA_WIDTH-1:0] mem_59; assign mem_59 = mem[59];
wire [DATA_WIDTH-1:0] mem_60; assign mem_60 = mem[60];
wire [DATA_WIDTH-1:0] mem_61; assign mem_61 = mem[61];
wire [DATA_WIDTH-1:0] mem_62; assign mem_62 = mem[62];
wire [DATA_WIDTH-1:0] mem_63; assign mem_63 = mem[63];
wire [DATA_WIDTH-1:0] mem_64; assign mem_64 = mem[64];
wire [DATA_WIDTH-1:0] mem_65; assign mem_65 = mem[65];
wire [DATA_WIDTH-1:0] mem_66; assign mem_66 = mem[66];
wire [DATA_WIDTH-1:0] mem_67; assign mem_67 = mem[67];
wire [DATA_WIDTH-1:0] mem_68; assign mem_68 = mem[68];
wire [DATA_WIDTH-1:0] mem_69; assign mem_69 = mem[69];
wire [DATA_WIDTH-1:0] mem_70; assign mem_70 = mem[70];
wire [DATA_WIDTH-1:0] mem_71; assign mem_71 = mem[71];
wire [DATA_WIDTH-1:0] mem_72; assign mem_72 = mem[72];
wire [DATA_WIDTH-1:0] mem_73; assign mem_73 = mem[73];
wire [DATA_WIDTH-1:0] mem_74; assign mem_74 = mem[74];
wire [DATA_WIDTH-1:0] mem_75; assign mem_75 = mem[75];
wire [DATA_WIDTH-1:0] mem_76; assign mem_76 = mem[76];
wire [DATA_WIDTH-1:0] mem_77; assign mem_77 = mem[77];
wire [DATA_WIDTH-1:0] mem_78; assign mem_78 = mem[78];
wire [DATA_WIDTH-1:0] mem_79; assign mem_79 = mem[79];
wire [DATA_WIDTH-1:0] mem_80; assign mem_80 = mem[80];
wire [DATA_WIDTH-1:0] mem_81; assign mem_81 = mem[81];
wire [DATA_WIDTH-1:0] mem_82; assign mem_82 = mem[82];
wire [DATA_WIDTH-1:0] mem_83; assign mem_83 = mem[83];
wire [DATA_WIDTH-1:0] mem_84; assign mem_84 = mem[84];
wire [DATA_WIDTH-1:0] mem_85; assign mem_85 = mem[85];
wire [DATA_WIDTH-1:0] mem_86; assign mem_86 = mem[86];
wire [DATA_WIDTH-1:0] mem_87; assign mem_87 = mem[87];
wire [DATA_WIDTH-1:0] mem_88; assign mem_88 = mem[88];
wire [DATA_WIDTH-1:0] mem_89; assign mem_89 = mem[89];
wire [DATA_WIDTH-1:0] mem_90; assign mem_90 = mem[90];
wire [DATA_WIDTH-1:0] mem_91; assign mem_91 = mem[91];
wire [DATA_WIDTH-1:0] mem_92; assign mem_92 = mem[92];
wire [DATA_WIDTH-1:0] mem_93; assign mem_93 = mem[93];
wire [DATA_WIDTH-1:0] mem_94; assign mem_94 = mem[94];
wire [DATA_WIDTH-1:0] mem_95; assign mem_95 = mem[95];
wire [DATA_WIDTH-1:0] mem_96; assign mem_96 = mem[96];
wire [DATA_WIDTH-1:0] mem_97; assign mem_97 = mem[97];
wire [DATA_WIDTH-1:0] mem_98; assign mem_98 = mem[98];
wire [DATA_WIDTH-1:0] mem_99; assign mem_99 = mem[99];
wire [DATA_WIDTH-1:0] mem_100; assign mem_100 = mem[100];
wire [DATA_WIDTH-1:0] mem_101; assign mem_101 = mem[101];
wire [DATA_WIDTH-1:0] mem_102; assign mem_102 = mem[102];
wire [DATA_WIDTH-1:0] mem_103; assign mem_103 = mem[103];
wire [DATA_WIDTH-1:0] mem_104; assign mem_104 = mem[104];
wire [DATA_WIDTH-1:0] mem_105; assign mem_105 = mem[105];
wire [DATA_WIDTH-1:0] mem_106; assign mem_106 = mem[106];
wire [DATA_WIDTH-1:0] mem_107; assign mem_107 = mem[107];
wire [DATA_WIDTH-1:0] mem_108; assign mem_108 = mem[108];
wire [DATA_WIDTH-1:0] mem_109; assign mem_109 = mem[109];
wire [DATA_WIDTH-1:0] mem_110; assign mem_110 = mem[110];
wire [DATA_WIDTH-1:0] mem_111; assign mem_111 = mem[111];
wire [DATA_WIDTH-1:0] mem_112; assign mem_112 = mem[112];
wire [DATA_WIDTH-1:0] mem_113; assign mem_113 = mem[113];
wire [DATA_WIDTH-1:0] mem_114; assign mem_114 = mem[114];
wire [DATA_WIDTH-1:0] mem_115; assign mem_115 = mem[115];
wire [DATA_WIDTH-1:0] mem_116; assign mem_116 = mem[116];
wire [DATA_WIDTH-1:0] mem_117; assign mem_117 = mem[117];
wire [DATA_WIDTH-1:0] mem_118; assign mem_118 = mem[118];
wire [DATA_WIDTH-1:0] mem_119; assign mem_119 = mem[119];
wire [DATA_WIDTH-1:0] mem_120; assign mem_120 = mem[120];
wire [DATA_WIDTH-1:0] mem_121; assign mem_121 = mem[121];
wire [DATA_WIDTH-1:0] mem_122; assign mem_122 = mem[122];
wire [DATA_WIDTH-1:0] mem_123; assign mem_123 = mem[123];
wire [DATA_WIDTH-1:0] mem_124; assign mem_124 = mem[124];
wire [DATA_WIDTH-1:0] mem_125; assign mem_125 = mem[125];
wire [DATA_WIDTH-1:0] mem_126; assign mem_126 = mem[126];
wire [DATA_WIDTH-1:0] mem_127; assign mem_127 = mem[127];
wire [DATA_WIDTH-1:0] mem_128; assign mem_128 = mem[128];
wire [DATA_WIDTH-1:0] mem_129; assign mem_129 = mem[129];
wire [DATA_WIDTH-1:0] mem_130; assign mem_130 = mem[130];
wire [DATA_WIDTH-1:0] mem_131; assign mem_131 = mem[131];
wire [DATA_WIDTH-1:0] mem_132; assign mem_132 = mem[132];
wire [DATA_WIDTH-1:0] mem_133; assign mem_133 = mem[133];
wire [DATA_WIDTH-1:0] mem_134; assign mem_134 = mem[134];
wire [DATA_WIDTH-1:0] mem_135; assign mem_135 = mem[135];
wire [DATA_WIDTH-1:0] mem_136; assign mem_136 = mem[136];
wire [DATA_WIDTH-1:0] mem_137; assign mem_137 = mem[137];
wire [DATA_WIDTH-1:0] mem_138; assign mem_138 = mem[138];
wire [DATA_WIDTH-1:0] mem_139; assign mem_139 = mem[139];
wire [DATA_WIDTH-1:0] mem_140; assign mem_140 = mem[140];
wire [DATA_WIDTH-1:0] mem_141; assign mem_141 = mem[141];
wire [DATA_WIDTH-1:0] mem_142; assign mem_142 = mem[142];
wire [DATA_WIDTH-1:0] mem_143; assign mem_143 = mem[143];
wire [DATA_WIDTH-1:0] mem_144; assign mem_144 = mem[144];
wire [DATA_WIDTH-1:0] mem_145; assign mem_145 = mem[145];
wire [DATA_WIDTH-1:0] mem_146; assign mem_146 = mem[146];
wire [DATA_WIDTH-1:0] mem_147; assign mem_147 = mem[147];
wire [DATA_WIDTH-1:0] mem_148; assign mem_148 = mem[148];
wire [DATA_WIDTH-1:0] mem_149; assign mem_149 = mem[149];
wire [DATA_WIDTH-1:0] mem_150; assign mem_150 = mem[150];
wire [DATA_WIDTH-1:0] mem_151; assign mem_151 = mem[151];
wire [DATA_WIDTH-1:0] mem_152; assign mem_152 = mem[152];
wire [DATA_WIDTH-1:0] mem_153; assign mem_153 = mem[153];
wire [DATA_WIDTH-1:0] mem_154; assign mem_154 = mem[154];
wire [DATA_WIDTH-1:0] mem_155; assign mem_155 = mem[155];
wire [DATA_WIDTH-1:0] mem_156; assign mem_156 = mem[156];
wire [DATA_WIDTH-1:0] mem_157; assign mem_157 = mem[157];
wire [DATA_WIDTH-1:0] mem_158; assign mem_158 = mem[158];
wire [DATA_WIDTH-1:0] mem_159; assign mem_159 = mem[159];
wire [DATA_WIDTH-1:0] mem_160; assign mem_160 = mem[160];
wire [DATA_WIDTH-1:0] mem_161; assign mem_161 = mem[161];
wire [DATA_WIDTH-1:0] mem_162; assign mem_162 = mem[162];
wire [DATA_WIDTH-1:0] mem_163; assign mem_163 = mem[163];
wire [DATA_WIDTH-1:0] mem_164; assign mem_164 = mem[164];
wire [DATA_WIDTH-1:0] mem_165; assign mem_165 = mem[165];
wire [DATA_WIDTH-1:0] mem_166; assign mem_166 = mem[166];
wire [DATA_WIDTH-1:0] mem_167; assign mem_167 = mem[167];
wire [DATA_WIDTH-1:0] mem_168; assign mem_168 = mem[168];
wire [DATA_WIDTH-1:0] mem_169; assign mem_169 = mem[169];
wire [DATA_WIDTH-1:0] mem_170; assign mem_170 = mem[170];
wire [DATA_WIDTH-1:0] mem_171; assign mem_171 = mem[171];
wire [DATA_WIDTH-1:0] mem_172; assign mem_172 = mem[172];
wire [DATA_WIDTH-1:0] mem_173; assign mem_173 = mem[173];
wire [DATA_WIDTH-1:0] mem_174; assign mem_174 = mem[174];
wire [DATA_WIDTH-1:0] mem_175; assign mem_175 = mem[175];
wire [DATA_WIDTH-1:0] mem_176; assign mem_176 = mem[176];
wire [DATA_WIDTH-1:0] mem_177; assign mem_177 = mem[177];
wire [DATA_WIDTH-1:0] mem_178; assign mem_178 = mem[178];
wire [DATA_WIDTH-1:0] mem_179; assign mem_179 = mem[179];
wire [DATA_WIDTH-1:0] mem_180; assign mem_180 = mem[180];
wire [DATA_WIDTH-1:0] mem_181; assign mem_181 = mem[181];
wire [DATA_WIDTH-1:0] mem_182; assign mem_182 = mem[182];
wire [DATA_WIDTH-1:0] mem_183; assign mem_183 = mem[183];
wire [DATA_WIDTH-1:0] mem_184; assign mem_184 = mem[184];
wire [DATA_WIDTH-1:0] mem_185; assign mem_185 = mem[185];
wire [DATA_WIDTH-1:0] mem_186; assign mem_186 = mem[186];
wire [DATA_WIDTH-1:0] mem_187; assign mem_187 = mem[187];
wire [DATA_WIDTH-1:0] mem_188; assign mem_188 = mem[188];
wire [DATA_WIDTH-1:0] mem_189; assign mem_189 = mem[189];
wire [DATA_WIDTH-1:0] mem_190; assign mem_190 = mem[190];
wire [DATA_WIDTH-1:0] mem_191; assign mem_191 = mem[191];
wire [DATA_WIDTH-1:0] mem_192; assign mem_192 = mem[192];
wire [DATA_WIDTH-1:0] mem_193; assign mem_193 = mem[193];
wire [DATA_WIDTH-1:0] mem_194; assign mem_194 = mem[194];
wire [DATA_WIDTH-1:0] mem_195; assign mem_195 = mem[195];
wire [DATA_WIDTH-1:0] mem_196; assign mem_196 = mem[196];
wire [DATA_WIDTH-1:0] mem_197; assign mem_197 = mem[197];
wire [DATA_WIDTH-1:0] mem_198; assign mem_198 = mem[198];
wire [DATA_WIDTH-1:0] mem_199; assign mem_199 = mem[199];
wire [DATA_WIDTH-1:0] mem_200; assign mem_200 = mem[200];
wire [DATA_WIDTH-1:0] mem_201; assign mem_201 = mem[201];
wire [DATA_WIDTH-1:0] mem_202; assign mem_202 = mem[202];
wire [DATA_WIDTH-1:0] mem_203; assign mem_203 = mem[203];
wire [DATA_WIDTH-1:0] mem_204; assign mem_204 = mem[204];
wire [DATA_WIDTH-1:0] mem_205; assign mem_205 = mem[205];
wire [DATA_WIDTH-1:0] mem_206; assign mem_206 = mem[206];
wire [DATA_WIDTH-1:0] mem_207; assign mem_207 = mem[207];
wire [DATA_WIDTH-1:0] mem_208; assign mem_208 = mem[208];
wire [DATA_WIDTH-1:0] mem_209; assign mem_209 = mem[209];
wire [DATA_WIDTH-1:0] mem_210; assign mem_210 = mem[210];
wire [DATA_WIDTH-1:0] mem_211; assign mem_211 = mem[211];
wire [DATA_WIDTH-1:0] mem_212; assign mem_212 = mem[212];
wire [DATA_WIDTH-1:0] mem_213; assign mem_213 = mem[213];
wire [DATA_WIDTH-1:0] mem_214; assign mem_214 = mem[214];
wire [DATA_WIDTH-1:0] mem_215; assign mem_215 = mem[215];
wire [DATA_WIDTH-1:0] mem_216; assign mem_216 = mem[216];
wire [DATA_WIDTH-1:0] mem_217; assign mem_217 = mem[217];
wire [DATA_WIDTH-1:0] mem_218; assign mem_218 = mem[218];
wire [DATA_WIDTH-1:0] mem_219; assign mem_219 = mem[219];
wire [DATA_WIDTH-1:0] mem_220; assign mem_220 = mem[220];
wire [DATA_WIDTH-1:0] mem_221; assign mem_221 = mem[221];
wire [DATA_WIDTH-1:0] mem_222; assign mem_222 = mem[222];
wire [DATA_WIDTH-1:0] mem_223; assign mem_223 = mem[223];
wire [DATA_WIDTH-1:0] mem_224; assign mem_224 = mem[224];
wire [DATA_WIDTH-1:0] mem_225; assign mem_225 = mem[225];
wire [DATA_WIDTH-1:0] mem_226; assign mem_226 = mem[226];
wire [DATA_WIDTH-1:0] mem_227; assign mem_227 = mem[227];
wire [DATA_WIDTH-1:0] mem_228; assign mem_228 = mem[228];
wire [DATA_WIDTH-1:0] mem_229; assign mem_229 = mem[229];
wire [DATA_WIDTH-1:0] mem_230; assign mem_230 = mem[230];
wire [DATA_WIDTH-1:0] mem_231; assign mem_231 = mem[231];
wire [DATA_WIDTH-1:0] mem_232; assign mem_232 = mem[232];
wire [DATA_WIDTH-1:0] mem_233; assign mem_233 = mem[233];
wire [DATA_WIDTH-1:0] mem_234; assign mem_234 = mem[234];
wire [DATA_WIDTH-1:0] mem_235; assign mem_235 = mem[235];
wire [DATA_WIDTH-1:0] mem_236; assign mem_236 = mem[236];
wire [DATA_WIDTH-1:0] mem_237; assign mem_237 = mem[237];
wire [DATA_WIDTH-1:0] mem_238; assign mem_238 = mem[238];
wire [DATA_WIDTH-1:0] mem_239; assign mem_239 = mem[239];
wire [DATA_WIDTH-1:0] mem_240; assign mem_240 = mem[240];
wire [DATA_WIDTH-1:0] mem_241; assign mem_241 = mem[241];
wire [DATA_WIDTH-1:0] mem_242; assign mem_242 = mem[242];
wire [DATA_WIDTH-1:0] mem_243; assign mem_243 = mem[243];
wire [DATA_WIDTH-1:0] mem_244; assign mem_244 = mem[244];
wire [DATA_WIDTH-1:0] mem_245; assign mem_245 = mem[245];
wire [DATA_WIDTH-1:0] mem_246; assign mem_246 = mem[246];
wire [DATA_WIDTH-1:0] mem_247; assign mem_247 = mem[247];
wire [DATA_WIDTH-1:0] mem_248; assign mem_248 = mem[248];
wire [DATA_WIDTH-1:0] mem_249; assign mem_249 = mem[249];
wire [DATA_WIDTH-1:0] mem_250; assign mem_250 = mem[250];
wire [DATA_WIDTH-1:0] mem_251; assign mem_251 = mem[251];
wire [DATA_WIDTH-1:0] mem_252; assign mem_252 = mem[252];
wire [DATA_WIDTH-1:0] mem_253; assign mem_253 = mem[253];
wire [DATA_WIDTH-1:0] mem_254; assign mem_254 = mem[254];
wire [DATA_WIDTH-1:0] mem_255; assign mem_255 = mem[255];
wire [DATA_WIDTH-1:0] mem_256; assign mem_256 = mem[256];
wire [DATA_WIDTH-1:0] mem_257; assign mem_257 = mem[257];
wire [DATA_WIDTH-1:0] mem_258; assign mem_258 = mem[258];
wire [DATA_WIDTH-1:0] mem_259; assign mem_259 = mem[259];
wire [DATA_WIDTH-1:0] mem_260; assign mem_260 = mem[260];
wire [DATA_WIDTH-1:0] mem_261; assign mem_261 = mem[261];
wire [DATA_WIDTH-1:0] mem_262; assign mem_262 = mem[262];
wire [DATA_WIDTH-1:0] mem_263; assign mem_263 = mem[263];
wire [DATA_WIDTH-1:0] mem_264; assign mem_264 = mem[264];
wire [DATA_WIDTH-1:0] mem_265; assign mem_265 = mem[265];
wire [DATA_WIDTH-1:0] mem_266; assign mem_266 = mem[266];
wire [DATA_WIDTH-1:0] mem_267; assign mem_267 = mem[267];
wire [DATA_WIDTH-1:0] mem_268; assign mem_268 = mem[268];
wire [DATA_WIDTH-1:0] mem_269; assign mem_269 = mem[269];
wire [DATA_WIDTH-1:0] mem_270; assign mem_270 = mem[270];
wire [DATA_WIDTH-1:0] mem_271; assign mem_271 = mem[271];
wire [DATA_WIDTH-1:0] mem_272; assign mem_272 = mem[272];
wire [DATA_WIDTH-1:0] mem_273; assign mem_273 = mem[273];
wire [DATA_WIDTH-1:0] mem_274; assign mem_274 = mem[274];
wire [DATA_WIDTH-1:0] mem_275; assign mem_275 = mem[275];
wire [DATA_WIDTH-1:0] mem_276; assign mem_276 = mem[276];
wire [DATA_WIDTH-1:0] mem_277; assign mem_277 = mem[277];
wire [DATA_WIDTH-1:0] mem_278; assign mem_278 = mem[278];
wire [DATA_WIDTH-1:0] mem_279; assign mem_279 = mem[279];
wire [DATA_WIDTH-1:0] mem_280; assign mem_280 = mem[280];
wire [DATA_WIDTH-1:0] mem_281; assign mem_281 = mem[281];
wire [DATA_WIDTH-1:0] mem_282; assign mem_282 = mem[282];
wire [DATA_WIDTH-1:0] mem_283; assign mem_283 = mem[283];
wire [DATA_WIDTH-1:0] mem_284; assign mem_284 = mem[284];
wire [DATA_WIDTH-1:0] mem_285; assign mem_285 = mem[285];
wire [DATA_WIDTH-1:0] mem_286; assign mem_286 = mem[286];
wire [DATA_WIDTH-1:0] mem_287; assign mem_287 = mem[287];
wire [DATA_WIDTH-1:0] mem_288; assign mem_288 = mem[288];
wire [DATA_WIDTH-1:0] mem_289; assign mem_289 = mem[289];
wire [DATA_WIDTH-1:0] mem_290; assign mem_290 = mem[290];
wire [DATA_WIDTH-1:0] mem_291; assign mem_291 = mem[291];
wire [DATA_WIDTH-1:0] mem_292; assign mem_292 = mem[292];
wire [DATA_WIDTH-1:0] mem_293; assign mem_293 = mem[293];
wire [DATA_WIDTH-1:0] mem_294; assign mem_294 = mem[294];
wire [DATA_WIDTH-1:0] mem_295; assign mem_295 = mem[295];
wire [DATA_WIDTH-1:0] mem_296; assign mem_296 = mem[296];
wire [DATA_WIDTH-1:0] mem_297; assign mem_297 = mem[297];
wire [DATA_WIDTH-1:0] mem_298; assign mem_298 = mem[298];
wire [DATA_WIDTH-1:0] mem_299; assign mem_299 = mem[299];
wire [DATA_WIDTH-1:0] mem_300; assign mem_300 = mem[300];
wire [DATA_WIDTH-1:0] mem_301; assign mem_301 = mem[301];
wire [DATA_WIDTH-1:0] mem_302; assign mem_302 = mem[302];
wire [DATA_WIDTH-1:0] mem_303; assign mem_303 = mem[303];
wire [DATA_WIDTH-1:0] mem_304; assign mem_304 = mem[304];
wire [DATA_WIDTH-1:0] mem_305; assign mem_305 = mem[305];
wire [DATA_WIDTH-1:0] mem_306; assign mem_306 = mem[306];
wire [DATA_WIDTH-1:0] mem_307; assign mem_307 = mem[307];
wire [DATA_WIDTH-1:0] mem_308; assign mem_308 = mem[308];
wire [DATA_WIDTH-1:0] mem_309; assign mem_309 = mem[309];
wire [DATA_WIDTH-1:0] mem_310; assign mem_310 = mem[310];
wire [DATA_WIDTH-1:0] mem_311; assign mem_311 = mem[311];
wire [DATA_WIDTH-1:0] mem_312; assign mem_312 = mem[312];
wire [DATA_WIDTH-1:0] mem_313; assign mem_313 = mem[313];
wire [DATA_WIDTH-1:0] mem_314; assign mem_314 = mem[314];
wire [DATA_WIDTH-1:0] mem_315; assign mem_315 = mem[315];
wire [DATA_WIDTH-1:0] mem_316; assign mem_316 = mem[316];
wire [DATA_WIDTH-1:0] mem_317; assign mem_317 = mem[317];
wire [DATA_WIDTH-1:0] mem_318; assign mem_318 = mem[318];
wire [DATA_WIDTH-1:0] mem_319; assign mem_319 = mem[319];



always @* begin
    write_state_next = WRITE_STATE_IDLE;

    mem_wr_en = 1'b0;

    write_id_next = write_id_reg;
    write_addr_next = write_addr_reg;
    write_count_next = write_count_reg;
    write_size_next = write_size_reg;
    write_burst_next = write_burst_reg;

    s_axi_awready_next = 1'b0;
    s_axi_wready_next = 1'b0;
    s_axi_bid_next = s_axi_bid_reg;
    s_axi_bvalid_next = s_axi_bvalid_reg && !s_axi_bready;

    case (write_state_reg)
        WRITE_STATE_IDLE: begin
            s_axi_awready_next = 1'b1;

            if (s_axi_awready && s_axi_awvalid) begin
                write_id_next = s_axi_awid;
                write_addr_next = s_axi_awaddr;
                write_count_next = s_axi_awlen;
                write_size_next = s_axi_awsize < $clog2(STRB_WIDTH) ? s_axi_awsize : $clog2(STRB_WIDTH);
                write_burst_next = s_axi_awburst;

                s_axi_awready_next = 1'b0;
                s_axi_wready_next = 1'b1;
                write_state_next = WRITE_STATE_BURST;
            end else begin
                write_state_next = WRITE_STATE_IDLE;
            end
        end
        WRITE_STATE_BURST: begin
            s_axi_wready_next = 1'b1;

            if (s_axi_wready && s_axi_wvalid) begin
                mem_wr_en = 1'b1;
                if (write_burst_reg != 2'b00) begin
                    write_addr_next = write_addr_reg + (1 << write_size_reg);
                end
                write_count_next = write_count_reg - 1;
                if (write_count_reg > 0) begin
                    write_state_next = WRITE_STATE_BURST;
                end else begin
                    s_axi_wready_next = 1'b0;
                    if (s_axi_bready || !s_axi_bvalid) begin
                        s_axi_bid_next = write_id_reg;
                        s_axi_bvalid_next = 1'b1;
                        s_axi_awready_next = 1'b1;
                        write_state_next = WRITE_STATE_IDLE;
                    end else begin
                        write_state_next = WRITE_STATE_RESP;
                    end
                end
            end else begin
                write_state_next = WRITE_STATE_BURST;
            end
        end
        WRITE_STATE_RESP: begin
            if (s_axi_bready || !s_axi_bvalid) begin
                s_axi_bid_next = write_id_reg;
                s_axi_bvalid_next = 1'b1;
                s_axi_awready_next = 1'b1;
                write_state_next = WRITE_STATE_IDLE;
            end else begin
                write_state_next = WRITE_STATE_RESP;
            end
        end
    endcase
end

always @(posedge clk) begin
    write_state_reg <= write_state_next;

    write_id_reg <= write_id_next;
    write_addr_reg <= write_addr_next;
    write_count_reg <= write_count_next;
    write_size_reg <= write_size_next;
    write_burst_reg <= write_burst_next;

    s_axi_awready_reg <= s_axi_awready_next;
    s_axi_wready_reg <= s_axi_wready_next;
    s_axi_bid_reg <= s_axi_bid_next;
    s_axi_bvalid_reg <= s_axi_bvalid_next;

    for (i = 0; i < WORD_WIDTH; i = i + 1) begin
        if (mem_wr_en & s_axi_wstrb[i]) begin
            mem[write_addr_valid][WORD_SIZE*i +: WORD_SIZE] <= s_axi_wdata[WORD_SIZE*i +: WORD_SIZE];
        end
    end

    if (rst) begin
        write_state_reg <= WRITE_STATE_IDLE;

        s_axi_awready_reg <= 1'b0;
        s_axi_wready_reg <= 1'b0;
        s_axi_bvalid_reg <= 1'b0;
    end
end

always @* begin
    read_state_next = READ_STATE_IDLE;

    mem_rd_en = 1'b0;

    s_axi_rid_next = s_axi_rid_reg;
    s_axi_rlast_next = s_axi_rlast_reg;
    s_axi_rvalid_next = s_axi_rvalid_reg && !(s_axi_rready || (PIPELINE_OUTPUT && !s_axi_rvalid_pipe_reg));

    read_id_next = read_id_reg;
    read_addr_next = read_addr_reg;
    read_count_next = read_count_reg;
    read_size_next = read_size_reg;
    read_burst_next = read_burst_reg;

    s_axi_arready_next = 1'b0;

    case (read_state_reg)
        READ_STATE_IDLE: begin
            s_axi_arready_next = 1'b1;

            if (s_axi_arready && s_axi_arvalid) begin
                read_id_next = s_axi_arid;
                read_addr_next = s_axi_araddr;
                read_count_next = s_axi_arlen;
                read_size_next = s_axi_arsize < $clog2(STRB_WIDTH) ? s_axi_arsize : $clog2(STRB_WIDTH);
                read_burst_next = s_axi_arburst;

                s_axi_arready_next = 1'b0;
                read_state_next = READ_STATE_BURST;
            end else begin
                read_state_next = READ_STATE_IDLE;
            end
        end
        READ_STATE_BURST: begin
            if (s_axi_rready || (PIPELINE_OUTPUT && !s_axi_rvalid_pipe_reg) || !s_axi_rvalid_reg) begin
                mem_rd_en = 1'b1;
                s_axi_rvalid_next = 1'b1;
                s_axi_rid_next = read_id_reg;
                s_axi_rlast_next = read_count_reg == 0;
                if (read_burst_reg != 2'b00) begin
                    read_addr_next = read_addr_reg + (1 << read_size_reg);
                end
                read_count_next = read_count_reg - 1;
                if (read_count_reg > 0) begin
                    read_state_next = READ_STATE_BURST;
                end else begin
                    s_axi_arready_next = 1'b1;
                    read_state_next = READ_STATE_IDLE;
                end
            end else begin
                read_state_next = READ_STATE_BURST;
            end
        end
    endcase
end

always @(posedge clk) begin
    read_state_reg <= read_state_next;

    read_id_reg <= read_id_next;
    read_addr_reg <= read_addr_next;
    read_count_reg <= read_count_next;
    read_size_reg <= read_size_next;
    read_burst_reg <= read_burst_next;

    s_axi_arready_reg <= s_axi_arready_next;
    s_axi_rid_reg <= s_axi_rid_next;
    s_axi_rlast_reg <= s_axi_rlast_next;
    s_axi_rvalid_reg <= s_axi_rvalid_next;

    if (mem_rd_en) begin
        s_axi_rdata_reg <= mem[read_addr_valid];
    end

    if (!s_axi_rvalid_pipe_reg || s_axi_rready) begin
        s_axi_rid_pipe_reg <= s_axi_rid_reg;
        s_axi_rdata_pipe_reg <= s_axi_rdata_reg;
        s_axi_rlast_pipe_reg <= s_axi_rlast_reg;
        s_axi_rvalid_pipe_reg <= s_axi_rvalid_reg;
    end

    if (rst) begin
        read_state_reg <= READ_STATE_IDLE;

        s_axi_arready_reg <= 1'b0;
        s_axi_rvalid_reg <= 1'b0;
        s_axi_rvalid_pipe_reg <= 1'b0;
    end
end

endmodule
