module comefa(
    //write port
    addr1, 
    d1, 
    we1, 
    //read port
    addr2, 
    q2,  
    //direct interconnect
    pe_top,
    pe_bot,
    clk
);

input [`AWIDTH-1:0] addr1;
input [`DWIDTH-1:0] d1;
input we1;

input [`AWIDTH-1:0] addr2;
output reg [`DWIDTH-1:0] q2;

inout pe_top;
inout pe_bot;
input clk;

//ram that matches external interface
reg [`DWIDTH-1:0] ram[((1<<`AWIDTH)-1):0];

//ram that is based on the internal configuration
//a 160x128 ram
reg [`NUM_COLS-1:0] ram_internal[`NUM_ROWS-1:0];

//Writing to the special address implies compute mode
wire compute_mode;
assign compute_mode = (addr1 == `CMD_ADDR) && (we1);

/////////////////////////////////////////////////////
// Compute mode behavioral model
/////////////////////////////////////////////////////
//If Address is `CMD_ADDR, then the data contains the command.

//The structure of the commnd is:
//<PREDICATE> <DUMMY< <B_SEL> <B_DATA> <WRITE_EN> <WRITE_SEL> <PORT> <C_RST> <C_EN> <M_RST>  <M_EN>  <TRUTH_TABLE>  <dst_row> <src2_row> <src1_row>
//   2 bits   3 bits   1 bit    1 bit    1 bit    2 bits     1 bit  1 bit   1 bit  1 bit    1 bit     4 bits       7 bits     7 bits      7 bits

//Row addresses are 7 bits because the organization is 128x160
//In some cases like COPY or SHIFT, one of the
//src rows will be blank.

wire [1:0] predicate;
wire [2:0] dummy;
wire b_sel;
wire b_data;
wire write_en;
wire [1:0] write_sel;
wire port;
wire c_rst;
wire c_en;
wire m_rst;
wire m_en;
wire [3:0] truth_table;
wire [6:0] dst;
wire [6:0] src2;
wire [6:0] src1;

assign predicate   = d1[39:38];
assign dummy       = d1[37:35];
assign b_sel       = d1[34];
assign b_data      = d1[33];
assign write_en    = d1[32];
assign write_sel   = d1[31:30];
assign port        = d1[29];
assign c_rst       = d1[28];
assign c_en        = d1[27];
assign m_rst       = d1[26];
assign m_en        = d1[25];
assign truth_table = d1[24:21];
assign dst         = d1[20:14];
assign src2        = d1[13:7];
assign src1        = d1[6:0];

//The following are not actual flops or latches.
//Just declared as reg to be able to assign to
//them in always@(*) (combinatorial) blocks.
reg [`NUM_COLS-1:0] op1;
reg [`NUM_COLS-1:0] op2;
reg [`NUM_COLS-1:0] tt_mux_out;
reg [`NUM_COLS-1:0] sum;
reg [`NUM_COLS-1:0] cout; 
reg [`NUM_COLS-1:0] cin; //actual latch
reg [`NUM_COLS-1:0] mask; //actual latch
reg [`NUM_COLS-1:0] pred_mux_out;
reg [`NUM_COLS-1:0] wsel1_mux_out;
reg [`NUM_COLS-1:0] wsel2_mux_out;
reg [`NUM_COLS-1:0] ram_internal_temp[`NUM_ROWS-1:0];
reg error;

//Behavioral reset
integer i;
initial begin
  for (i=0; i<`NUM_ROWS; i=i+1) begin
    ram_internal_temp[i] = 0;
  end
  cin = 0;
  cout = 0;
  mask = 0;
  error = 0;
end

///////////////////////////////////////////////
//Tri-state switches for shifting
///////////////////////////////////////////////
reg pe_top_lshift;
wire pe_top_rshift;
wire pe_bot_lshift;
reg pe_bot_rshift;

wire lshift;
wire rshift;

assign lshift = compute_mode & (port==1'b0) & (write_sel==2'b00);
assign rshift = compute_mode & (port==1'b1) & (write_sel==2'b10);

assign pe_top = lshift ? pe_top_lshift : 1'bz;
assign pe_top_rshift = rshift ? pe_top : 1'bz;
assign pe_bot = rshift ? pe_bot_rshift : 1'bz;
assign pe_bot_lshift = lshift ? pe_bot : 1'bz;

always @(posedge clk) begin 
    if (compute_mode) begin

        ///////////////////////////////////////////////
        // Read operands
        ///////////////////////////////////////////////
        //Operands come from two rows in the RAM
        op1 = ram_internal[src1];
        if (b_sel==1'b1) begin
            op2 = {`NUM_COLS{b_data}};
        end 
        else begin
            op2 = ram_internal[src2];
        end

        ///////////////////////////////////////////////
        // Truth table mux, sum and carry
        ///////////////////////////////////////////////
        for (i=0; i<`NUM_COLS; i++) begin
            //Select lines of the truth table mux are driven by
            //the two operands read from the RAM
            case({op2[i],op1[i]})
            2'b00: tt_mux_out[i] = truth_table[0];
            2'b01: tt_mux_out[i] = truth_table[1];
            2'b10: tt_mux_out[i] = truth_table[2];
            2'b11: tt_mux_out[i] = truth_table[3];
            endcase

            //Obtain the sum
            sum[i] = tt_mux_out[i] ^ cin[i];

            //Obain the carry
            cout[i] = (op1[i] & op2[i]) | (op1[i] & cin[i]) | (op2[i] & cin[i]);
        end


        ///////////////////////////////////////////////
        //Predication logic
        ///////////////////////////////////////////////
        for (i=0; i<`NUM_COLS; i++) begin
            case(predicate)
            2'b00: pred_mux_out[i] = mask[i];  //last cycle's value of mask (in this cycle m_en should be 0)
            2'b01: pred_mux_out[i] = cin[i];   //last cycle's value of carry (in this cycle c_en should be 0)
            2'b10: pred_mux_out[i] = ~cin[i];  //last cycle's value of carry (in this cycle c_en should be 0)
            2'b11: pred_mux_out[i] = 1'b1;
            endcase
        end

        ///////////////////////////////////////////////
        //Write select logic
        ///////////////////////////////////////////////
        //write_sel1 mux

        //Right most PE
        case(write_sel)
        2'b00:   wsel1_mux_out[0] = pe_bot_lshift; //shift path
        2'b01:   wsel1_mux_out[0] = sum[0];
        default: if (!port) begin
            error = 1;
            //$display("%t: Incorrect selection", $time); //not allowed
        end
        endcase

        //Other PEs
        for (i=1; i<`NUM_COLS; i++) begin
            case(write_sel)
            2'b00:   wsel1_mux_out[i] = sum[i-1]; //left PE's sum (shift path)
            2'b01:   wsel1_mux_out[i] = sum[i];   //current PE's sum
            default: if (!port) begin
                error = 1;
                //$display("%t: Incorrect selection", $time); //not allowed
            end
            endcase
        end

        pe_top_lshift = sum[`NUM_COLS-1];

        //write_sel2 mux
        pe_bot_rshift = sum[0];
        
        //Other PEs
        for (i=0; i<`NUM_COLS-1; i++) begin
            case(write_sel)
            2'b01:   wsel2_mux_out[i] = cin[i];   //current PE's carry
            2'b10:   wsel2_mux_out[i] = sum[i+1]; //right PE's sum (shift path)
            default: if (port) begin
                error = 1;
                //$display("%t: Incorrect selection", $time); //not allowed
            end
            endcase
        end

        //Left most PE
        case(write_sel)
        2'b01:   wsel2_mux_out[`NUM_COLS-1] = cin[`NUM_COLS-1];
        2'b10:   wsel2_mux_out[`NUM_COLS-1] = pe_top_rshift; //shift path
        default: if (port) begin
            error = 1;
            //$display("%t: Incorrect selection", $time); //not allowed
        end
        endcase

        ///////////////////////////////////////////////
        //Write results 
        ///////////////////////////////////////////////
        for (i=0; i<`NUM_COLS; i++) begin
            if (pred_mux_out[i] && write_en) begin
                if (port) begin
                    ram_internal_temp[dst][i] = wsel2_mux_out[i];
                end
                else begin
                    ram_internal_temp[dst][i] = wsel1_mux_out[i];
                end
            end
        end

        /////////////////////////////////////////////////
        // Updating actual arrays at clock edge
        /////////////////////////////////////////////////
        ram_internal[dst] <= ram_internal_temp[dst];
        ram[(dst<<2)+0] <= ram_internal_temp[dst][1*`DWIDTH-1:0*`DWIDTH];
        ram[(dst<<2)+1] <= ram_internal_temp[dst][2*`DWIDTH-1:1*`DWIDTH];
        ram[(dst<<2)+2] <= ram_internal_temp[dst][3*`DWIDTH-1:2*`DWIDTH];
        ram[(dst<<2)+3] <= ram_internal_temp[dst][4*`DWIDTH-1:3*`DWIDTH];

        //This is to model the delay in the peripherals.
        //Technically, this is not required.
        //#1;

        //The following two piece of code (carry and mask latch)
        //should appear in the end. Any operation done above
        //should use the old value of the carry and latch.

        ///////////////////////////////////////////////
        // Carry latch (save for next cycle)
        ///////////////////////////////////////////////
        if (c_rst) begin
            cin = 0;
        end
        else if (c_en) begin
            cin = cout;
        end

        ///////////////////////////////////////////////
        // Mask latch (save for next cycle)
        ///////////////////////////////////////////////
        if (m_rst) begin
            mask = 0;
        end
        else if (m_en) begin
            mask = tt_mux_out;
        end
    end
end


/////////////////////////////////////////////////
// Storage mode behavioral model
/////////////////////////////////////////////////
always @(posedge clk) begin
    if (!compute_mode) begin
        //write port
        if (we1) begin
          ram[addr1] <= d1;
          //Also update ram_internal
          case (addr1[1:0]) 
          2'b00 : ram_internal[addr1[`AWIDTH-1:2]][1*`DWIDTH-1:0*`DWIDTH] <= d1;
          2'b01 : ram_internal[addr1[`AWIDTH-1:2]][2*`DWIDTH-1:1*`DWIDTH] <= d1;
          2'b10 : ram_internal[addr1[`AWIDTH-1:2]][3*`DWIDTH-1:2*`DWIDTH] <= d1;
          2'b11 : ram_internal[addr1[`AWIDTH-1:2]][4*`DWIDTH-1:3*`DWIDTH] <= d1;
          endcase
        end

        //read port
        else begin
            q2 <= ram[addr2];
        end
    end  
