//Flop based RF
module rf(
    clk,
    resetn,
    addr,
    wren,
    data,
    rf0,
    rf1,
    rf2,
    rf3
);

input clk;
input resetn;
input [`RF_ADDR_WIDTH-1:0] addr;
input  wren;
input [`RF_DATA_WIDTH-1:0] data;
output reg [`RF_DATA_WIDTH-1:0] rf0;
output reg [`RF_DATA_WIDTH-1:0] rf1;
output reg [`RF_DATA_WIDTH-1:0] rf2;
output reg [`RF_DATA_WIDTH-1:0] rf3;

always @ (posedge clk) begin 
  if (~resetn) begin
    rf0 <= 0;
    rf1 <= 0;  
    rf2 <= 0;  
    rf3 <= 0;  
  end
  else if (wren) begin
    case(addr)
    0: begin rf0 <= data; end
    1: begin rf1 <= data; end
    2: begin rf2 <= data; end
    3: begin rf3 <= data; end
    default: begin rf0 <= data; end
    endcase
  end
end
  
endmodule

