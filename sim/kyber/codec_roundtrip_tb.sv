`timescale 1ns/1ps

module codec_roundtrip_tb(input logic clk);
    logic rst = 1'b1;
    logic enc_wen = 1'b0;
    logic [21:0] enc_din = '0;
    wire [31:0] enc_dout;
    wire enc_valid;

    wire [31:0] fifo_dout;
    wire fifo_full;
    wire fifo_empty;
    wire dec_req;
    wire dec_valid;
    wire [23:0] dec_dout;

    logic [19:0] expected [0:255];
    integer received;
    integer mismatches;
    integer trial;
    integer i;

    encode_Client encoder (
        .clk(clk), .rst(rst), .din(enc_din), .wen(enc_wen),
        .k(3'd2), .sel(1'b0), .dout(enc_dout), .valid(enc_valid)
    );

    fifo_wrapper_32_16 #(.DEPTH(512)) transport (
        .clk(clk), .rst_n(~rst), .wr_en(enc_valid), .wr_data(enc_dout),
        .rd_en(dec_req), .dout(fifo_dout), .full(fifo_full),
        .empty(fifo_empty)
    );

    decode_Server decoder (
        .clk(clk), .rst(rst), .din(fifo_dout), .fifo_empty(fifo_empty),
        .CCA(1'b0), .sel(1'b0), .k(3'd2), .dout(dec_dout),
        .req(dec_req), .valid(dec_valid)
    );

    always @(posedge clk) begin
        if (rst) begin
            received <= 0;
            mismatches <= 0;
        end else if (dec_valid && received < 256) begin
            if (dec_dout[19:0] != expected[received]) begin
                mismatches <= mismatches + 1;
                if (mismatches < 8)
                    $display("[CODEC] trial=%0d sample=%0d expected=%05h got=%05h",
                             trial, received, expected[received], dec_dout[19:0]);
            end
            received <= received + 1;
        end
    end

    function automatic [19:0] sample_value(input integer trial_id,
                                            input integer sample_id);
        logic [31:0] x;
        begin
            x = 32'h9e3779b9 * (trial_id + 1) ^
                32'h85ebca6b * (sample_id + 3);
            x = x ^ (x << 13);
            x = x ^ (x >> 17);
            x = x ^ (x << 5);
            sample_value = {x[25:16], x[9:0]};
        end
    endfunction

    initial begin
        repeat (4) @(posedge clk);
        for (trial = 0; trial < 32; trial = trial + 1) begin
            rst = 1'b1;
            enc_wen = 1'b0;
            repeat (3) @(posedge clk);
            @(negedge clk);
            rst = 1'b0;

            for (i = 0; i < 256; i = i + 1) begin
                expected[i] = sample_value(trial, i);
                enc_din = {2'b0, sample_value(trial, i)};
                enc_wen = 1'b1;
                @(negedge clk);
            end
            enc_wen = 1'b0;

            for (i = 0; i < 3000 && received < 256; i = i + 1)
                @(posedge clk);
            if (received != 256)
                $fatal(1, "Codec trial %0d timed out after %0d decoded samples",
                       trial, received);
            if (mismatches != 0)
                $fatal(1, "Codec trial %0d failed with %0d/256 mismatches",
                       trial, mismatches);
        end

        $display("*** KYBER U CODEC ROUND-TRIP PASS (32 x 256 samples) ***");
        $finish;
    end
endmodule