end

/////////////////////////////////////////////////
// Debug signals
/////////////////////////////////////////////////

wire [159:0] row0;
assign row0 = ram_internal[0];

wire [159:0] row1;
assign row1 = ram_internal[1];

wire [159:0] row2;
assign row2 = ram_internal[2];

wire [159:0] row3;
assign row3 = ram_internal[3];

wire [159:0] row4;
assign row4 = ram_internal[4];

wire [159:0] row5;
assign row5 = ram_internal[5];

wire [159:0] row6;
assign row6 = ram_internal[6];

wire [159:0] row7;
assign row7 = ram_internal[7];

wire [159:0] row8;
assign row8 = ram_internal[8];

wire [159:0] row9;
assign row9 = ram_internal[9];

wire [159:0] row10;
assign row10 = ram_internal[10];

wire [159:0] row11;
assign row11 = ram_internal[11];

wire [159:0] row12;
assign row12 = ram_internal[12];

wire [159:0] row13;
assign row13 = ram_internal[13];

wire [159:0] row14;
assign row14 = ram_internal[14];

wire [159:0] row15;
assign row15 = ram_internal[15];

wire [159:0] row16;
assign row16 = ram_internal[16];

wire [159:0] row17;
assign row17 = ram_internal[17];

wire [159:0] row18;
assign row18 = ram_internal[18];

