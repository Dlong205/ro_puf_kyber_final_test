`timescale 1ns / 1ps
`default_nettype none

// Resource-only measurement boundaries. Every functional output, including K,
// remains observable in OOC synthesis. These are NOT board tops or an external
// ML-KEM command API. Keeping scrub inputs dynamic includes its implementation.
module fpga_split_client_k2 (
    input wire clk, rst, start, scrub_en,
    input wire [10:0] scrub_addr,
    input wire wen, ready_pk, req_c,
    input wire [31:0] din,
    input wire [255:0] seed_m,
    output wire ready_c, req_pk, valid, valid_out, done,
    output wire [31:0] dout,
    output wire [255:0] K
);
    Kyber_Client u_client (
        .clk(clk), .rst(rst), .start(start), .scrub_en(scrub_en),
        .scrub_addr(scrub_addr), .wen(wen), .k(3'd2),
        .ready_pk(ready_pk), .req_c(req_c), .din(din),
        .ready_c(ready_c), .req_pk(req_pk), .valid(valid), .dout(dout),
        .valid_out(valid_out), .seed_m(seed_m), .K(K), .done(done)
    );
endmodule

module fpga_split_server_k2 (
    input wire clk, rst, start, scrub_en,
    input wire [10:0] scrub_addr,
    input wire wen, ready_c, req_pk,
    input wire [31:0] din,
    input wire [255:0] seed_d, seed_z,
    output wire ready_pk, req_c, valid, valid_out, done,
    output wire [31:0] dout,
    output wire [255:0] K
);
    Kyber_Server u_server (
        .clk(clk), .rst(rst), .start(start), .scrub_en(scrub_en),
        .scrub_addr(scrub_addr), .wen(wen), .k(3'd2),
        .ready_c(ready_c), .req_pk(req_pk), .din(din),
        .ready_pk(ready_pk), .req_c(req_c), .valid(valid), .dout(dout),
        .valid_out(valid_out), .seed_d(seed_d), .seed_z(seed_z),
        .K(K), .done(done)
    );
endmodule
`default_nettype wire
