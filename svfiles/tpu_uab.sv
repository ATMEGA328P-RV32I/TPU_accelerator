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
module tpu_uab(
    input logic clk,
    input logic we,
    input logic [39:0] waddr, // this is 40 bits as AXI4 standard uses 40 bit global address space
    input logic signed [31:0] wdata[0:3],
    input logic re,
    input logic [39:0] raddr,
    output logic signed [31:0] rdata[0:3]
);
    logic signed [31:0] sram[0:4095][0:3]; // 4096 rows, every single row holds 4 32 bit numbers

    always_ff @(posedge clk) begin
        if(we) begin // write data to address waddr
            sram[waddr[11:0]][0]<=wdata[0]; // 11 as to represent 4096 rows we need only 12 bits, so rest of bits in 40 bit waddr are discarded
            sram[waddr[11:0]][1]<=wdata[1];
            sram[waddr[11:0]][2]<=wdata[2];
            sram[waddr[11:0]][3]<=wdata[3];
        end
    end

    always_ff @(posedge clk) begin
        if(re) begin // read data from address raddr
            rdata[0]<=sram[raddr[11:0]][0];
            rdata[1]<=sram[raddr[11:0]][1];
            rdata[2]<=sram[raddr[11:0]][2];
            rdata[3]<=sram[raddr[11:0]][3];
        end
    end
endmodule
