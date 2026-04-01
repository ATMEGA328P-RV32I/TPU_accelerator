// Copyright 2026 Atul Kumar
module tpu_pool_engine(
    input logic clk,rst_n,start, // start is the trigger to wake up the engine
    output logic engine_done, // flag raised to tell that pooling is done
    input logic [39:0] src_addr,dest_addr, // src_addr- tells where to start reading , dest_addr- where to write the new shrunken data
    input logic [15:0] seq_length, // length of data stream
    output logic uab_re, // read enable, tells UAB that data is needed
    output logic [39:0] uab_raddr, // address of data needed
    input logic signed [31:0] uab_rdata[0:3], // 4 32 bit no.s at a time (ie 128 bit VLIW)

    output logic uab_we, // signal to write data into UAB
    output logic [39:0] uab_waddr, // address where to write the data
    output logic signed [31:0] uab_wdata[0:3] // data to be written
);
    typedef enum logic [1:0] {IDLE,STREAM,DONE} state_t; // FSM states
    state_t state,next_state;

    logic [15:0] read_count,write_count; // keeps track of how many samplws fetched and how many samples written back
    
    // another major bug i have fixed. Toggle has been introduced to act as a traffic policeman.
    // per clock cycle, UAB can only give out 1 row of data but we need 2 rows to compare and pool
    // so, toggle is 0 when first data arrived and 1 when 2nd data also arrived 
    logic toggle; // only when toggle is 1 can the data be written to UAB. toggle alternates between 0 and 1 every clock cycle.
    
    logic signed [31:0] relu_val[0:3],hold_reg[0:3]; // relu_val holds the data after negative numbers are erased(ReLU can be visualized as deleting negative no.s) 
                                                     // hold_reg acts as temporary memory to store the 1st row while the engine waits for the 2nd row

    always_comb begin
        // unsigned bug fixed using 32'sd0 as we are comparing a no. that can be signed also, so we dont write 32'd0
        for(int i=0; i<4; i++) relu_val[i]=(uab_rdata[i]>32'sd0)?uab_rdata[i]:32'sd0; // The Hardware ReLU- it looks at the incoming ECG data. If the number is greater than signed zero, the mux passes the number. If it is -ve, the mux passes 0
        for(int i=0; i<4; i++) uab_wdata[i]=(relu_val[i]>hold_reg[i])?relu_val[i]:hold_reg[i];
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin // If the reset button is pressed, set every register to zero
            state<=IDLE; read_count<='0; write_count<='0; 
            uab_raddr<='0; uab_waddr<='0; toggle<='0;
            for(int i=0; i<4; i++) hold_reg[i]<='0;
        end else begin
            state<=next_state;
            case(state)
                IDLE: if(start) begin // when the trigger arrives, lock in the start and destination addresses
                    read_count<='0; write_count<='0;
                    uab_raddr<=src_addr; uab_waddr<=dest_addr; toggle<='0; 
                end
                STREAM: begin // for every clock cycle, increment the read address by 1 to constantly stream new data out of the RAM, until we hit the sequence limit.
                    if(read_count<seq_length) begin 
                        uab_raddr<=uab_raddr+1; 
                        read_count<=read_count+1; 
                    end
                    if(read_count>0&&write_count<(seq_length>>1)) begin // we only start comparing and writing if we have read something(>0) and haven't exceeded half the sequence length
                        toggle<=~toggle; // 0 to 1 ; 1 to 0
                        if(!toggle) hold_reg<=relu_val; // we just read the 1st row of the pair, don't write to memory yet, just store it safely inside hold_reg
                        else begin // reading the 2nd row of the pair. The combinational block is instantly comparing it to hold_reg and pushing the winner to the output pins
                            uab_waddr<=uab_waddr+1; 
                            write_count<=write_count+1; 
                        end
                    end
                end
            endcase
        end
    end

    always_comb begin // FSM next state logic
        next_state=state;
        case(state)
            IDLE: if(start) next_state=STREAM;
            STREAM: if(write_count==(seq_length>>1)) next_state=DONE;
            DONE: next_state=IDLE;
        endcase
    end

    assign engine_done=(state==DONE);
    assign uab_re=(state==STREAM)&&(read_count<seq_length); // memory reads are only allowed in stream mode when we need data
    assign uab_we=(state==STREAM)&&(read_count>0)&&toggle; // we only write in stream mode when toggle is 1
endmodule