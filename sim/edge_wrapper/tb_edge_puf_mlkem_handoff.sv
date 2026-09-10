`timescale 1ns / 1ps
`default_nettype none

module kp_puf_top (
    input wire clk, input wire rst_n, input wire zeroize, input wire start,
    input wire [7:0] seed, output reg busy, output reg done,
    output reg [263:0] response
);
    always @(posedge clk or negedge rst_n or posedge zeroize) begin
        if (!rst_n || zeroize) begin
            busy <= 1'b0; done <= 1'b0; response <= 264'd0;
        end else begin
            done <= busy;
            busy <= start;
            if (start) response <= {256'h1234, seed};
        end
    end
endmodule

module fuzzy_extractor (
    input wire clk, input wire rst_n, input wire zeroize, input wire start,
    input wire mode, input wire [263:0] response_in,
    input wire [263:0] helper_in, output reg [263:0] helper_out,
    output reg [191:0] key_out, output reg busy, output reg done,
    output reg success
);
    localparam [191:0] TEST_KEY = 192'h0123456789abcdef_fedcba9876543210_a55a5aa5_deadbeef;
    always @(posedge clk or negedge rst_n or posedge zeroize) begin
        if (!rst_n || zeroize) begin
            helper_out <= 264'd0; key_out <= 192'd0; busy <= 1'b0;
            done <= 1'b0; success <= 1'b0;
        end else begin
            done <= busy;
            busy <= start;
            if (start) begin
                helper_out <= helper_in ^ response_in;
                key_out <= TEST_KEY;
                success <= mode;
            end
        end
    end
endmodule

module edge_mlkem_core (
    input wire clk, input wire rst_n, input wire zeroize, input wire start,
    input wire [191:0] fe_key, input wire stream_in_valid,
    input wire peer_ready_c, input wire peer_req_pk,
    input wire [31:0] stream_in_data, output wire ready_pk,
    output wire req_c, output wire stream_out_valid,
    output wire [31:0] stream_out_data, output reg busy, output reg done,
    output wire scrub_done, output wire protocol_start,
    output reg secret_valid, output reg [255:0] shared_secret
);
    localparam [191:0] TEST_KEY = 192'h0123456789abcdef_fedcba9876543210_a55a5aa5_deadbeef;
    reg captured_good;
    assign ready_pk = 1'b0;
    assign req_c = 1'b0;
    assign stream_out_valid = 1'b0;
    assign stream_out_data = 32'd0;
    assign scrub_done = done;
    assign protocol_start = start;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n || zeroize) begin
            busy <= 1'b0; done <= 1'b0; secret_valid <= 1'b0;
            shared_secret <= 256'd0; captured_good <= 1'b0;
        end else begin
            done <= busy;
            secret_valid <= busy;
            busy <= start;
            if (start) begin
                captured_good <= fe_key == TEST_KEY;
                shared_secret <= {64'd0, fe_key};
            end
        end
    end
endmodule

module tb_edge_puf_mlkem_handoff;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg zeroize = 1'b0;
    reg start = 1'b0;
    wire done;
    integer cycles;
    always #5 clk = ~clk;

    edge_puf_mlkem_core dut (
        .clk(clk), .rst_n(rst_n), .zeroize(zeroize), .start(start),
        .enroll(1'b0), .puf_seed(8'h5a), .helper_in(264'h1),
        .helper_out(), .fe_success(), .stream_in_valid(1'b0),
        .peer_ready_c(1'b0), .peer_req_pk(1'b0), .stream_in_data(32'd0),
        .ready_pk(), .req_c(), .stream_out_valid(), .stream_out_data(),
        .busy(), .done(done), .scrub_done(), .protocol_start(),
        .secret_valid(), .shared_secret()
    );

    initial begin
        repeat (3) @(posedge clk);
        rst_n <= 1'b1;
        @(posedge clk); start <= 1'b1;
        @(posedge clk); start <= 1'b0;
        cycles = 0;
        while (!done && cycles < 40) begin
            @(posedge clk);
            cycles = cycles + 1;
        end
        if (!done) $fatal(1, "wrapper handoff timed out");
        if (!dut.u_edge.captured_good)
            $fatal(1, "FE key was erased before Edge captured it");
        if (dut.u_fe.key_out != 192'd0)
            $fatal(1, "FE key was not erased after handoff");
        $display("EDGE_PUF_MLKEM_HANDOFF_PASS cycles=%0d", cycles);
        $finish;
    end
endmodule

`default_nettype wire
