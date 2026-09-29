`timescale 1ns / 1ps
`default_nettype none

// R4 enrollment (sim, RTL-exact): BCH encode the frozen train reference with
// the real fuzzy_extractor, KCV the extracted key with edge_root_binding,
// then self-check reconstruction (decode with the helper must return the
// same key with success).  Stimulus/response files are plain hex text.
module tb_puf64_enroll;
    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rst_n = 1'b0;

    reg [263:0] stim_mem [0:0];
    reg [55:0] ctx_mem [0:0];
    reg [263:0] response_r;
    reg [55:0] ctx_r;
    reg [263:0] helper_r;
    integer fd;

    reg fe_start = 1'b0;
    reg fe_mode = 1'b0;
    wire [263:0] helper_w;
    wire [191:0] key_w;
    wire fe_busy, fe_done, fe_success;
    wire [7:0] fe_corr;
    fuzzy_extractor #(.T(8), .DATA_BITS(192), .N(264), .BITS(8)) u_fe (
        .clk(clk), .rst_n(rst_n), .zeroize(1'b0),
        .start(fe_start), .mode(fe_mode),
        .response_in(response_r), .helper_in(helper_r),
        .helper_out(helper_w), .key_out(key_w),
        .busy(fe_busy), .done(fe_done), .success(fe_success),
        .corr_bit_count(fe_corr)
    );

    reg kcv_start = 1'b0;
    wire [223:0] kcv_w;
    wire kcv_busy, kcv_done, kcv_pass;
    edge_root_binding u_kcv (
        .clk(clk), .rst_n(rst_n), .zeroize(1'b0),
        .start(kcv_start), .root_key(key_w), .kcv_ctx(ctx_r),
        .kcv_ref(224'd0), .busy(kcv_busy), .done(kcv_done),
        .kcv_pass(kcv_pass), .kcv_out(kcv_w)
    );

    reg [191:0] enrolled_key;
    reg [223:0] enrolled_kcv;
    integer guard;

    task automatic wait_fe;
        begin
            guard = 0;
            while (!fe_done && guard < 100000) begin
                @(posedge clk);
                guard = guard + 1;
            end
            if (!fe_done) $fatal(1, "FE timed out");
        end
    endtask

    task automatic wait_kcv;
        begin
            guard = 0;
            while (!kcv_done && guard < 100000) begin
                @(posedge clk);
                guard = guard + 1;
            end
            if (!kcv_done) $fatal(1, "KCV timed out");
        end
    endtask

    initial begin
        $readmemh("enroll_stimulus_response.hex", stim_mem);
        $readmemh("enroll_stimulus_ctx.hex", ctx_mem);
        response_r = stim_mem[0];
        ctx_r = ctx_mem[0];
        helper_r = 264'd0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);
        // 1. enroll
        @(negedge clk); fe_mode = 1'b0; fe_start = 1'b1;
        @(negedge clk); fe_start = 1'b0;
        wait_fe();
        enrolled_key = key_w;
        helper_r = helper_w;
        $display("ENROLL key=%h", key_w);
        // 2. KCV over the enrolled key
        @(negedge clk); kcv_start = 1'b1;
        @(negedge clk); kcv_start = 1'b0;
        wait_kcv();
        enrolled_kcv = kcv_w;
        $display("ENROLL kcv=%h", kcv_w);
        // 3. self-check: reconstruct with helper must return the same key
        @(negedge clk); fe_mode = 1'b1; fe_start = 1'b1;
        @(negedge clk); fe_start = 1'b0;
        wait_fe();
        if (!fe_success) $fatal(1, "reconstruct of own helper failed");
        if (key_w !== enrolled_key)
            $fatal(1, "reconstruct key != enrolled key");
        if (fe_corr != 8'd0)
            $fatal(1, "reconstruct of identical response corrected bits");
        $display("ENROLL_RECONSTRUCT_SELFCHECK_OK corr=%0d", fe_corr);
        fd = $fopen("enroll_result_helper.hex", "w");
        $fwrite(fd, "%h\n", helper_r);
        $fclose(fd);
        fd = $fopen("enroll_result_key.hex", "w");
        $fwrite(fd, "%h\n", enrolled_key);
        $fclose(fd);
        fd = $fopen("enroll_result_kcv.hex", "w");
        $fwrite(fd, "%h\n", enrolled_kcv);
        $fclose(fd);
        $display("PUF64_MACROV2_ENROLL_PASS");
        $finish;
    end

    initial begin
        repeat (2000000) @(posedge clk);
        $fatal(1, "enroll tb timeout");
    end
endmodule

`default_nettype wire
