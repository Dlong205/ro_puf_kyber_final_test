`timescale 1ns / 1ps
`default_nettype none

// T4/T8: SoC MMIO trust-anchor behavior.
//  * operational (DIAGNOSTIC_PROVISION=0): the engine reference always comes
//    from the trusted anchor; CPU writes to the KCV shadow cannot change it,
//    and reads at KCV_REF return no computed-digest oracle.
//  * diagnostic  (DIAGNOSTIC_PROVISION=1): enrollment may read the public
//    digest and the CPU may fill the comparison-only shadow.
module tb_soc_kcv_operational;
    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rstn = 1'b0;

    reg         mem_valid = 1'b0;
    reg  [31:0] mem_addr = 32'd0;
    reg  [31:0] mem_wdata = 32'd0;
    reg  [3:0]  mem_wstrb = 4'd0;
    wire        op_ready, diag_ready;
    wire [31:0] op_rdata, diag_rdata;

    reg  [223:0] trusted_ref = 224'h0123456789abcdef0123456789abcdef01234567;
    reg          trusted_valid = 1'b1;
    reg          kcv_done = 1'b0;
    reg          kcv_pass = 1'b0;
    reg  [223:0] kcv_out = 224'hcafebabecafebabecafebabecafebabecafebabe;

    wire [223:0] op_kcv_ref;
    wire [223:0] diag_kcv_ref;
    wire        op_tx, diag_tx, op_tx_active, diag_tx_active;
    wire [263:0] op_helper_out, diag_helper_out;

    soc_peripherals #(.CLKS_PER_BIT(4), .DIAGNOSTIC_PROVISION(1'b0)) op (
        .clk(clk), .rstn(rstn), .mem_valid(mem_valid), .mem_ready(op_ready),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_wstrb(mem_wstrb),
        .mem_rdata(op_rdata), .rx(1'b1), .tx(op_tx),
        .tx_active(op_tx_active), .puf_start(), .fe_start(), .fe_mode(),
        .kdf_start(), .secure_zeroize(), .puf_done(1'b0), .fe_done(1'b0),
        .fe_success(1'b0), .kdf_done(1'b0), .secure_zeroize_done(1'b0),
        .kdf_seed(512'd0), .helper_out_data(op_helper_out),
        .helper_in_data(264'd0), .kcv_start(), .kcv_ref(op_kcv_ref),
        .kcv_ctx(), .kcv_done(kcv_done), .kcv_pass(kcv_pass),
        .kcv_out(kcv_out), .trusted_kcv_valid_i(trusted_valid),
        .trusted_kcv_ref_i(trusted_ref)
    );

    soc_peripherals #(.CLKS_PER_BIT(4), .DIAGNOSTIC_PROVISION(1'b1)) diag (
        .clk(clk), .rstn(rstn), .mem_valid(mem_valid), .mem_ready(diag_ready),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_wstrb(mem_wstrb),
        .mem_rdata(diag_rdata), .rx(1'b1), .tx(diag_tx),
        .tx_active(diag_tx_active), .puf_start(), .fe_start(), .fe_mode(),
        .kdf_start(), .secure_zeroize(), .puf_done(1'b0), .fe_done(1'b0),
        .fe_success(1'b0), .kdf_done(1'b0), .secure_zeroize_done(1'b0),
        .kdf_seed(512'd0), .helper_out_data(diag_helper_out),
        .helper_in_data(264'd0), .kcv_start(), .kcv_ref(diag_kcv_ref),
        .kcv_ctx(), .kcv_done(kcv_done), .kcv_pass(kcv_pass),
        .kcv_out(kcv_out), .trusted_kcv_valid_i(trusted_valid),
        .trusted_kcv_ref_i(trusted_ref)
    );

    integer checks = 0;

    task automatic write32(input [31:0] addr, input [31:0] data);
        begin
            @(negedge clk);
            mem_addr = addr; mem_wdata = data; mem_wstrb = 4'hF;
            mem_valid = 1'b1;
            wait (op_ready && diag_ready);
            @(negedge clk);
            mem_valid = 1'b0; mem_wstrb = 4'h0;
        end
    endtask

    task automatic read_op(input [31:0] addr, output [31:0] data);
        begin
            @(negedge clk);
            mem_addr = addr; mem_wdata = 32'd0; mem_wstrb = 4'h0;
            mem_valid = 1'b1;
            wait (op_ready);
            data = op_rdata;
            @(negedge clk);
            mem_valid = 1'b0;
        end
    endtask

    task automatic read_diag(input [31:0] addr, output [31:0] data);
        begin
            @(negedge clk);
            mem_addr = addr; mem_wdata = 32'd0; mem_wstrb = 4'h0;
            mem_valid = 1'b1;
            wait (diag_ready);
            data = diag_rdata;
            @(negedge clk);
            mem_valid = 1'b0;
        end
    endtask

    reg [31:0] value;

    initial begin
        repeat (4) @(posedge clk);
        rstn = 1'b1;
        repeat (2) @(posedge clk);

        // CPU writes only reach the comparison-only shadow.  The engine
        // reference is a separate top-level anchor input (trusted_ref) and is
        // structurally unreachable from this bus.
        write32(32'h100000A0, 32'hDEADBEEF);
        if (op_kcv_ref[31:0] !== 32'hDEADBEEF)
            $fatal(1, "shadow write did not reach the register");
        if (diag_kcv_ref[31:0] !== 32'hDEADBEEF)
            $fatal(1, "diagnostic shadow did not capture the CPU write");
        checks = checks + 1;

        // Operational: KCV_REF reads expose no digest oracle.
        read_op(32'h100000A0, value);
        if (value !== 32'd0)
            $fatal(1, "operational KCV_REF read leaked the digest: %08x", value);
        checks = checks + 1;

        // Diagnostic: enrollment may read the public digest.
        read_diag(32'h100000A0, value);
        if (value !== kcv_out[31:0])
            $fatal(1, "diagnostic digest read mismatch: %08x", value);
        checks = checks + 1;

        // KCV_CTRL exposes the trusted-anchor valid bit (bit 2).
        read_op(32'h100000C4, value);
        if (value[2] !== trusted_valid)
            $fatal(1, "KCV_CTRL anchor-valid bit wrong: %08x", value);
        trusted_valid = 1'b0;
        @(posedge clk);
        read_op(32'h100000C4, value);
        if (value[2] !== 1'b0)
            $fatal(1, "KCV_CTRL anchor-valid did not follow the anchor");
        checks = checks + 1;

        $display("SOC_KCV_MMIO_OPERATIONAL_PASS checks=%0d", checks);
        $finish;
    end

    initial begin
        repeat (20000) @(posedge clk);
        $fatal(1, "timeout");
    end
endmodule

`default_nettype wire
