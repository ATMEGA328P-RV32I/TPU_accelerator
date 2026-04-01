// Copyright 2026 Atul Kumar
module tpu_top #(
    parameter int D_WIDTH = 16
)(
    input  logic clk,
    input  logic rst_n,

    input  logic        host_start,
    output logic        host_done,

    // --- Host 32-bit Programming Interface ---
    input  logic        host_iram_we,
    input  logic [9:0]  host_iram_addr, 
    input  logic [31:0] host_iram_wdata,

    input  logic        host_wram_we,
    input  logic [39:0] host_wram_addr, 
    input  logic signed [D_WIDTH-1:0] host_wram_wdata,

    input  logic        host_uab_we,
    input  logic [39:0] host_uab_addr,  
    input  logic signed [31:0] host_uab_wdata [0:3],
    
    output logic signed [31:0] host_uab_rdata [0:3],

    // --- NEW CLEAN OUTPUTS FOR DEMO ---
    output logic        anomaly_flag,     
    output logic [7:0]  prob_normal_out,  
    output logic [7:0]  prob_anomaly_out  
);

    // ==========================================
    // 1. 128-bit Instruction RAM & Gearbox
    // ==========================================
    logic [127:0] iram [0:255];
    logic [127:0] inst_shadow_reg;
    logic [7:0]   inst_pc;
    logic [127:0] current_instruction;

    always_ff @(posedge clk) begin
        if (host_iram_we) begin
            if (host_iram_addr[1:0] == 2'b00) inst_shadow_reg[31:0]   <= host_iram_wdata;
            if (host_iram_addr[1:0] == 2'b01) inst_shadow_reg[63:32]  <= host_iram_wdata;
            if (host_iram_addr[1:0] == 2'b10) inst_shadow_reg[95:64]  <= host_iram_wdata;
            if (host_iram_addr[1:0] == 2'b11) iram[host_iram_addr[9:2]] <= {host_iram_wdata, inst_shadow_reg[95:0]};
        end
        current_instruction <= iram[inst_pc];
    end

    // ==========================================
    // 2. Weight RAM (4X Expanded: 4096 Depth)
    // ==========================================
    logic signed [D_WIDTH-1:0] wram [0:4095];
    logic        wram_re;
    logic [39:0] wram_raddr;
    logic signed [D_WIDTH-1:0] wram_rdata;

    always_ff @(posedge clk) begin
        if (host_wram_we) wram[host_wram_addr[11:0]] <= host_wram_wdata;
        if (wram_re)      wram_rdata <= wram[wram_raddr[11:0]];
    end

    // ==========================================
    // Internal Wires
    // ==========================================
    logic start_load, start_conv, start_pool, start_dense, relu_en, any_engine_done;
    logic [39:0] src_addr, dest_addr;
    logic [7:0]  config_ptr;

    logic        conv_uab_re, conv_uab_we, conv_done, conv_wram_re;
    logic [39:0] conv_uab_raddr, conv_uab_waddr, conv_wram_raddr;
    logic signed [31:0] conv_uab_wdata [0:3];

    logic        pool_uab_re, pool_uab_we, pool_done;
    logic [39:0] pool_uab_raddr, pool_uab_waddr;
    logic signed [31:0] pool_uab_wdata [0:3];

    logic        dense_uab_re, dense_uab_we, dense_done, dense_wram_re;
    logic [39:0] dense_uab_raddr, dense_uab_waddr, dense_wram_raddr;
    logic signed [31:0] dense_uab_wdata [0:3];

    logic        master_uab_re, master_uab_we;
    logic [39:0] master_uab_raddr, master_uab_waddr;
    logic signed [31:0] master_uab_wdata [0:3], master_uab_rdata [0:3];

    // ==========================================
    // Safe Multiplexer (Traffic Cop)
    // ==========================================
    typedef enum logic [1:0] {HOST, CONV, POOL, DENSE} owner_t;
    owner_t bus_owner;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) bus_owner <= HOST;
        else begin
            if (start_conv)       bus_owner <= CONV;
            else if (start_pool)  bus_owner <= POOL;
            else if (start_dense) bus_owner <= DENSE;
            else if (any_engine_done) bus_owner <= HOST;
        end
    end

    always_comb begin
        if (bus_owner == CONV) begin
            master_uab_re = conv_uab_re; master_uab_we = conv_uab_we;
            master_uab_raddr = conv_uab_raddr; master_uab_waddr = conv_uab_waddr;
            master_uab_wdata = conv_uab_wdata; wram_re = conv_wram_re; wram_raddr = conv_wram_raddr;
        end else if (bus_owner == POOL) begin
            master_uab_re = pool_uab_re; master_uab_we = pool_uab_we;
            master_uab_raddr = pool_uab_raddr; master_uab_waddr = pool_uab_waddr;
            master_uab_wdata = pool_uab_wdata; wram_re = 1'b0; wram_raddr = '0;
        end else if (bus_owner == DENSE) begin
            master_uab_re = dense_uab_re; master_uab_we = dense_uab_we;
            master_uab_raddr = dense_uab_raddr; master_uab_waddr = dense_uab_waddr;
            master_uab_wdata = dense_uab_wdata; wram_re = dense_wram_re; wram_raddr = dense_wram_raddr;
        end else begin
            master_uab_re = 1'b1; master_uab_we = host_uab_we;
            master_uab_raddr = host_uab_addr; master_uab_waddr = host_uab_addr;
            master_uab_wdata = host_uab_wdata; wram_re = 1'b0; wram_raddr = '0;
        end
    end

    assign any_engine_done = conv_done | pool_done | dense_done;
    
    // ==========================================
    // Hardware Softmax & Output Routing
    // ==========================================
    logic [7:0] p_norm, p_anom;

    tpu_softmax softmax_inst (
        .logit_normal(master_uab_rdata[0]),
        .logit_anomaly(master_uab_rdata[1]),
        .prob_normal(p_norm),
        .prob_anomaly(p_anom)
    );

    assign prob_normal_out  = p_norm;
    assign prob_anomaly_out = p_anom;
    assign anomaly_flag = (p_anom > p_norm) ? 1'b1 : 1'b0;

    always_comb begin
        host_uab_rdata[0] = master_uab_rdata[0];
        host_uab_rdata[1] = master_uab_rdata[1];
        host_uab_rdata[2] = master_uab_rdata[2];
        host_uab_rdata[3] = master_uab_rdata[3];
    end

    // ==========================================
    // Module Instantiations
    // ==========================================
    tpu_controller ctrl_inst (
        .clk(clk), .rst_n(rst_n), .tpu_start(host_start), .tpu_done(host_done),
        .inst_pc(inst_pc), .inst_data(current_instruction),
        .start_load(start_load), .start_conv(start_conv), .start_pool(start_pool), .start_dense(start_dense),
        .src_addr(src_addr), .dest_addr(dest_addr), .config_ptr(config_ptr), .relu_en(relu_en),
        .engine_done(any_engine_done)
    );

    tpu_uab uab_inst (
        .clk(clk), .we(master_uab_we), .waddr(master_uab_waddr), .wdata(master_uab_wdata),
        .re(master_uab_re), .raddr(master_uab_raddr), .rdata(master_uab_rdata)
    );

    tpu_conv1d_engine #(.ARRAY_SIZE(5), .D_WIDTH(D_WIDTH)) conv_inst (
        .clk(clk), .rst_n(rst_n), .start(start_conv), .engine_done(conv_done),
        .src_addr(src_addr), .dest_addr(dest_addr), .config_ptr(config_ptr), 
        .seq_length(16'd260), // FIXED: 260 to read padding
        .uab_re(conv_uab_re), .uab_raddr(conv_uab_raddr), .uab_rdata(master_uab_rdata),
        .uab_we(conv_uab_we), .uab_waddr(conv_uab_waddr), .uab_wdata(conv_uab_wdata),
        .wram_re(conv_wram_re), .wram_raddr(conv_wram_raddr), .wram_rdata(wram_rdata)
    );

    tpu_pool_engine pool_inst (
        .clk(clk), .rst_n(rst_n), .start(start_pool), .engine_done(pool_done),
        .src_addr(src_addr), .dest_addr(dest_addr), .seq_length(16'd256),
        .uab_re(pool_uab_re), .uab_raddr(pool_uab_raddr), .uab_rdata(master_uab_rdata),
        .uab_we(pool_uab_we), .uab_waddr(pool_uab_waddr), .uab_wdata(pool_uab_wdata)
    );

    tpu_dense_engine #(.D_WIDTH(D_WIDTH)) dense_inst (
        .clk(clk), .rst_n(rst_n), .start(start_dense), .engine_done(dense_done), .relu_en(relu_en),
        .src_addr(src_addr), .dest_addr(dest_addr), .config_ptr(config_ptr), .seq_length(16'd128),
        .uab_re(dense_uab_re), .uab_raddr(dense_uab_raddr), .uab_rdata(master_uab_rdata),
        .uab_we(dense_uab_we), .uab_waddr(dense_uab_waddr), .uab_wdata(dense_uab_wdata),
        .wram_re(dense_wram_re), .wram_raddr(dense_wram_raddr), .wram_rdata(wram_rdata)
    );

endmodule