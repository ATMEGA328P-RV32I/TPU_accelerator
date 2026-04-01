// Copyright 2026 Atul Kumar
// Module: mac_node
// Description: The fundamental Processing Element (Multiply-Accumulate)
// Note: I have made this a weight-stationary architecture.
module mac_node #( parameter int D_WIDTH=16)(
    input logic clk,
    input logic rst_n,
    input logic en,
    // Static Weight for this specific node
    input  logic signed [D_WIDTH-1:0] weight,
    // Inputs from Top and Left neighbors
    input logic signed [D_WIDTH-1:0] act_in,
    input logic signed [(2*D_WIDTH)-1:0] psum_in,
    // Outputs to Bottom and Right neighbors
    output logic signed [D_WIDTH-1:0] act_out,
    output logic signed [(2*D_WIDTH)-1:0] psum_out
);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            act_out <='0;
            psum_out <='0;
        end else if (en) begin
            // 1. Pass the activation to the right neighbor
            act_out <= act_in; 
            // 2. Multiply, Accumulate, and pass down to the bottom neighbor
            psum_out <= psum_in+(act_in*weight); 
        end
    end
endmodule