wire [159:0] row19;
assign row19 = ram_internal[19];

wire [159:0] row20;
assign row20 = ram_internal[20];

wire [159:0] row21;
assign row21 = ram_internal[21];

wire [159:0] row22;
assign row22 = ram_internal[22];

wire [159:0] row23;
assign row23 = ram_internal[23];

wire [159:0] row24;
assign row24 = ram_internal[24];

wire [159:0] row25;
assign row25 = ram_internal[25];

wire [159:0] row26;
assign row26 = ram_internal[26];

wire [159:0] row27;
assign row27 = ram_internal[27];

wire [159:0] row28;
assign row28 = ram_internal[28];

wire [159:0] row29;
assign row29 = ram_internal[29];

wire [159:0] row30;
assign row30 = ram_internal[30];

wire [159:0] row31;
assign row31 = ram_internal[31];

wire [159:0] row32;
assign row32 = ram_internal[32];

wire [159:0] row33;
assign row33 = ram_internal[33];

wire [159:0] row34;
assign row34 = ram_internal[34];

wire [159:0] row35;
assign row35 = ram_internal[35];

wire [159:0] row36;
assign row36 = ram_internal[36];

wire [159:0] row37;
assign row37 = ram_internal[37];

wire [159:0] row38;
assign row38 = ram_internal[38];

