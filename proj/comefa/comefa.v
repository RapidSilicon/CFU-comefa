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
//<PREDICATE> <DUMMY> <WRITE_EN> <WRITE_SEL> <PORT> <C_RST> <C_EN> <M_RST>  <M_EN>  <TRUTH_TABLE>  <dst_row> <src2_row> <src1_row>
//   2 bits   5 bits     1 bit    2 bits     1 bit  1 bit   1 bit  1 bit    1 bit     4 bits       7 bits     7 bits      7 bits

//Row addresses are 7 bits because the organization is 128x160
//In some cases like COPY or SHIFT, one of the
//src rows will be blank.

wire [1:0] predicate;
wire [4:0] dummy;
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
assign dummy       = d1[37:33];
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
        op2 = ram_internal[src2];

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
        ram[(dst<<2)+0] <= ram_internal_temp[dst][31:0];
        ram[(dst<<2)+1] <= ram_internal_temp[dst][63:32];
        ram[(dst<<2)+2] <= ram_internal_temp[dst][95:64];
        ram[(dst<<2)+3] <= ram_internal_temp[dst][127:96];
        ram[(dst<<2)+4] <= ram_internal_temp[dst][159:128];

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
        q2 <= ram[addr2];
    end  
end

endmodule

