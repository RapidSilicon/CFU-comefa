module controller (
    input clk,
    input rstn,
    input start,
    output reg done,
    output reg [`ADDR_WIDTH-1:0] stored_instr_addr,
    input [`ADDR_WIDTH-1:0] stored_instr_start_addr,
    input [`ADDR_WIDTH-1:0] stored_instr_end_addr,
    input [`STORED_INST_DATA_WIDTH-1:0] stored_instruction,
    output [`ADDR_WIDTH-1:0] exec_instr_addr,
    output [`DATA_WIDTH-1:0] exec_instruction,
    input [`RF_MAX_PRECISION-1:0] rf0,
    input [`RF_MAX_PRECISION-1:0] rf1,
    input [`RF_MAX_PRECISION-1:0] rf2,
    input [`RF_MAX_PRECISION-1:0] rf3,
    output execute
);

reg cur_instr_done;
reg one_cycle_left;
reg done_0;
reg execute_0;

//Decode the fetched instruction
reg [`OPCODE_WIDTH-1:0] opcode;

reg [`PRECISION_WIDTH-1:0] precision;
reg [`ROW_ADDR_WIDTH-1:0] src1_row;
reg [`ROW_ADDR_WIDTH-1:0] src2_row;
reg [`ROW_ADDR_WIDTH-1:0] src3_row;
reg [`ROW_ADDR_WIDTH-1:0] src4_row;
reg [`ROW_ADDR_WIDTH-1:0] dst_row;
reg [`RF_ADDR_WIDTH-1:0] src1_rf;
reg [`RF_ADDR_WIDTH-1:0] src2_rf;
reg [`LEVELS_WIDTH-1:0] levels;
reg [`LOGICAL_OP_WIDTH-1:0] logical_op;

reg first_time;

//Fetch the stored instruction
always @(posedge clk) begin
    if (~rstn || ~start) begin
        stored_instr_addr <= stored_instr_start_addr;
        done_0 <= 0;
        first_time <= 1;
    end
    else begin
        //If the current instruction is done, then we fetch the next
        //stored instruction
        if ((stored_instr_addr == (stored_instr_end_addr+1)) && one_cycle_left) begin
            done_0 <= 1;
        end
        else if (start && (first_time || one_cycle_left)) begin
            first_time <= 0;
            stored_instr_addr <= stored_instr_addr + 1;
            //$display("%m %t: Fetched new instruction", $time);
            done_0 <= 0;
            opcode <= stored_instruction[`STORED_INST_DATA_WIDTH-1:`STORED_INST_DATA_WIDTH-`OPCODE_WIDTH];
            case(stored_instruction[`STORED_INST_DATA_WIDTH-1:`STORED_INST_DATA_WIDTH-`OPCODE_WIDTH])
             `RESET, 
             `ADD,
             `SHIFT,
             `MUL:
             begin
                 precision <= stored_instruction[`PRECISION_WIDTH-1:0];
                 src1_row <= stored_instruction[`ROW_ADDR_WIDTH+`PRECISION_WIDTH-1:`PRECISION_WIDTH];
                 src2_row <= stored_instruction[2*`ROW_ADDR_WIDTH+`PRECISION_WIDTH-1:`ROW_ADDR_WIDTH+`PRECISION_WIDTH];
                 dst_row <= stored_instruction[3*`ROW_ADDR_WIDTH+`PRECISION_WIDTH-1:2*`ROW_ADDR_WIDTH+`PRECISION_WIDTH];
             end
             `ADD_CONST,
             `MUL_CONST:
             begin
                 precision <= stored_instruction[`PRECISION_WIDTH-1:0];
                 src1_row <= stored_instruction[`ROW_ADDR_WIDTH+`PRECISION_WIDTH-1:`PRECISION_WIDTH];
                 src2_rf <= stored_instruction[`RF_ADDR_WIDTH+`ROW_ADDR_WIDTH+`PRECISION_WIDTH-1:`ROW_ADDR_WIDTH+`PRECISION_WIDTH];
                 dst_row <= stored_instruction[3*`ROW_ADDR_WIDTH+`PRECISION_WIDTH-1:2*`ROW_ADDR_WIDTH+`PRECISION_WIDTH];
             end
             `REDUCE:
             begin
                 precision <= stored_instruction[`PRECISION_WIDTH-1:0];
                 src1_row <= stored_instruction[`ROW_ADDR_WIDTH+`PRECISION_WIDTH-1:`PRECISION_WIDTH];
                 src2_row <= stored_instruction[2*`ROW_ADDR_WIDTH+`PRECISION_WIDTH-1:`ROW_ADDR_WIDTH+`PRECISION_WIDTH];
                 dst_row <= stored_instruction[3*`ROW_ADDR_WIDTH+`PRECISION_WIDTH-1:2*`ROW_ADDR_WIDTH+`PRECISION_WIDTH];
                 levels <= stored_instruction[`LEVELS_WIDTH+3*`ROW_ADDR_WIDTH+`PRECISION_WIDTH-1:3*`ROW_ADDR_WIDTH+`PRECISION_WIDTH];
             end
             `DOTPROD1:
             begin
                 precision <= stored_instruction[`PRECISION_WIDTH-1:0];
                 src1_row <= stored_instruction[`ROW_ADDR_WIDTH+`PRECISION_WIDTH-1:`PRECISION_WIDTH];
                 src2_row <= stored_instruction[2*`ROW_ADDR_WIDTH+`PRECISION_WIDTH-1:`ROW_ADDR_WIDTH+`PRECISION_WIDTH];
             end
             `DOTPROD2:
             begin
                 src3_row <= stored_instruction[`ROW_ADDR_WIDTH-1:0];
                 src4_row <= stored_instruction[2*`ROW_ADDR_WIDTH-1:`ROW_ADDR_WIDTH];
                 dst_row <= stored_instruction[3*`ROW_ADDR_WIDTH-1:2*`ROW_ADDR_WIDTH];
             end
             `DOTPROD_CONST1:
             begin
                 precision <= stored_instruction[`PRECISION_WIDTH-1:0];
                 src1_rf <= stored_instruction[`RF_ADDR_WIDTH+`PRECISION_WIDTH-1:`PRECISION_WIDTH];
                 src2_rf <= stored_instruction[2*`RF_ADDR_WIDTH+`PRECISION_WIDTH-1:`RF_ADDR_WIDTH+`PRECISION_WIDTH];
             end
             `DOTPROD_CONST2:
             begin
                 src1_row <= stored_instruction[`ROW_ADDR_WIDTH-1:0];
                 src2_row <= stored_instruction[2*`ROW_ADDR_WIDTH-1:`ROW_ADDR_WIDTH];
                 dst_row <= stored_instruction[3*`ROW_ADDR_WIDTH-1:2*`ROW_ADDR_WIDTH];
             end
             `LOGICAL:
             begin
                 precision <= stored_instruction[`PRECISION_WIDTH-1:0];
                 src1_row <= stored_instruction[`ROW_ADDR_WIDTH+`PRECISION_WIDTH-1:`PRECISION_WIDTH];
                 src2_row <= stored_instruction[2*`ROW_ADDR_WIDTH+`PRECISION_WIDTH-1:`ROW_ADDR_WIDTH+`PRECISION_WIDTH];
                 dst_row <= stored_instruction[3*`ROW_ADDR_WIDTH+`PRECISION_WIDTH-1:2*`ROW_ADDR_WIDTH+`PRECISION_WIDTH];
                 logical_op <= stored_instruction[`LOGICAL_OP_WIDTH+3*`ROW_ADDR_WIDTH+`PRECISION_WIDTH-1:3*`ROW_ADDR_WIDTH+`PRECISION_WIDTH];
             end
             `LOGICAL_CONST:
             begin
                 precision <= stored_instruction[`PRECISION_WIDTH-1:0];
                 src1_row <= stored_instruction[`ROW_ADDR_WIDTH+`PRECISION_WIDTH-1:`PRECISION_WIDTH];
                 src2_rf <= stored_instruction[`RF_ADDR_WIDTH+`ROW_ADDR_WIDTH+`PRECISION_WIDTH-1:`ROW_ADDR_WIDTH+`PRECISION_WIDTH];
                 dst_row <= stored_instruction[3*`ROW_ADDR_WIDTH+`PRECISION_WIDTH-1:2*`ROW_ADDR_WIDTH+`PRECISION_WIDTH];
                 logical_op <= stored_instruction[`LOGICAL_OP_WIDTH+3*`ROW_ADDR_WIDTH+`PRECISION_WIDTH-1:3*`ROW_ADDR_WIDTH+`PRECISION_WIDTH];
             end
             default:
                 if (rstn && start) begin
                     //$display("%m %t: Unsupported opcode in instruction %h", $time, stored_instruction);
                 end
            endcase 
        end
    end
end

assign execute = execute_0 && ~done;

always @(posedge clk) begin
    done <= done_0;
end


reg [`RF_MAX_PRECISION-1:0] rf_val;
reg [`RF_MAX_PRECISION-1:0] rf_val_reg;

//Select the RF value to use.
//This code assumes 4 bit RF address for now.
//And only 4 registers area assumed.
always @(*) begin
    case(src2_rf) 
        4'b0000: rf_val = rf0;
        4'b0001: rf_val = rf1;
        4'b0010: rf_val = rf2;
        4'b0011: rf_val = rf3;
        default: rf_val = rf0;
    endcase
end

reg [1:0] predicate;
reg [4:0] dummy;
reg write_en;
reg [1:0] write_sel;
reg port;
reg c_rst;
reg c_en;
reg m_rst;
reg m_en;
reg [3:0] truth_table;
reg [6:0] dst;
reg [6:0] src2;
reg [6:0] src1;

reg [3:0] state;

assign exec_instr_addr = `CMD_ADDR;
assign exec_instruction = {predicate, dummy, write_en, write_sel, port, c_rst, c_en, m_rst, m_en, truth_table, dst, src2, src1};

integer counter;
integer i, j;

//Execute the decoded instruction
always @(posedge clk) begin
    if (~rstn || ~start) begin
        execute_0 <= 1'b0;
        predicate <= 2'b00;
        dummy <= 5'b00000;
        write_en <= 1'b0;
        write_sel <= 2'b00;
        port <= 1'b0; 
        c_rst <= 1'b0;
        c_en <= 1'b0;  
        m_rst <= 1'b0; 
        m_en <= 1'b0;  
        truth_table <= 4'b0000;
        src1 <= 7'b0;
        src2 <= 7'b0;
        dst <= 7'b0;
        cur_instr_done <= 1'b0;
        counter <= 0;
        i <= 0;
        j <= 0;
        state <= 0;
        one_cycle_left <= 1'b0;
    end
    else begin
        case(opcode)
        `ADD,
        `ADD_CONST:
        begin
            case(state)
            4'b0000: begin
                counter <= precision;
                execute_0 <= 1'b1;
                cur_instr_done <= 1'b0;
                state <= 4'b0001;
                predicate <= 2'b11; //enable writing
                dummy <= 5'b00000;
                write_en <= 1'b1;
                write_sel <= 2'b01; //write_sel1 mux selects sum
                port <= 1'b0; //port 1 enabled for write
                c_rst <= 1'b0; //reset c latch
                c_en <= 1'b1;  //do not store carry in c latch
                m_rst <= 1'b0; //do not reset m latch
                m_en <= 1'b0;  //no masking required
                if (opcode==`ADD) begin
                    truth_table <= 4'b0110; //xor
                end
                else begin //opcode is ADD_CONST
                    //to perform an xor internally, we need to send
                    //b,b,b',b' into the truth table.
                    //truth_table <= {~rf_val[0], rf_val[0], rf_val[0], ~rf_val[0]};
                    //truth_table <= {rf_val[0], ~rf_val[0], rf_val[0], ~rf_val[0]};
                    if (rf_val[0]==1'b1) begin
                        truth_table <= 4'b0101;
                    end
                    else begin
                        truth_table <= 4'b1010;
                    end
                    //Shift rf_val by 1
                    rf_val_reg <= rf_val >> 1;
                end
                src1 <= src1_row;
                src2 <= src2_row;
                dst <= dst_row;
                one_cycle_left <= 1'b0;
            end
            4'b0001: begin
                counter <= counter - 1;
                execute_0 <= 1'b1;
                cur_instr_done <= 1'b0;
                if (counter==2) begin
                    state <= 4'b0010;
                    one_cycle_left <= 1'b1;
                end
                else begin
                    state <= 4'b0001;
                    one_cycle_left <= 1'b0;
                end
                predicate <= 2'b11; //enable writing
                dummy <= 5'b00000;
                write_en <= 1'b1;
                write_sel <= 2'b01; //write_sel1 mux selects sum
                port <= 1'b0; //port 1 enabled for write
                c_rst <= 1'b0; //reset c latch
                c_en <= 1'b1;  //do not store carry in c latch
                m_rst <= 1'b0; //do not reset m latch
                m_en <= 1'b0;  //no masking required
                if (opcode==`ADD) begin
                    truth_table <= 4'b0110; //xor
                end
                else begin //opcode is ADD_CONST
                    //to perform an xor internally, we need to send
                    //b,b,b',b' into the truth table.
                    //truth_table <= {~rf_val_reg[0], rf_val_reg[0], rf_val_reg[0], ~rf_val_reg[0]};
                    //truth_table <= {rf_val_reg[0], ~rf_val_reg[0], rf_val_reg[0], ~rf_val_reg[0]};
                    if (rf_val_reg[0]==1'b1) begin
                        truth_table <= 4'b0101;
                    end
                    else begin
                        truth_table <= 4'b1010;
                    end
                    //Shift rf_val by 1
                    rf_val_reg <= rf_val_reg >> 1;
                end
                src1 <= src1+1;
                src2 <= src2+1;
                dst <= dst+1;
            end
            // in the last cycle of add, we need to write the carry into the array
            4'b0010: begin
                counter <= counter - 1;
                execute_0 <= 1'b1;
                cur_instr_done <= 1'b1;
                state <= 4'b0000;
                predicate <= 2'b11; //enable writing
                dummy <= 5'b00000;
                write_en <= 1'b1;
                write_sel <= 2'b01; //write_sel2 mux selects carry
                port <= 1'b1; //port 2 enabled for write
                c_rst <= 1'b1; //reset c latch after this cycle
                c_en <= 1'b0;  //no need to store new carry
                m_rst <= 1'b0; //do not reset m latch
                m_en <= 1'b0;  //no masking required
                truth_table <= 4'b0110; //xor //this is don't care though
                src1 <= src1+1;
                src2 <= src2+1;
                dst <= dst+1;
                one_cycle_left <= 1'b0;
            end
            default: begin
                //$display("Unsupported");
            end
            endcase
 
        end

        `MUL:
        begin
            case(state)
            //step0: Init extra rows to 0
            4'b0000: begin
                i <= i + 1;
                execute_0 <= 1'b1;
                cur_instr_done <= 1'b0;
                if (i==(precision-1)) begin
                    state <= 4'b0001;
                    i <= 0;
                end
                predicate <= 2'b11; //enable writing
                dummy <= 5'b00000;
                write_en <= 1'b1;
                write_sel <= 2'b01; //write_sel1 mux selects sum
                port <= 1'b0; //port 1 enabled for write
                c_rst <= 1'b0; //reset c latch
                c_en <= 1'b0;  //do not store carry in c latch
                m_rst <= 1'b0; //do not reset m latch
                m_en <= 1'b0;  //no masking required
                truth_table <= 4'b0000; //set to 0
                src1 <= src1_row; //don't care
                src2 <= src2_row; //don't care
                dst <= dst_row + precision + i;
                one_cycle_left <= 1'b0;
            end
            //step 1: read src1 lsb into mask
            4'b0001: begin
                execute_0 <= 1'b1;
                cur_instr_done <= 1'b0;
                state <= 4'b0010;
                predicate <= 2'b11; //don't care
                dummy <= 5'b00000;
                write_en <= 1'b0;
                write_sel <= 2'b01; //don't care
                port <= 1'b0; //don't care
                c_rst <= 1'b0; //no reset
                c_en <= 1'b0;  //do not store carry in c latch
                m_rst <= 1'b0; //do not reset m latch
                m_en <= 1'b1;  //store value read to mask
                truth_table <= 4'b1010; //cause src1 to become the output
                src1 <= src1_row;
                src2 <= src2_row; //don't care
                dst <= dst_row; //don't care
                one_cycle_left <= 1'b0;
            end
            //step 2: copy src2 if masks are 1
            4'b0010: begin
                i <= i + 1;
                execute_0 <= 1'b1;
                cur_instr_done <= 1'b0;
                if (i==(precision-1)) begin
                    state <= 4'b0011;
                    i <= 0;
                    j <= 1;
                end
                predicate <= 2'b00; //masks
                dummy <= 5'b00000;
                write_en <= 1'b1;
                write_sel <= 2'b01; //write_sel1 mux selects sum
                port <= 1'b0; //port 1 enabled for write
                c_rst <= 1'b0; //reset c latch
                c_en <= 1'b0;  //do not store carry in c latch
                m_rst <= 1'b0; //do not reset m latch
                m_en <= 1'b0;  //do not update masks
                truth_table <= 4'b1100; //src2 becomes the output
                src1 <= src1_row; //do not care
                src2 <= src2_row + i;
                dst <= dst_row + i;
                one_cycle_left <= 1'b0;
            end
            //step 3: read src1 next bit into masks
            4'b0011: begin
                execute_0 <= 1'b1;
                cur_instr_done <= 1'b0;
                state <= 4'b0100;
                predicate <= 2'b11; //don't care
                dummy <= 5'b00000;
                write_en <= 1'b0; //do not write
                write_sel <= 2'b01; //don't care
                port <= 1'b0; //don't care
                c_rst <= 1'b0; //no reset carry
                c_en <= 1'b0;  //do not store carry in c latch
                m_rst <= 1'b0; //do not reset m latch
                m_en <= 1'b1;  //save value read to masks
                truth_table <= 4'b1010; //src1 becomes the output
                src1 <= src1_row + j; //
                src2 <= src2_row; //don't care
                dst <= dst_row; //don't care
                one_cycle_left <= 1'b0;
                i <= 0;
            end
            //step 4: add src2 if masks are 1
            4'b0100: begin
                i <= i + 1;
                execute_0 <= 1'b1;
                cur_instr_done <= 1'b0;
                if (i==(precision-1)) begin
                    state <= 4'b0101;
                end
                predicate <= 2'b00; //masks
                dummy <= 5'b00000;
                write_en <= 1'b1;
                write_sel <= 2'b01; //write_sel1 mux selects sum
                port <= 1'b0; //port 1 enabled for write
                c_rst <= 1'b0; //reset c latch
                c_en <= 1'b1;  //store carry in c latch
                m_rst <= 1'b0; //do not reset m latch
                m_en <= 1'b0;  //do not update masks
                truth_table <= 4'b0110; //xor for sum
                src1 <= dst_row + j + i; //
                src2 <= src2_row + i;
                dst <= dst_row + j + i;
                if ((j==(precision-1)) && (i==(precision-1))) begin
                    one_cycle_left <= 1'b1;
                end else begin
                    one_cycle_left <= 1'b0;
                end
            end
            //step 5: carry
            4'b0101: begin
                execute_0 <= 1'b1;
                predicate <= 2'b00; //masks
                dummy <= 5'b00000;
                write_en <= 1'b1; //write
                write_sel <= 2'b01; //select carry
                port <= 1'b1; //port 2
                c_rst <= 1'b0; //no reset carry
                c_en <= 1'b1;  //store carry values
                m_rst <= 1'b0; //do not reset m latch
                m_en <= 1'b0;  //do not update masks
                truth_table <= 4'b0110; //don't care
                src1 <= src1_row; //do not care
                src2 <= src2_row; //don't care
                dst <= dst_row + i + j; //send carry to this row
                one_cycle_left <= 1'b0;
                j <= j+1;
                i <= 0;
                if (j==(precision-1)) begin
                    state <= 4'b0000;
                    cur_instr_done <= 1'b1;
                end
                else begin
                    state <= 4'b0011;
                    cur_instr_done <= 1'b0;
                end
            end
            default: begin
                //$display("Unsupported");
            end
            endcase
 
        end

        `MUL_CONST:
        begin
            case(state)
            //step0: Init extra rows to 0
            4'b0000: begin
                i <= i + 1;
                execute_0 <= 1'b1;
                cur_instr_done <= 1'b0;
                if (i==(precision-1)) begin
                    state <= 4'b0010;
                    i <= 0;
                end
                predicate <= 2'b11; //enable writing
                dummy <= 5'b00000;
                write_en <= 1'b1;
                write_sel <= 2'b01; //write_sel1 mux selects sum
                port <= 1'b0; //port 1 enabled for write
                c_rst <= 1'b0; //reset c latch
                c_en <= 1'b0;  //do not store carry in c latch
                m_rst <= 1'b0; //do not reset m latch
                m_en <= 1'b0;  //no masking required
                truth_table <= 4'b0000; //set to 0
                src1 <= src1_row; //don't care
                src2 <= src2_row; //don't care
                dst <= dst_row + precision + i;
                one_cycle_left <= 1'b0;
            end
            //step 2: copy src2 or 0 depending on src1
            4'b0010: begin
                i <= i + 1;
                execute_0 <= 1'b1;
                cur_instr_done <= 1'b0;
                if (i==(precision-1)) begin
                    state <= 4'b0100;
                    i <= 0;
                    j <= 1;
                end
                predicate <= 2'b11; //vdd
                dummy <= 5'b00000;
                write_en <= 1'b1;
                write_sel <= 2'b01; //write_sel1 mux selects sum
                port <= 1'b0; //port 1 enabled for write
                c_rst <= 1'b0; //reset c latch
                c_en <= 1'b0;  //do not store carry in c latch
                m_rst <= 1'b0; //do not reset m latch
                m_en <= 1'b0;  //do not update masks
                if (rf_val[0]==1'b1) begin
                    truth_table <= 4'b1100; //src2 becomes the output
                end else begin
                    truth_table <= 4'b0000; //0 becomes the output
                end
                src1 <= src1_row; //do not care
                src2 <= src2_row + i;
                dst <= dst_row + i;
                one_cycle_left <= 1'b0;
                rf_val_reg <= rf_val >> 1;
            end

            //step 4: add src2 depending on src1
            4'b0100: begin
                if (rf_val_reg[0]==1'b0) begin
                    execute_0 <= 1'b1;
                    cur_instr_done <= 1'b0;
                    predicate <= 2'b00; //don't care
                    dummy <= 5'b00000;
                    write_en <= 1'b0;
                    write_sel <= 2'b01; //write_sel1 mux selects sum
                    port <= 1'b0; //port 1 enabled for write
                    c_rst <= 1'b0; //reset c latch
                    c_en <= 1'b0;  //do not store carry in c latch
                    m_rst <= 1'b0; //do not reset m latch
                    m_en <= 1'b0;  //do not update masks
                    truth_table <= 4'b0110; //don't care
                    src1 <= 0; //don't care
                    src2 <= 0; //don't care
                    dst <= 0; //don't care

                    j <= j+1;
                    i <= 0;
                    if (j==(precision-1)) begin
                        state <= 4'b0110;
                        cur_instr_done <= 1'b0;
                        one_cycle_left <= 1'b1;
                    end
                    else begin
                        state <= 4'b0100;
                        cur_instr_done <= 1'b0;
                        one_cycle_left <= 1'b0;
                    end
                    rf_val_reg <= rf_val_reg >> 1;
                    
                end
                else begin
                    i <= i + 1;
                    execute_0 <= 1'b1;
                    cur_instr_done <= 1'b0;
                    if (i==(precision-1)) begin
                        state <= 4'b0101;
                        rf_val_reg <= rf_val_reg >> 1;
                    end
                    predicate <= 2'b11; //vdd
                    dummy <= 5'b00000;
                    write_en <= 1'b1;
                    write_sel <= 2'b01; //write_sel1 mux selects sum
                    port <= 1'b0; //port 1 enabled for write
                    c_rst <= 1'b0; //reset c latch
                    c_en <= 1'b1;  //store carry in c latch
                    m_rst <= 1'b0; //do not reset m latch
                    m_en <= 1'b0;  //do not update masks
                    truth_table <= 4'b0110; //xor for sum
                    src1 <= dst_row + j + i; //
                    src2 <= src2_row + i;
                    dst <= dst_row + j + i;
                    if ((j==(precision-1)) && (i==(precision-1))) begin
                        one_cycle_left <= 1'b1;
                    end else begin
                        one_cycle_left <= 1'b0;
                    end
                end
            end
            //step 5: carry
            4'b0101: begin
                execute_0 <= 1'b1;
                predicate <= 2'b11; //vdd
                dummy <= 5'b00000;
                write_en <= 1'b1; //write
                write_sel <= 2'b01; //select carry
                port <= 1'b1; //port 2
                c_rst <= 1'b0; //no reset carry
                c_en <= 1'b1;  //store carry values
                m_rst <= 1'b0; //do not reset m latch
                m_en <= 1'b0;  //do not update masks
                truth_table <= 4'b0110; //don't care
                src1 <= src1_row; //do not care
                src2 <= src2_row; //don't care
                dst <= dst_row + i + j; //send carry to this row
                one_cycle_left <= 1'b0;
                j <= j+1;
                i <= 0;
                if (j==(precision-1)) begin
                    state <= 4'b0000;
                    cur_instr_done <= 1'b1;
                end
                else begin
                    state <= 4'b0100;
                    cur_instr_done <= 1'b0;
                end
            end

            //dummy cycle
            4'b0110: begin
                state <= 4'b0000;
                cur_instr_done <= 1'b1;
                execute_0 <= 1'b1;
                write_en <= 1'b0; 
            end

            default: begin
                //$display("Unsupported");
            end
            endcase
 
        end

        default: begin
            //$display("Unsupported");
        end
        endcase
    end
end

endmodule
