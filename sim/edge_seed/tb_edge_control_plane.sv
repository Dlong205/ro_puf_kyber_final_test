`timescale 1ns / 1ps
`default_nettype none

module tb_edge_control_plane;
    logic clk = 0;
    always #5 clk = ~clk;
    logic rst_n = 0, zeroize = 0, start = 0, core_done = 0;
    logic [191:0] fe_key;
    wire busy, done, scrub_done, core_reset, core_start, scrub_en;
    wire [10:0] scrub_addr;
    wire [255:0] seed_d, seed_z;
    int scrub_count = 0;

    localparam [511:0] EXPECTED = {
        32'h3aff5570, 32'h9429424d, 32'h45de8b1c, 32'h34f7aad8,
        32'hfdf69b34, 32'hb48b340e, 32'habcf673d, 32'hfd02abad,
        32'h1ae1dc88, 32'hafb02040, 32'h370b6470, 32'heea10462,
        32'h0b3c4345, 32'h06d34af4, 32'h180ff71f, 32'h23514971
    };

    edge_control_plane #(.SCRUB_LAST_ADDR(7)) dut (
        .clk(clk), .rst_n(rst_n), .zeroize(zeroize), .start(start),
        .fe_key(fe_key), .core_done(core_done), .busy(busy), .done(done),
        .scrub_done(scrub_done), .core_reset(core_reset),
        .core_start(core_start), .scrub_en(scrub_en),
        .scrub_addr(scrub_addr), .seed_d(seed_d), .seed_z(seed_z)
    );

    always @(posedge clk) if (scrub_en) scrub_count <= scrub_count + 1;

    task automatic check(input string name, input logic condition);
        if (!condition) $fatal(1, "FAIL: %s", name);
        $display("PASS: %s", name);
    endtask

    initial begin
        fe_key = {
            32'h17161514, 32'h13121110, 32'h0f0e0d0c,
            32'h0b0a0908, 32'h07060504, 32'h03020100
        };
        repeat (4) @(negedge clk);
        rst_n = 1;
        @(negedge clk);
        start = 1;
        @(negedge clk); start = 0;

        while (!core_start) begin
            @(negedge clk);
            if ($time > 20000) $fatal(1, "core start timeout");
        end
        check("control plane scrubs all KEM addresses", scrub_count == 8);
        check("derived d survives KEM pre-scrub", seed_d == EXPECTED[255:0]);
        check("derived z survives KEM pre-scrub", seed_z == EXPECTED[511:256]);
        check("KDF state erased before real core start",
              dut.u_seed.kdf_seed == 0 &&
              dut.u_seed.u_kdf.lane_a[0] == 0 &&
              dut.u_seed.u_kdf.lane_a[24] == 0 &&
              dut.u_seed.u_kdf.lane_b[0] == 0 &&
              dut.u_seed.u_kdf.lane_b[24] == 0);
        @(negedge clk);
        check("real core start is one cycle", !core_start);

        core_done = 1;
        @(negedge clk); core_done = 0;
        check("completion erases d/z", seed_d == 0 && seed_z == 0);
        check("control plane done after secret erase", done);
        @(negedge clk);
        check("completion returns idle", !done && !busy);

        // External zeroize while idle still performs a complete KEM scrub.
        scrub_count = 0;
        zeroize = 1;
        @(negedge clk); zeroize = 0;
        while (!scrub_done) @(negedge clk);
        check("idle zeroize scrubs full KEM range", scrub_count == 8);
        check("idle zeroize does not launch KEM", !core_start && !done);

        $display("EDGE_CONTROL_PLANE_PASS");
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "timeout");
    end
endmodule

`default_nettype wire
