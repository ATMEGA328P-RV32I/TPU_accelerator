// Copyright 2026 Atul Kumar
module im2col_buffer#(parameter int D_WIDTH=16)(
    input logic clk,rst_n,en,
    input logic signed[D_WIDTH-1:0] stream_in,
    output logic signed[D_WIDTH-1:0] window_out[0:4]
);
    logic signed[D_WIDTH-1:0] shift_reg[0:4];
    always_ff @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            shift_reg[0]<='0;shift_reg[1]<='0;shift_reg[2]<='0;shift_reg[3]<='0;shift_reg[4]<='0;
        end else if(en)begin
            shift_reg[0]<=stream_in;
            shift_reg[1]<=shift_reg[0];
            shift_reg[2]<=shift_reg[1];
            shift_reg[3]<=shift_reg[2];
            shift_reg[4]<=shift_reg[3];
        end
    end
    assign window_out[0]=shift_reg[0];
    assign window_out[1]=shift_reg[1];
    assign window_out[2]=shift_reg[2];
    assign window_out[3]=shift_reg[3];
    assign window_out[4]=shift_reg[4];
endmodule