wire [159:0] row39;
assign row39 = ram_internal[39];

wire [159:0] row40;
assign row40 = ram_internal[40];

wire [159:0] row41;
assign row41 = ram_internal[41];

wire [159:0] row42;
assign row42 = ram_internal[42];

wire [159:0] row43;
assign row43 = ram_internal[43];

wire [159:0] row44;
assign row44 = ram_internal[44];

wire [159:0] row45;
assign row45 = ram_internal[45];

wire [159:0] row46;
assign row46 = ram_internal[46];

wire [159:0] row47;
assign row47 = ram_internal[47];

wire [159:0] row48;
assign row48 = ram_internal[48];

wire [159:0] row49;
assign row49 = ram_internal[49];

wire [159:0] row50;
assign row50 = ram_internal[50];

wire [159:0] row51;
assign row51 = ram_internal[51];

wire [159:0] row52;
assign row52 = ram_internal[52];

wire [159:0] row53;
assign row53 = ram_internal[53];

wire [159:0] row54;
assign row54 = ram_internal[54];

wire [159:0] row55;
assign row55 = ram_internal[55];

wire [159:0] row56;
assign row56 = ram_internal[56];

wire [159:0] row57;
assign row57 = ram_internal[57];

wire [159:0] row58;
assign row58 = ram_internal[58];

wire [159:0] row59;
assign row59 = ram_internal[59];

wire [159:0] row60;
assign row60 = ram_internal[60];

wire [159:0] row61;
assign row61 = ram_internal[61];

wire [159:0] row62;
assign row62 = ram_internal[62];

wire [159:0] row63;
assign row63 = ram_internal[63];

wire [159:0] row64;
assign row64 = ram_internal[64];

wire [159:0] row65;
assign row65 = ram_internal[65];

wire [159:0] row66;
assign row66 = ram_internal[66];

wire [159:0] row67;
assign row67 = ram_internal[67];

wire [159:0] row68;
assign row68 = ram_internal[68];

wire [159:0] row69;
assign row69 = ram_internal[69];

wire [159:0] row70;
assign row70 = ram_internal[70];

wire [159:0] row71;
assign row71 = ram_internal[71];

wire [159:0] row72;
assign row72 = ram_internal[72];

wire [159:0] row73;
assign row73 = ram_internal[73];

wire [159:0] row74;
assign row74 = ram_internal[74];

