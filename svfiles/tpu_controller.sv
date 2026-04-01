// Copyright 2026 Atul Kumar
module tpu_controller (
    input  logic        clk, rst_n, tpu_start,
    output logic        tpu_done,
    output logic [7:0]  inst_pc,
    input  logic [127:0] inst_data,
    
    output logic        start_load, start_conv, start_pool, start_dense,
    output logic [39:0] src_addr, dest_addr,
    output logic [7:0]  config_ptr,
    output logic        relu_en,
    input  logic        engine_done
);

    typedef enum logic [2:0] {IDLE, FETCH, DECODE_EXEC, WAIT_ENGINE, DONE} state_t;
    state_t state, next_state;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin state <= IDLE; inst_pc <= 0; end
        else begin
            state <= next_state;
            if (state == IDLE && tpu_start) inst_pc <= 0;
            else if (state == WAIT_ENGINE && engine_done) inst_pc <= inst_pc + 1;
        end
    end

    always_comb begin
        next_state = state;
        case (state)
            IDLE:        if (tpu_start) next_state = FETCH;
            FETCH:       next_state = DECODE_EXEC;
            DECODE_EXEC: next_state = (inst_data[127:124] == 4'hF) ? DONE : ((inst_data[127:124] == 4'h0) ? WAIT_ENGINE : WAIT_ENGINE);
            WAIT_ENGINE: if (inst_data[127:124] == 4'h0 || engine_done) next_state = FETCH;
            DONE:        if (!tpu_start) next_state = IDLE;
            default:     next_state = IDLE;
        endcase
    end

    assign start_load  = (state == DECODE_EXEC) && (inst_data[127:124] == 4'h1);
    assign start_conv  = (state == DECODE_EXEC) && (inst_data[127:124] == 4'h2);
    assign start_pool  = (state == DECODE_EXEC) && (inst_data[127:124] == 4'h3);
    assign start_dense = (state == DECODE_EXEC) && (inst_data[127:124] == 4'h4);
    
    assign src_addr    = inst_data[123:84];
    assign dest_addr   = inst_data[83:44];
    assign config_ptr  = inst_data[43:36];
    assign relu_en     = inst_data[35];
    assign tpu_done    = (state == DONE);

endmodule