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

module systolic_core #(parameter int ARRAY_SIZE = 2, parameter int D_WIDTH = 16)(
    input logic clk,
    input logic rst_n,
    input logic en,
    // Activations entering from the left edge of the grid
    input  logic signed [D_WIDTH-1:0] act_in [0:ARRAY_SIZE-1],
    // Static weights pre-loaded into the grid (Simplified for Hackathon)
    input  logic signed [D_WIDTH-1:0] weight_in [0:ARRAY_SIZE-1][0:ARRAY_SIZE-1],
    // Final Partial Sums exiting the bottom edge of the grid
    output logic signed [(2*D_WIDTH)-1:0] psum_out [0:ARRAY_SIZE-1]
);

    // act_wire[r][c] is the horizontal wire feeding into row r, column c
    logic signed [D_WIDTH-1:0] act_wire [0:ARRAY_SIZE][0:ARRAY_SIZE];
    // psum_wire[r][c] is the vertical wire feeding into row r, column c
    logic signed [(2*D_WIDTH)-1:0] psum_wire [0:ARRAY_SIZE][0:ARRAY_SIZE];
    genvar r, c;
    generate
        // Loop through every Row
        for (r=0; r<ARRAY_SIZE; r++) begin : row_gen
            // Connect the left-most input ports to the first column of the mesh
            assign act_wire[r][0]=act_in[r];
            // Loop through every Column
            for (c=0; c<ARRAY_SIZE; c++) begin : col_gen 
                // Ground the top-most partial sum inputs so the first row adds to 0
                if (r==0) begin
                    assign psum_wire[0][c] ='0;
                end
                // Instantiate the MAC Processing Element
                mac_node #(.D_WIDTH(D_WIDTH)) pe_inst (
                    .clk(clk),
                    .rst_n(rst_n),
                    .en(en),
                    .weight(weight_in[r][c]), // The AI weight for this specific node
                    .act_in(act_wire[r][c]), // Activation from the left neighbor
                    .psum_in(psum_wire[r][c]), // Partial sum from the top neighbor
                    .act_out(act_wire[r][c+1]), // Pass activation to the right neighbor
                    .psum_out(psum_wire[r+1][c]) // Pass partial sum to the bottom neighbor
                );
            end
        end
        // Connect the bottom-most outputs to the module's output ports
        for (c=0; c<ARRAY_SIZE; c++) begin : out_gen
            assign psum_out[c]=psum_wire[ARRAY_SIZE][c];
        end
    endgenerate
endmodule
