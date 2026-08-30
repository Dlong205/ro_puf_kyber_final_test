`timescale 1ns / 1ps

(* KEEP_HIERARCHY = "yes" *)
module kp_ro_cell #(
    parameter int FREQ_OFFSET = 0
)(
    input  logic clk,
    input  logic rst_n,
    input  logic en,
    input  logic [3:0] cfg,
    output logic o
);

    `ifdef VERILATOR
        logic [15:0] div_cnt;
        logic [15:0] div_val;
        
        always_comb begin
            div_val = 16'd1 + (FREQ_OFFSET[15:0] & 16'h3);
        end
        
        always_ff @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                o <= 1'b0;
                div_cnt <= 16'd0;
            end else if (en) begin
                if (div_cnt >= div_val) begin
                    o <= ~o;
                    div_cnt <= 16'd0;
                end else begin
                    div_cnt <= div_cnt + 1;
                end
            end else begin
                // Match the disabled hardware RO: restart from a defined
                // phase so repeated challenges are deterministic in RTL sim.
                o <= 1'b0;
                div_cnt <= 16'd0;
            end
        end
    `else
        (* DONT_TOUCH = "true" *) logic t0, t1, t2, t3;

        (* DONT_TOUCH = "true" *) LUT6_L #(
            .INIT(64'h8888888888888888)
        ) LUT6_NAND0 (
            .LO(t0),
            .I0(en),
            .I1(t3),
            .I2(cfg[0]),
            .I3(1'b0),
            .I4(1'b0),
            .I5(1'b0)
        );

        (* DONT_TOUCH = "true" *) LUT6_L #(
            .INIT(64'h5555555555555555)
        ) LUT6_INV0 (
            .LO(t1),
            .I0(t0),
            .I1(cfg[1]),
            .I2(1'b0),
            .I3(1'b0),
            .I4(1'b0),
            .I5(1'b0)
        );

        (* DONT_TOUCH = "true" *) LUT6_L #(
            .INIT(64'h5555555555555555)
        ) LUT6_INV1 (
            .LO(t2),
            .I0(t1),
            .I1(cfg[2]),
            .I2(1'b0),
            .I3(1'b0),
            .I4(1'b0),
            .I5(1'b0)
        );

        (* DONT_TOUCH = "true" *) LUT6_L #(
            .INIT(64'h5555555555555555)
        ) LUT6_INV2 (
            .LO(t3),
            .I0(t2),
            .I1(cfg[3]),
            .I2(1'b0),
            .I3(1'b0),
            .I4(1'b0),
            .I5(1'b0)
        );

        assign o = t3;
    `endif

endmodule
