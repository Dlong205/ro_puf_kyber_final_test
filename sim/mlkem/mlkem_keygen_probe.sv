`timescale 1ns/1ps

// Deterministic ML-KEM-512 KeyGen harness.
//
// The legacy Kyber_Server expects Client request/ready traffic after it emits
// the public key.  A Client instance is therefore connected for interface
// compatibility, while the KAT deliberately ends after capturing ek.
module mlkem_keygen_probe (
    input  wire        clk,
    input  wire [255:0] seed_d,
    input  wire [255:0] seed_z,
    input  wire [6:0]  inspect_addr,
    input  wire [3:0]  tail_addr,
    output wire        pk_valid,
    output wire [31:0] pk_word,
    output wire [47:0] sk_quad,
    output wire [31:0] dk_tail_word,
    output wire [5:0]  server_state
);
    reg rst_n = 1'b0;
    reg start_reg = 1'b0;
    integer cycle_count = 0;

    localparam [255:0] SEED_M = 256'h0;

    wire ready_pk;
    wire ready_c;
    wire req_pk;
    wire req_c;
    wire [31:0] dout_server;
    wire [31:0] dout_client;
    wire server_valid_out;
    wire client_valid_out;
    wire server_valid;
    wire client_valid;
    wire server_done;
    wire client_done;
    wire [255:0] K_server;
    wire [255:0] K_client;

    assign pk_valid = server_valid_out;
    assign pk_word = dout_server;
    assign server_state = server_inst.state;
    // Four consecutive 12-bit s-hat coefficients are interleaved across
    // RAM0/RAM1 at each address: RAM0.lo, RAM0.hi, RAM1.lo, RAM1.hi.
    assign sk_quad = {server_inst.ntt.RAM1.inst.mem[inspect_addr],
                      server_inst.ntt.RAM0.inst.mem[inspect_addr]};
    assign dk_tail_word = tail_addr[3] ?
        (server_inst.z >> (32 * tail_addr[2:0])) :
        (server_inst.hash_pk >> (32 * tail_addr[2:0]));

    initial begin
        repeat (5) @(posedge clk);
        rst_n = 1'b1;
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            cycle_count <= 0;
            start_reg <= 1'b0;
        end else begin
            cycle_count <= cycle_count + 1;
            start_reg <= (cycle_count == 0);
        end
    end

`ifdef MLKEM_DEBUG
    always @(posedge clk) begin
        if (server_inst.hash.sponge_done)
            $display("HASH_DONE cyc=%0d state=%h rate=%0d ext=%b stream=%h patt=%b eta3=%b",
                cycle_count, server_inst.state,
                server_inst.hash.sponge_output_rate,
                server_inst.hash.sponge_done_extend,
                server_inst.hash.matrix_stream_id,
                server_inst.patt_bit, server_inst.eta3_bit);
        if (server_inst.hash.matrix_stream_change)
            $display("MATRIX_BOUNDARY cyc=%0d stream=%h seen=%h ctr=%0d",
                cycle_count, server_inst.hash.decode_stream,
                server_inst.hash.matrix_stream_seen,
                server_inst.hash.fifo_GENA_ctr);
    end
`endif

    Kyber_Server server_inst (
        .clk(clk), .rst(~rst_n), .start(start_reg),
        .wen(client_valid_out), .k(3'd2), .ready_c(ready_c),
        .req_pk(req_pk), .din(dout_client), .ready_pk(ready_pk),
        .req_c(req_c), .valid(server_valid),
        .valid_out(server_valid_out), .dout(dout_server),
        .seed_d(seed_d), .seed_z(seed_z), .K(K_server),
        .done(server_done)
    );

    Kyber_Client client_inst (
        .clk(clk), .rst(~rst_n), .start(start_reg),
        .wen(server_valid_out), .k(3'd2), .ready_pk(ready_pk),
        .req_c(req_c), .din(dout_server), .ready_c(ready_c),
        .req_pk(req_pk), .valid(client_valid),
        .valid_out(client_valid_out), .dout(dout_client),
        .seed_m(SEED_M), .K(K_client), .done(client_done)
    );
endmodule
