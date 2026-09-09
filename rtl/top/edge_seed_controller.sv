`timescale 1ns / 1ps
`default_nettype none

// CPU-free handoff from the fuzzy-extractor key to ML-KEM-512 KeyGen/Decaps.
//
// A transaction is strictly sequential:
//   FE key -> SHAKE256 KDF -> capture d/z -> scrub KDF -> pulse kem_start.
// The KEM must capture seed_d/seed_z on kem_start and report kem_done when it
// no longer needs them.  Seeds are never exposed through a software/MMIO port.
module edge_seed_controller (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         zeroize,
    input  wire         start,
    input  wire [191:0] fe_key,
    input  wire         kem_done,
    output wire         busy,
    output wire         done,
    output wire         kem_start,
    output reg  [255:0] seed_d,
    output reg  [255:0] seed_z
);
    localparam [2:0] ST_IDLE       = 3'd0;
    localparam [2:0] ST_KDF_WAIT   = 3'd1;
    localparam [2:0] ST_KDF_SCRUB  = 3'd2;
    localparam [2:0] ST_KEM_START  = 3'd3;
    localparam [2:0] ST_KEM_WAIT   = 3'd4;
    localparam [2:0] ST_DONE       = 3'd5;

    reg [2:0] state;
    reg       start_seen;
    wire      start_accept = (state == ST_IDLE) && start && !start_seen;
    wire      kdf_done;
    wire [511:0] kdf_seed;
    wire      kdf_zeroize = zeroize || (state == ST_KDF_SCRUB);

    assign busy      = (state != ST_IDLE) && (state != ST_DONE);
    assign done      = (state == ST_DONE);
    assign kem_start = (state == ST_KEM_START);

    kdf_keccak u_kdf (
        .clk(clk),
        .rst_n(rst_n),
        .zeroize(kdf_zeroize),
        .start(start_accept),
        .key_in(fe_key),
        .done(kdf_done),
        .seed_out(kdf_seed)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= ST_IDLE;
            start_seen <= 1'b0;
            seed_d     <= 256'd0;
            seed_z     <= 256'd0;
        end else if (zeroize) begin
            state      <= ST_IDLE;
            // A held-high request must be released after an abort.
            start_seen <= 1'b1;
            seed_d     <= 256'd0;
            seed_z     <= 256'd0;
        end else begin
            if (!start)
                start_seen <= 1'b0;
            else if (start_accept)
                start_seen <= 1'b1;

            case (state)
                ST_IDLE: begin
                    seed_d <= 256'd0;
                    seed_z <= 256'd0;
                    if (start_accept)
                        state <= ST_KDF_WAIT;
                end

                ST_KDF_WAIT: begin
                    if (kdf_done) begin
                        // Matches the existing firmware mapping:
                        // KDF words 0..7 -> d, words 8..15 -> z.
                        seed_d <= kdf_seed[255:0];
                        seed_z <= kdf_seed[511:256];
                        state  <= ST_KDF_SCRUB;
                    end
                end

                ST_KDF_SCRUB: state <= ST_KEM_START;
                ST_KEM_START: state <= ST_KEM_WAIT;

                ST_KEM_WAIT: begin
                    if (kem_done) begin
                        seed_d <= 256'd0;
                        seed_z <= 256'd0;
                        state  <= ST_DONE;
                    end
                end

                ST_DONE: state <= ST_IDLE;

                default: begin
                    state  <= ST_IDLE;
                    seed_d <= 256'd0;
                    seed_z <= 256'd0;
                end
            endcase
        end
    end
endmodule

`default_nettype wire
