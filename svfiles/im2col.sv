// Custom Tensor Processing Unit (TPU) for 1D CNN Inference
// Copyright (C) 2026 Atul Kumar
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published
// by the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.
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