wire [159:0] row75;
assign row75 = ram_internal[75];

wire [159:0] row76;
assign row76 = ram_internal[76];

wire [159:0] row77;
assign row77 = ram_internal[77];

wire [159:0] row78;
assign row78 = ram_internal[78];

wire [159:0] row79;
assign row79 = ram_internal[79];

wire [159:0] row80;
assign row80 = ram_internal[80];

wire [159:0] row81;
assign row81 = ram_internal[81];

wire [159:0] row82;
assign row82 = ram_internal[82];

wire [159:0] row83;
assign row83 = ram_internal[83];

wire [159:0] row84;
assign row84 = ram_internal[84];

wire [159:0] row85;
assign row85 = ram_internal[85];

wire [159:0] row86;
assign row86 = ram_internal[86];

wire [159:0] row87;
assign row87 = ram_internal[87];

wire [159:0] row88;
assign row88 = ram_internal[88];

wire [159:0] row89;
assign row89 = ram_internal[89];

wire [159:0] row90;
assign row90 = ram_internal[90];

wire [159:0] row91;
assign row91 = ram_internal[91];

wire [159:0] row92;
assign row92 = ram_internal[92];

wire [159:0] row93;
assign row93 = ram_internal[93];

wire [159:0] row94;
assign row94 = ram_internal[94];

wire [159:0] row95;
assign row95 = ram_internal[95];

wire [159:0] row96;
assign row96 = ram_internal[96];

wire [159:0] row97;
assign row97 = ram_internal[97];

wire [159:0] row98;
assign row98 = ram_internal[98];

wire [159:0] row99;
assign row99 = ram_internal[99];

wire [159:0] row100;
assign row100 = ram_internal[100];

wire [159:0] row101;
assign row101 = ram_internal[101];

wire [159:0] row102;
assign row102 = ram_internal[102];

wire [159:0] row103;
assign row103 = ram_internal[103];

wire [159:0] row104;
assign row104 = ram_internal[104];

wire [159:0] row105;
assign row105 = ram_internal[105];

wire [159:0] row106;
assign row106 = ram_internal[106];

wire [159:0] row107;
assign row107 = ram_internal[107];

wire [159:0] row108;
assign row108 = ram_internal[108];

wire [159:0] row109;
assign row109 = ram_internal[109];

wire [159:0] row110;
assign row110 = ram_internal[110];

wire [159:0] row111;
assign row111 = ram_internal[111];

wire [159:0] row112;
assign row112 = ram_internal[112];

wire [159:0] row113;
assign row113 = ram_internal[113];

wire [159:0] row114;
assign row114 = ram_internal[114];

wire [159:0] row115;
assign row115 = ram_internal[115];

wire [159:0] row116;
assign row116 = ram_internal[116];

wire [159:0] row117;
assign row117 = ram_internal[117];

wire [159:0] row118;
assign row118 = ram_internal[118];

wire [159:0] row119;
assign row119 = ram_internal[119];

wire [159:0] row120;
assign row120 = ram_internal[120];

wire [159:0] row121;
assign row121 = ram_internal[121];

wire [159:0] row122;
assign row122 = ram_internal[122];

wire [159:0] row123;
assign row123 = ram_internal[123];

wire [159:0] row124;
assign row124 = ram_internal[124];

wire [159:0] row125;
assign row125 = ram_internal[125];

wire [159:0] row126;
assign row126 = ram_internal[126];

wire [159:0] row127;
assign row127 = ram_internal[127];

wire [7:0] a0;
assign a0 = {ram_internal[3][0],ram_internal[4][0],ram_internal[5][0],ram_internal[6][0],ram_internal[7][0],ram_internal[8][0],ram_internal[9][0],ram_internal[10][0]};
wire [7:0] b0;
assign b0 = {ram_internal[11][0],ram_internal[12][0],ram_internal[13][0],ram_internal[14][0],ram_internal[15][0],ram_internal[16][0],ram_internal[17][0],ram_internal[17][0]};

endmodule

