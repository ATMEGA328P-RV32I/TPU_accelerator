// Copyright 2026 Atul Kumar
module tpu_dense_engine #(parameter int D_WIDTH=16)(
    input logic clk,rst_n,start, // starting the engine
    output logic engine_done, // flag telling whether finished execution
    input logic relu_en, // whether relu needs to be applied
    input logic [39:0] src_addr,dest_addr, // where to read data and where to write result
    input logic [7:0] config_ptr, // location of dense weights in wram
    input logic [15:0] seq_length, // length of pooled sequence

    output logic uab_re, // uab read write prot
    output logic [39:0] uab_raddr,
    input logic signed [31:0] uab_rdata[0:3],
    output logic uab_we,
    output logic [39:0] uab_waddr,
    output logic signed [31:0] uab_wdata[0:3],
    
    output logic wram_re, // wram read port
    output logic [39:0] wram_raddr,
    input logic signed [D_WIDTH-1:0] wram_rdata
);
    typedef enum logic [3:0] {IDLE,LOAD_B,FETCH_ADDR,LATCH_MEM,MAC_0,MAC_1,MAC_2,MAC_3,WRITE_OUT,DONE} state_t; // 10 state fsm
    state_t state,next_state;
    
    logic [15:0] vec_idx; // counts through the pooled sequence
    logic node_idx; // 1 bit switch, 0 means we are calculating the normal probability, 1 means we are calculating the anomaly probability
    logic [10:0] weight_cnt; // which weight is being used currently
    logic [1:0] bias_cnt; // which bias is being used currently
    logic signed [47:0] accum; // the massive accumulator, when we multiply a 32-bit activation by a 16-bit weight and add it up hundreds of times, a 32-bit register will overflow and crash, hence built a custom 48 bit register to hold the massive sum
    logic signed [31:0] final_nodes[0:1]; // to hold the 2 final output logits
    logic signed [31:0] dense_b[0:1]; // to hold the 2 loaded biases

    always_comb begin
        case(state) // the wram address multiplexer, this instantly calculates where to point the wram read address based on what state we are in
            LOAD_B: wram_raddr={30'd0,config_ptr,2'b00}+11'd1024+bias_cnt;
            LATCH_MEM: wram_raddr={30'd0,config_ptr,2'b00}+weight_cnt; 
            MAC_0: wram_raddr={30'd0,config_ptr,2'b00}+weight_cnt+1;
            MAC_1: wram_raddr={30'd0,config_ptr,2'b00}+weight_cnt+2;
            MAC_2: wram_raddr={30'd0,config_ptr,2'b00}+weight_cnt+3;
            default: wram_raddr={30'd0,config_ptr,2'b00}+weight_cnt;
        endcase
    end
    assign uab_raddr=src_addr+vec_idx;

    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=IDLE;
            {vec_idx,node_idx,weight_cnt,bias_cnt}<='0;
            accum<='0;
            final_nodes[0]<='0; final_nodes[1]<='0;
            dense_b[0]<='0; dense_b[1]<='0;
        end else begin
            state<=next_state;
            case(state)
                IDLE: if(start) begin 
                    vec_idx<='0; node_idx<=1'b0; weight_cnt<='0; accum<='0; bias_cnt<='0; 
                end
                LOAD_B: begin
                    if(bias_cnt>0&&bias_cnt<=2) begin
                        dense_b[bias_cnt-1]<={{16{wram_rdata[15]}},wram_rdata};
                    end
                    bias_cnt<=bias_cnt+1;
                end
                MAC_0: accum<=accum+($signed(uab_rdata[0])*$signed(wram_rdata));
                MAC_1: accum<=accum+($signed(uab_rdata[1])*$signed(wram_rdata));
                MAC_2: accum<=accum+($signed(uab_rdata[2])*$signed(wram_rdata));
                MAC_3: begin
                    logic signed [47:0] new_accum=accum+($signed(uab_rdata[3])*$signed(wram_rdata));
                    weight_cnt<=weight_cnt+4;
                    if(vec_idx==seq_length-1) begin
                        final_nodes[node_idx]<=(new_accum>>>8)+dense_b[node_idx];
                        if(node_idx==1'b1) state<=WRITE_OUT;
                        else begin 
                            node_idx<=1'b1; vec_idx<='0; accum<='0; state<=FETCH_ADDR; 
                        end
                    end else begin 
                        accum<=new_accum; vec_idx<=vec_idx+1; 
                    end
                end
            endcase
        end
    end

    always_comb begin
        next_state=state;
        case(state)
            IDLE: if(start) next_state=LOAD_B;
            LOAD_B: if(bias_cnt==3) next_state=FETCH_ADDR;
            FETCH_ADDR: next_state=LATCH_MEM;
            LATCH_MEM: next_state=MAC_0;
            MAC_0: next_state=MAC_1;
            MAC_1: next_state=MAC_2;
            MAC_2: next_state=MAC_3;
            MAC_3: next_state=(vec_idx==seq_length-1&&node_idx==1'b1)?WRITE_OUT:FETCH_ADDR;
            WRITE_OUT: next_state=DONE;
            DONE: next_state=IDLE;
            default: next_state=IDLE;
        endcase
    end

    assign engine_done=(state==DONE);
    assign uab_re=(state==FETCH_ADDR);
    assign wram_re=(state==LOAD_B&&bias_cnt<2)||(state==FETCH_ADDR)||(state==LATCH_MEM)||(state==MAC_0)||(state==MAC_1)||(state==MAC_2);
    assign uab_we=(state==WRITE_OUT);
    assign uab_waddr=dest_addr;

    always_comb begin
        if(relu_en) begin
            uab_wdata[0]=(final_nodes[0]>32'sd0)?final_nodes[0]:32'sd0;
            uab_wdata[1]=(final_nodes[1]>32'sd0)?final_nodes[1]:32'sd0;
        end else begin
            uab_wdata[0]=final_nodes[0];
            uab_wdata[1]=final_nodes[1];
        end
        uab_wdata[2]=32'sd0; 
        uab_wdata[3]=32'sd0;
    end
endmodule