`timescale 1ns / 1ps
`default_nettype none

// Digital integration boundary for the ASIC flow.
//
// This module deliberately contains no pad cells, PLL, power-on reset counter,
// FPGA primitive or technology library instance.  The physical integration
// layer must provide a stable clock and an active-low reset.  Reset assertion
// may be asynchronous; release is synchronized locally before it reaches the
// digital system.
module Kyber_System_Asic_Top #(
    parameter integer UART_CLKS_PER_BIT = 434,
    parameter [7:0]   PUF_SEED = 8'h42
) (
    input  wire       clk_i,
    input  wire       rst_ni,
    input  wire       uart_rx_i,
    output wire       uart_tx_o,
    output wire [1:0] status_o
);

    // Asynchronous assertion, synchronous release into the system clock
    // domain.  The external reset controller must hold rst_ni low until the
    // supply and clk_i satisfy the technology-specific requirements.
    wire rst_sys_n;
    reset_sync_n u_reset_sync (
        .clk_i(clk_i),
        .arst_ni(rst_ni),
        .srst_no(rst_sys_n)
    );

    wire tx_active;
    wire kyber_done;
    wire [263:0] puf_resp;
    wire [191:0] fe_key;
    wire [511:0] kyber_seed;

    wire puf_start;
    wire fe_start;
    wire fe_mode;
    wire kdf_start;
    wire secure_zeroize;
    wire puf_done;
    wire fe_done;
    wire fe_success;
    wire kdf_done;
    wire [263:0] helper_soc_to_fe;
    wire [263:0] helper_fe_to_soc;

    // Only non-secret progress signals cross this integration boundary.
    assign status_o[0] = tx_active;
    assign status_o[1] = kyber_done;

    riscv_soc #(
        .CLKS_PER_BIT(UART_CLKS_PER_BIT),
        .EXPOSE_KYBER_SECRETS(0),
        .SECURE_KYBER_SCRUB(1)
    ) u_soc (
        .clk(clk_i),
        .rstn(rst_sys_n),
        .rx(uart_rx_i),
        .tx(uart_tx_o),
        .tx_active(tx_active),
        .kyber_done(kyber_done),
        .kyber_shared_secret(),
        .puf_start(puf_start),
        .fe_start(fe_start),
        .fe_mode(fe_mode),
        .kdf_start(kdf_start),
        .secure_zeroize(secure_zeroize),
        .puf_done(puf_done),
        .fe_done(fe_done),
        .fe_success(fe_success),
        .kdf_done(kdf_done),
        .helper_out(helper_soc_to_fe),
        .helper_in(helper_fe_to_soc),
        .kdf_seed(kyber_seed)
    );

    kp_puf_top u_puf (
        .clk(clk_i),
        .rst_n(rst_sys_n),
        .zeroize(secure_zeroize),
        .start(puf_start),
        .seed(PUF_SEED),
        .busy(),
        .done(puf_done),
        .response(puf_resp)
    );

    fuzzy_extractor u_fe (
        .clk(clk_i),
        .rst_n(rst_sys_n),
        .zeroize(secure_zeroize),
        .start(fe_start),
        .mode(fe_mode),
        .response_in(puf_resp),
        .helper_in(helper_soc_to_fe),
        .helper_out(helper_fe_to_soc),
        .key_out(fe_key),
        .busy(),
        .done(fe_done),
        .success(fe_success)
    );

    kdf_keccak u_kdf (
        .clk(clk_i),
        .rst_n(rst_sys_n),
        .zeroize(secure_zeroize),
        .start(kdf_start),
        .key_in(fe_key),
        .done(kdf_done),
        .seed_out(kyber_seed)
    );

endmodule

`default_nettype wire
