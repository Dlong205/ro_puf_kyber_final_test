`timescale 1ns / 1ps
`default_nettype none

// Reconstruct one real frozen holdout vector with the provisioned helper and
// trusted KCV.  Stimuli are private/generated and are never compiled in.
module tb_puf64_reconstruct_vector;
    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rst_n = 1'b0;

    reg [263:0] response_mem [0:0];
    reg [263:0] helper_mem [0:0];
    reg [55:0] ctx_mem [0:0];
    reg [223:0] kcv_mem [0:0];
    reg fe_start = 1'b0;
    wire [191:0] key_w;
    wire fe_done, fe_success;
    wire [7:0] fe_corr;

    fuzzy_extractor #(.T(8), .DATA_BITS(192), .N(264), .BITS(8)) u_fe (
        .clk(clk), .rst_n(rst_n), .zeroize(1'b0), .start(fe_start),
        .mode(1'b1), .response_in(response_mem[0]),
        .helper_in(helper_mem[0]), .helper_out(), .key_out(key_w), .busy(),
        .done(fe_done), .success(fe_success), .corr_bit_count(fe_corr)
    );

    reg kcv_start = 1'b0;
    wire kcv_done, kcv_pass;
    wire [223:0] kcv_out;
    edge_root_binding u_kcv (
        .clk(clk), .rst_n(rst_n), .zeroize(1'b0), .start(kcv_start),
        .root_key(key_w), .kcv_ctx(ctx_mem[0]), .kcv_ref(kcv_mem[0]),
        .busy(), .done(kcv_done), .kcv_pass(kcv_pass), .kcv_out(kcv_out)
    );

    integer guard;
    initial begin
        $readmemh("reconstruct_stimulus_response.hex", response_mem);
        $readmemh("reconstruct_stimulus_helper.hex", helper_mem);
        $readmemh("reconstruct_stimulus_ctx.hex", ctx_mem);
        $readmemh("reconstruct_stimulus_kcv.hex", kcv_mem);
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);
        @(negedge clk); fe_start = 1'b1;
        @(negedge clk); fe_start = 1'b0;
        guard = 0;
        while (!fe_done && guard < 100000) begin
            @(posedge clk); guard = guard + 1;
        end
        if (!fe_done) $fatal(1, "FE timed out");
        if (!fe_success) $fatal(1, "real holdout helper reconstruction failed");
        if (fe_corr > 8) $fatal(1, "BCH correction count outside T=8");
        @(negedge clk); kcv_start = 1'b1;
        @(negedge clk); kcv_start = 1'b0;
        guard = 0;
        while (!kcv_done && guard < 100000) begin
            @(posedge clk); guard = guard + 1;
        end
        if (!kcv_done) $fatal(1, "KCV timed out");
        if (!kcv_pass) $fatal(1, "real helper key does not match anchor");
        $display("PUF64_REAL_HOLDOUT_RECONSTRUCT_PASS corr=%0d", fe_corr);
        $finish;
    end

    initial begin
        repeat (1000000) @(posedge clk);
        $fatal(1, "reconstruct vector timeout");
    end
endmodule

`default_nettype wire
