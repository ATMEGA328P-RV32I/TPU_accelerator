// Copyright 2026 Atul Kumar
module tpu_conv1d_engine #(parameter int ARRAY_SIZE=5,parameter int D_WIDTH=16)(
    input logic clk,rst_n,start, // start acts as the trigger to wake up this engine
    output logic engine_done,// engine_done is flagged when convolution gets finished
    input logic [39:0] src_addr,dest_addr, // tells exactly where to read data(src_addr),where to write the answers(dest_addr)
    input logic [7:0] config_ptr, // where to find the weights(config_ptr)
    input logic [15:0] seq_length, // how many samples to process(seq_length)
    
    // This is the UAB(unified activation buffer) interface. I have dedicated read and write enables, and separate 40 bit address buses. The data bus reads/writes 4 32-bit blocks at a time to keep up with the MACs
    output logic uab_re,
    output logic [39:0] uab_raddr,
    input logic signed [31:0] uab_rdata[0:3],
    output logic uab_we,
    output logic [39:0] uab_waddr,
    output logic signed [31:0] uab_wdata[0:3],
    
    // This is the WRAM(weight RAM) interface. It only needs a read channel because the weights are statically loaded from the host before the network runs.
    output logic wram_re,
    output logic [39:0] wram_raddr,
    input logic signed [D_WIDTH-1:0] wram_rdata
);
    typedef enum logic [1:0] {IDLE,LOAD_W,STREAM,DONE} state_t; // 4 state FSM. Idle waits for a trigger. Load_w fetches the weights into the systolic grid. Stream pumps the ECG data through the math core. Done signals the top-level FSM
    state_t state,next_state;
    
    logic [4:0] weight_count; 
    logic [15:0] read_count,write_count; // read_count and write_count track how much data has been processed
    logic [6:0] valid_sr; // 7 bit shift register used purely to track pipeline latency. It tells exactly when valid data is finally emerging from the systolic array.
    logic signed [D_WIDTH-1:0] weight_grid[0:ARRAY_SIZE-1][0:ARRAY_SIZE-1]; // this holds the 25 weights fore the 5x5 MAC array
    logic signed [31:0] conv_bias[0:3]; // holds the 4 biases added to the end of the convolution
    logic signed [D_WIDTH-1:0] window_acts[0:ARRAY_SIZE-1]; 
    logic signed [(2*D_WIDTH)-1:0] psum_out_wires[0:ARRAY_SIZE-1];
    
    // instantiating the data formatter
    im2col#(.D_WIDTH(D_WIDTH)) im2col_inst(
        .clk(clk),.rst_n(rst_n),.en(state==STREAM),
        .stream_in(uab_rdata[0][15:0]), 
        .window_out(window_acts)
    );

    // 5x5 systolic matrix; recieves the sliding window from in2col, locks the stationary weight_grid and outputs 32 bit partial sums
    systolic_core#(.ARRAY_SIZE(ARRAY_SIZE),.D_WIDTH(D_WIDTH)) core_inst(
        .clk(clk),.rst_n(rst_n),.en(state==STREAM),
        .act_in(window_acts),.weight_in(weight_grid),
        .psum_out(psum_out_wires)
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=IDLE; weight_count<='0; read_count<='0; write_count<='0; valid_sr<='0;
            uab_raddr<='0; uab_waddr<='0; wram_raddr<='0;
        end else begin
            state<=next_state;
            case(state)
                IDLE: if(start) begin // all the base addresses are initialized. WRAM address pointer jumps to config_ptr where the weights are stored and UAB read/write pointers are locked.
                    weight_count<='0; read_count<='0; write_count<='0; valid_sr<='0;
                    wram_raddr<={32'd0,config_ptr}; 
                    uab_raddr<=src_addr; 
                    uab_waddr<=dest_addr;
                end
                LOAD_W: begin // 1D data is loaded onto 2D grid using modulo 5 and division 5 math
                    if(weight_count>0&&weight_count<=25) 
                        weight_grid[(weight_count-1)%5][(weight_count-1)/5]<=wram_rdata;
                    else if(weight_count>25&&weight_count<=29) // the 4 numbers after that are biases
                        conv_bias[weight_count-26]<={{16{wram_rdata[15]}},wram_rdata};
                    
                    wram_raddr<=wram_raddr+1; 
                    weight_count<=weight_count+1;
                end
                STREAM: begin
                    valid_sr<={valid_sr[5:0],(read_count<seq_length)}; // every clock cycle, push a 1 into the valid_sr shift register. Because im2col takes 5 cycles to fill, and the systolic core takes time to pass values down, valid_sr acts as a perfect hardware timer. When the 1 reaches valid_sr[6], valid math is finally exiting the pipeline
                    if(read_count<seq_length) begin // just increment UAB read pointer and read_count till max length of ECG samples
                        uab_raddr<=uab_raddr+1; 
                        read_count<=read_count+1; 
                    end
                    if(valid_sr[6]&&write_count<(seq_length-4)) begin // start writing back to memory iff valid_sr[6] is 1 (ie the pipeline is primed and valid). Because a kernel size of 5 shrinks the array by 4, stop writing at seq_length-4
                        uab_waddr<=uab_waddr+1; 
                        write_count<=write_count+1; 
                    end
                end
            endcase
        end
    end

    always_comb begin // standard FSM combinational logic to calculate next state
        next_state=state;
        case(state)
            IDLE: if(start) next_state=LOAD_W;
            LOAD_W: if(weight_count==30) next_state=STREAM; 
            STREAM: if(valid_sr==7'b0&&read_count==seq_length) next_state=DONE; 
            DONE: next_state=IDLE;
        endcase
    end

    assign engine_done=(state==DONE);
    assign wram_re=(state==LOAD_W&&weight_count<29);
    assign uab_re=(state==STREAM&&read_count<seq_length);
    assign uab_we=(state==STREAM)&&valid_sr[6]&&(write_count<(seq_length-4)); 
    
    // A Q8.8 number multiplied by another Q8.8 number results in a Q16.16 format. 
    // To store it back in UAB as a standard Q8.8, do an arithmetic right shift (>>>8) to truncate the extra decimal bits, then add the bias.
    // This was one of the major bugs   
    assign uab_wdata[0]=(psum_out_wires[0]>>>8)+conv_bias[0]; 
    assign uab_wdata[1]=(psum_out_wires[1]>>>8)+conv_bias[1];
    assign uab_wdata[2]=(psum_out_wires[2]>>>8)+conv_bias[2]; 
    assign uab_wdata[3]=(psum_out_wires[3]>>>8)+conv_bias[3];
endmodule