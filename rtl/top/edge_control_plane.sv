`timescale 1ns / 1ps
`default_nettype none

// Controller-only integration boundary. seed_d/seed_z and core_* connect to
// Kyber_Server inside the eventual Edge top; they are not board-level ports.
module edge_control_plane #(
    parameter integer SCRUB_LAST_ADDR = 2047
) (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         zeroize,
    input  wire         start,
    input  wire [191:0] fe_key,
    input  wire         core_done,
    output wire         busy,
    output wire         done,
    output wire         scrub_done,
    output wire         core_reset,
    output wire         core_start,
    output wire         scrub_en,
    output wire [10:0]  scrub_addr,
    output wire [255:0] seed_d,
    output wire [255:0] seed_z
);
    wire seed_busy;
    wire seed_done;
    wire kem_launch_req;
    wire scrub_busy;
    wire scrub_tx_done;
    wire scrub_ready;

    edge_seed_controller u_seed (
        .clk(clk), .rst_n(rst_n), .zeroize(zeroize), .start(start),
        .fe_key(fe_key), .kem_done(core_done), .busy(seed_busy),
        .done(seed_done), .kem_start(kem_launch_req),
        .seed_d(seed_d), .seed_z(seed_z)
    );

    edge_kem_scrub_controller #(
        .SCRUB_LAST_ADDR(SCRUB_LAST_ADDR)
    ) u_scrub (
        .clk(clk), .rst_n(rst_n), .zeroize(zeroize),
        .launch_req(kem_launch_req), .core_done(core_done), .ready(scrub_ready),
        .busy(scrub_busy), .done(scrub_tx_done), .scrub_done(scrub_done),
        .core_reset(core_reset), .core_start(core_start),
        .scrub_en(scrub_en), .scrub_addr(scrub_addr)
    );

    // seed_done is the externally visible transaction completion because it
    // is the point at which d/z have also been erased. scrub_tx_done should
    // coincide, but is intentionally not relied on for secret lifecycle.
    assign busy = seed_busy || scrub_busy;
    assign done = seed_done;

`ifndef SYNTHESIS
    always @(posedge clk) begin
        if (!zeroize && (seed_done != scrub_tx_done))
            $error("Edge controller completion phases diverged");
        if (!zeroize && kem_launch_req && !scrub_ready)
            $error("Seed controller requested a busy KEM scrub controller");
    end
`endif
endmodule

`default_nettype wire
