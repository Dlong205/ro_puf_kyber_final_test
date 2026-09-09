`timescale 1ns / 1ps
`default_nettype none

module tb_edge_mlkem_core;
    localparam int EXPECTED_KEM_CYCLES = 19535;

    logic clk = 0;
    always #5 clk = ~clk;
    logic rst_n = 0, zeroize = 0, start = 0;
    logic [191:0] fe_key;

    wire ready_pk, ready_c, req_pk, req_c;
    wire server_valid_out, client_valid_out;
    wire [31:0] dout_server, dout_client;
    wire edge_busy, edge_done, scrub_done, protocol_start, secret_valid;
    wire client_done;
    wire [255:0] K_server, K_client;
    logic saw_client_done = 0;
    logic saw_edge_done = 0;
    logic ciphertext_corrupted = 0;
    int cycles = 0;
    logic invalid_mode;
    int kem_cycles;

    localparam [255:0] SEED_M =
        256'h00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff;

    initial invalid_mode = $test$plusargs("INVALID_CT");
    wire corrupt_word = invalid_mode && !ciphertext_corrupted &&
                        client_valid_out && (dut.u_server.state == 6'h23);
    wire [31:0] client_to_edge = corrupt_word ?
                                  (dout_client ^ 32'h00000001) : dout_client;

    edge_mlkem_core dut (
        .clk(clk), .rst_n(rst_n), .zeroize(zeroize), .start(start),
        .fe_key(fe_key), .stream_in_valid(client_valid_out),
        .peer_ready_c(ready_c), .peer_req_pk(req_pk),
        .stream_in_data(client_to_edge), .ready_pk(ready_pk), .req_c(req_c),
        .stream_out_valid(server_valid_out), .stream_out_data(dout_server),
        .busy(edge_busy), .done(edge_done), .scrub_done(scrub_done),
        .protocol_start(protocol_start), .secret_valid(secret_valid),
        .shared_secret(K_server)
    );

    Kyber_Client client (
        .clk(clk), .rst(!rst_n), .start(protocol_start),
        .scrub_en(1'b0), .scrub_addr(11'd0),
        .wen(server_valid_out), .k(3'd2), .ready_pk(ready_pk),
        .req_c(req_c), .din(dout_server), .ready_c(ready_c),
        .req_pk(req_pk), .valid(), .valid_out(client_valid_out),
        .dout(dout_client), .seed_m(SEED_M), .K(K_client),
        .done(client_done)
    );

    always @(posedge clk) begin
        if (!rst_n) begin
            cycles <= 0;
            saw_client_done <= 0;
            saw_edge_done <= 0;
        end else begin
            cycles <= cycles + 1;
            if (client_done) saw_client_done <= 1;
            if (edge_done) saw_edge_done <= 1;
            if (corrupt_word) ciphertext_corrupted <= 1;
            if (cycles > 600000)
                $fatal(1, "timeout server=%h client=%h",
                       dut.u_server.state, client.state);
        end
    end

    task automatic check(input string name, input logic condition);
        if (!condition) $fatal(1, "FAIL: %s", name);
        $display("PASS: %s", name);
    endtask

    initial begin
        fe_key = {
            32'h17161514, 32'h13121110, 32'h0f0e0d0c,
            32'h0b0a0908, 32'h07060504, 32'h03020100
        };
        repeat (5) @(negedge clk);
        rst_n = 1;
        @(negedge clk); start = 1;
        @(negedge clk); start = 0;

        while (!secret_valid) @(negedge clk);
        kem_cycles = cycles;
        check("fixed valid/invalid KEM latency", kem_cycles == EXPECTED_KEM_CYCLES);
        check("client completion observed", saw_client_done || client_done);
        check("shared key is nonzero", K_server != 0);
        if (invalid_mode) begin
            check("ciphertext corruption injected", ciphertext_corrupted);
            check("modified ciphertext rejected", !dut.u_server.equal);
            check("implicit-rejection key differs", K_server != K_client);
        end else begin
            check("edge and client shared keys match", K_server == K_client);
            check("server accepted valid ciphertext", dut.u_server.equal);
        end
        check("d/z already erased at secret-valid", dut.u_control.seed_d == 0 &&
              dut.u_control.seed_z == 0);
        check("KDF remains erased", dut.u_control.u_seed.kdf_seed == 0 &&
              dut.u_control.u_seed.u_kdf.keccak_inst.state_reg == 0);

        // Full security request resets registers and walks all Kyber storage.
        zeroize = 1;
        @(negedge clk); zeroize = 0;
        while (!scrub_done) @(negedge clk);
        check("zeroize clears server shared secret", K_server == 0);
        check("zeroize returns server FSM idle", dut.u_server.state == 0);
        check("zeroize leaves no transaction completion", !edge_done && !secret_valid);

        $display("EDGE_MLKEM_CORE_PASS mode=%s kem_cycles=%0d total_cycles=%0d",
                 invalid_mode ? "invalid" : "valid", kem_cycles, cycles);
        $finish;
    end
endmodule

`default_nettype wire
