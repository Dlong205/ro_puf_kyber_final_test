`timescale 1ns / 1ps

module kp_mux16to1(
    input  logic [15:0] in,
    input  logic [3:0]  select,
    output logic        out
);
    assign out = in[select];
endmodule


module kp_counter_puf #(
    parameter int SIZE = 32
)(
    input  logic clk,
    input  logic en,
    input  logic rst_n,
    input  logic cnt_rst,
    output logic [SIZE-1:0] q
);
    // cnt_rst is generated in the system-clock domain while this counter is
    // clocked by the selected RO.  Assert reset asynchronously (also works
    // when the RO is stopped), then release it synchronously to the RO clock.
    wire local_arst_n = rst_n & ~cnt_rst;
    (* ASYNC_REG = "TRUE" *) logic [1:0] reset_release;
    (* ASYNC_REG = "TRUE" *) logic en_meta, en_sync;
    wire domain_rst_n = reset_release[1];

    always_ff @(posedge clk or negedge local_arst_n) begin
        if (!local_arst_n)
            reset_release <= 2'b00;
        else
            reset_release <= {reset_release[0], 1'b1};
    end

    // Synchronize count_en before it controls a register in the RO domain.
    // Both the synchronizer and counter use the locally synchronized reset.
    always_ff @(posedge clk or negedge domain_rst_n) begin
        if (!domain_rst_n) begin
            en_meta <= 1'b0;
            en_sync <= 1'b0;
            q <= '0;
        end else begin
            en_meta <= en;
            en_sync <= en_meta;
            if (en_sync)
                q <= q + 1'b1;
        end
    end
endmodule


module kp_comparator(
    input  logic [31:0] count0,
    input  logic [31:0] count1,
    output logic        winner
);
    assign winner = (count0 > count1) ? 1'b0 : 1'b1;
endmodule


module kp_shiftReg #(
    parameter int WIDTH = 264
)(
    input  logic        clk,
    input  logic        rst_n,
    input  logic        en,
    input  logic        s_in,
    output logic [WIDTH-1:0] p_out
);
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            p_out <= '0;
        end else if (en) begin
            p_out <= {s_in, p_out[WIDTH-1:1]};
        end
    end
endmodule


module kp_lfsr #(
    parameter int NUM_BITS = 8
)(
    input  logic                  clk,
    input  logic                  rst_n,
    input  logic                  en,
    input  logic                  seed_dv,
    input  logic [NUM_BITS-1:0]   seed,
    output logic [NUM_BITS-1:0]   lfsr_data,
    output logic                  lfsr_done
);
    logic [NUM_BITS:1] r_lfsr;
    logic              r_xnor;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_lfsr <= '0;
        end else if (en) begin
            if (seed_dv) begin
                r_lfsr <= seed;
            end else begin
                r_lfsr <= {r_lfsr[NUM_BITS-1:1], r_xnor};
            end
        end
    end

    always_comb begin
        case (NUM_BITS)
            3:  r_xnor = r_lfsr[3] ^~ r_lfsr[2];
            4:  r_xnor = r_lfsr[4] ^~ r_lfsr[3];
            5:  r_xnor = r_lfsr[5] ^~ r_lfsr[3];
            6:  r_xnor = r_lfsr[6] ^~ r_lfsr[5];
            7:  r_xnor = r_lfsr[7] ^~ r_lfsr[6];
            8:  r_xnor = r_lfsr[8] ^~ r_lfsr[6] ^~ r_lfsr[5] ^~ r_lfsr[4];
            default: r_xnor = 1'b0;
        endcase
    end

    assign lfsr_data  = r_lfsr[NUM_BITS:1];
    assign lfsr_done  = (r_lfsr[NUM_BITS:1] == seed);

endmodule
