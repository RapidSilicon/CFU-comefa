`define SIMULATION_MEMORY

`define DRAM_DWIDTH 40
`define DRAM_NUM_WORDS 512

`ifdef SIMULATION

`define DWIDTH    40
`define LOGDWIDTH 6
`define AWIDTH    9

`define NUM_COLS 160
`define NUM_ROWS 128

//Data written to this address is treated as an instruction
`define CMD_ADDR   9'b111111111

`else

`define DWIDTH    40
`define LOGDWIDTH 6
`define AWIDTH    9

`define NUM_COLS 160
`define NUM_ROWS 128 

//Data written to this address is treated as an instruction
`define CMD_ADDR   9'b111111111


`endif


`define ADDR_WIDTH 9
`define NUM_LOCATIONS 512
`define DATA_WIDTH 40
//The following is intentionally defined to be 32.
//That's because we can fit all the bits we need in 32 bits.
//This allows us to write 1 macro instruction into the instruction RAM
//every cycle. If we use 40 bits, then we'd need to write one
//instruction in 2 cycles.
`define STORED_INST_DATA_WIDTH 32

`define OPCODE_WIDTH        4
`define PRECISION_WIDTH     4
`define ROW_ADDR_WIDTH      7
`define RF_ADDR_WIDTH       4
`define LEVELS_WIDTH        3
`define LOGICAL_OP_WIDTH    3

//Assuming max 8-bit precision for now
`define RF_MAX_PRECISION 8

//Opcodes
`define RESET           4'b0000
`define ADD             4'b0001
`define SHIFT           4'b0010
`define MUL             4'b0011
`define ADD_CONST       4'b0100
`define MUL_CONST       4'b0101
`define REDUCE          4'b0110
`define DOTPROD1        4'b0111
`define DOTPROD2        4'b1000
`define DOTPROD_CONST1  4'b1001
`define DOTPROD_CONST2  4'b1010
`define LOGICAL         4'b1011
`define LOGICAL_CONST   4'b1100

