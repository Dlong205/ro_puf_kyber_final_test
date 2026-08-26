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
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            q <= '0;
        end else if (cnt_rst) begin
            q <= '0;
        end else if (en) begin
            q <= q + 1;
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