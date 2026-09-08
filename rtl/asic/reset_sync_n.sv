`timescale 1ns / 1ps
`default_nettype none

// Active-low reset conditioner: asynchronous assertion, two-cycle
// synchronous release.  Technology mapping may replace the two registers with
// approved reset synchronizer cells while preserving this contract.
module reset_sync_n (
    input  wire clk_i,
    input  wire arst_ni,
    output wire srst_no
);
    (* ASYNC_REG = "TRUE" *) reg [1:0] release_ff;

    always @(posedge clk_i or negedge arst_ni) begin
        if (!arst_ni)
            release_ff <= 2'b00;
        else
            release_ff <= {release_ff[0], 1'b1};
    end

    assign srst_no = release_ff[1];
endmodule

`default_nettype wire
