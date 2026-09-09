`timescale 1ns / 1ps
`default_nettype none

module tb_edge_seed_controller;
    logic clk = 0;
    always #5 clk = ~clk;

    logic rst_n = 0;
    logic zeroize = 0;
    logic start = 0;
    logic [191:0] fe_key;
    logic kem_done = 0;
    wire busy, done, kem_start;
    wire [255:0] seed_d, seed_z;
    int kem_start_count = 0;

    localparam [511:0] EXPECTED = {
        32'h3aff5570, 32'h9429424d, 32'h45de8b1c, 32'h34f7aad8,
        32'hfdf69b34, 32'hb48b340e, 32'habcf673d, 32'hfd02abad,
        32'h1ae1dc88, 32'hafb02040, 32'h370b6470, 32'heea10462,
        32'h0b3c4345, 32'h06d34af4, 32'h180ff71f, 32'h23514971
    };

    edge_seed_controller dut (
        .clk(clk), .rst_n(rst_n), .zeroize(zeroize), .start(start),
        .fe_key(fe_key), .kem_done(kem_done), .busy(busy), .done(done),
        .kem_start(kem_start), .seed_d(seed_d), .seed_z(seed_z)
    );

    always @(posedge clk) if (kem_start) kem_start_count <= kem_start_count + 1;

    task automatic check(input string name, input logic condition);
        if (!condition) $fatal(1, "FAIL: %s", name);
        $display("PASS: %s", name);
    endtask

    task automatic pulse_start;
        @(negedge clk); start = 1;
        @(negedge clk); start = 0;
    endtask

    task automatic wait_kem_start;
        int timeout = 0;
        while (!kem_start && timeout < 1000) begin
            @(negedge clk); timeout++;
        end
        check("KDF reaches KEM start", kem_start);
    endtask

    initial begin
        fe_key = {
            32'h17161514, 32'h13121110, 32'h0f0e0d0c,
            32'h0b0a0908, 32'h07060504, 32'h03020100
        };
        repeat (5) @(negedge clk);
        rst_n = 1;

        // Normal transaction: direct mapping, KDF scrub before KEM start,
        // busy-start ignored, and seeds retained only while KEM needs them.
        pulse_start();
        wait_kem_start();
        check("KDF low half maps to d", seed_d == EXPECTED[255:0]);
        check("KDF high half maps to z", seed_z == EXPECTED[511:256]);
        check("KDF output scrubbed before KEM", dut.kdf_seed == 0);
        check("KDF key/state scrubbed before KEM",
              dut.u_kdf.key_shift == 0 && dut.u_kdf.keccak_inst.state_reg == 0);
        pulse_start();
        repeat (4) @(negedge clk);
        check("busy start does not retrigger", kem_start_count == 1);
        check("seeds stable while KEM active",
              seed_d == EXPECTED[255:0] && seed_z == EXPECTED[511:256]);
        kem_done = 1;
        @(negedge clk); kem_done = 0;
        check("completion scrubs d/z", seed_d == 0 && seed_z == 0);
        check("controller emits done", done);
        @(negedge clk);
        check("done is one cycle and controller idles", !done && !busy);

        // Abort during KDF. No delayed KEM launch may escape the abort.
        pulse_start();
        repeat (20) @(negedge clk);
        check("abort test entered busy state", busy);
        // Keep request asserted across abort. Controller must require a low
        // level before accepting a new transaction.
        start = 1;
        zeroize = 1;
        @(negedge clk); zeroize = 0;
        check("zeroize aborts and clears outputs", !busy && !kem_start &&
              seed_d == 0 && seed_z == 0 && dut.kdf_seed == 0);
        repeat (250) @(negedge clk);
        check("no late KEM start after abort", kem_start_count == 1);

        // Held-high request is accepted once; it must be released to re-arm.
        repeat (5) @(negedge clk);
        check("held start after abort is not accepted", !busy);
        start = 0;
        @(negedge clk);
        start = 1;
        wait_kem_start();
        check("released request re-arms controller", kem_start_count == 1);
        @(negedge clk);
        check("one KEM pulse after re-arm", kem_start_count == 2);
        kem_done = 1;
        @(negedge clk); kem_done = 0;
        @(negedge clk);
        repeat (5) @(negedge clk);
        check("held request cannot auto-restart", kem_start_count == 2 && !busy);
        start = 0;

        $display("EDGE_SEED_CONTROLLER_PASS");
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "timeout");
    end
endmodule

`default_nettype wire
