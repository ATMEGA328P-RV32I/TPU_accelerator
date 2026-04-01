// Copyright 2026 Atul Kumar
// high precision hardware softmax 
// Idea- Use memory to reduce dependcece on DSP blocks
module tpu_softmax(
    input logic signed [31:0] logit_normal,
    input logic signed [31:0] logit_anomaly,
    output logic [7:0] prob_normal,
    output logic [7:0] prob_anomaly
);

    logic signed [31:0] diff;
    logic [7:0] lut_val;

    // diff = anomaly - normal
    assign diff=logit_anomaly-logit_normal;

    always_comb begin
        if(diff<-32'sd996) lut_val=8'd0; // < 2%
        else if(diff<-32'sd704) lut_val=8'd4; // 2% - 6%
        else if(diff<-32'sd562) lut_val=8'd8; // 6% - 10%
        else if(diff<-32'sd464) lut_val=8'd12; // 10% - 14%
        else if(diff<-32'sd388) lut_val=8'd16; // 14% - 18%
        else if(diff<-32'sd324) lut_val=8'd20; // 18% - 22%
        else if(diff<-32'sd268) lut_val=8'd24; // 22% - 26%
        else if(diff<-32'sd217) lut_val=8'd28; // 26% - 30%
        else if(diff<-32'sd170) lut_val=8'd32; // 30% - 34%
        else if(diff<-32'sd125) lut_val=8'd36; // 34% - 38%
        else if(diff<-32'sd83) lut_val=8'd40; // 38% - 42%
        else if(diff<-32'sd41) lut_val=8'd44; // 42% - 46%
        else if(diff<32'sd0) lut_val=8'd48; // 46% - 50%
        else if(diff==32'sd0) lut_val=8'd50; // cead center
        else if(diff<32'sd41) lut_val=8'd52; // 50% - 54%
        else if(diff<32'sd83) lut_val=8'd56; // 54% - 58%
        else if(diff<32'sd125) lut_val=8'd60; // 58% - 62%
        else if(diff<32'sd170) lut_val=8'd64; // 62% - 66%
        else if(diff<32'sd217) lut_val=8'd68; // 66% - 70%
        else if(diff<32'sd268) lut_val=8'd72; // 70% - 74%
        else if(diff<32'sd324) lut_val=8'd76; // 74% - 78%
        else if(diff<32'sd388) lut_val=8'd80; // 78% - 82%
        else if(diff<32'sd464) lut_val=8'd84; // 82% - 86%
        else if(diff<32'sd562) lut_val=8'd88; // 86% - 90%
        else if(diff<32'sd704) lut_val=8'd92; // 90% - 94%
        else if(diff<32'sd996) lut_val=8'd96; // 94% - 98%
        else lut_val=8'd100; // > 98%
    end

    assign prob_anomaly=lut_val;
    assign prob_normal=8'd100-lut_val;

endmodule