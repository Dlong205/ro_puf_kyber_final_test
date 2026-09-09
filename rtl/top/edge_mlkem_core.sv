`timescale 1ns / 1ps
`default_nettype none

// CPU-free ML-KEM-512 Edge role: derived seeds + secure launch + legacy
// KeyGen/Decaps datapath.  This is an internal core boundary, not a board top.
// shared_secret must terminate in a confirmation engine in the final design.
module edge_mlkem_core (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         zeroize,
    input  wire         start,
    input  wire [191:0] fe_key,

    input  wire         stream_in_valid,
    input  wire         peer_ready_c,
    input  wire         peer_req_pk,
    input  wire [31:0]  stream_in_data,
    output wire         ready_pk,
    output wire         req_c,
    output wire         stream_out_valid,
    output wire [31:0]  stream_out_data,

    output wire         busy,
    output wire         done,
    output wire         scrub_done,
    output wire         protocol_start,
    output wire         secret_valid,
    output wire [255:0] shared_secret
);
    wire core_reset;
    wire scrub_en;
    wire [10:0] scrub_addr;
    wire [255:0] seed_d;
    wire [255:0] seed_z;
    wire core_done;
    wire unused_valid;

    edge_control_plane u_control (
        .clk(clk), .rst_n(rst_n), .zeroize(zeroize), .start(start),
        .fe_key(fe_key), .core_done(core_done), .busy(busy), .done(done),
        .scrub_done(scrub_done), .core_reset(core_reset),
        .core_start(protocol_start), .scrub_en(scrub_en),
        .scrub_addr(scrub_addr), .seed_d(seed_d), .seed_z(seed_z)
    );

    Kyber_Server u_server (
        .clk(clk), .rst(core_reset), .start(protocol_start),
        .scrub_en(scrub_en), .scrub_addr(scrub_addr),
        .wen(stream_in_valid), .k(3'd2),
        .ready_c(peer_ready_c), .req_pk(peer_req_pk),
        .din(stream_in_data), .ready_pk(ready_pk), .req_c(req_c),
        .valid(unused_valid), .valid_out(stream_out_valid),
        .dout(stream_out_data), .seed_d(seed_d), .seed_z(seed_z),
        .K(shared_secret), .done(core_done)
    );

    assign secret_valid = done;
endmodule

`default_nettype wire
