`timescale 1ns / 1ps
`default_nettype none

// Laboratory-only full Edge top. Raw PUF data and the shared secret never
// leave the FPGA, but the compact 32-bit equality tag is not release-grade.
module Edge_Arty_Diagnostic_Top #(
    parameter integer UART_CLKS_PER_BIT = 868
) (
    input  wire       CLK100MHZ,
    input  wire [1:0] SW,
    input  wire       UART_RXD,
    output wire       UART_TXD,
    output wire [3:0] LED
);
    reg [15:0] por_count = 16'd0;
    reg por_done = 1'b0;
    always @(posedge CLK100MHZ) begin
        if (!por_done) begin
            por_count <= por_count + 1'b1;
            por_done <= &por_count;
        end
    end

    wire core_start;
    wire core_zeroize;
    wire core_enroll;
    wire [263:0] helper_in;
    wire [263:0] helper_out;
    wire fe_success;
    wire ready_pk;
    wire req_c;
    wire stream_out_valid;
    wire [31:0] stream_out_data;
    wire peer_req_pk;
    wire peer_ready_c;
    wire stream_in_valid;
    wire [31:0] stream_in_data;
    wire busy;
    wire done;
    wire scrub_done;
    wire protocol_start;
    wire secret_valid;
    wire [255:0] shared_secret;
    wire tx_active;
    wire [223:0] core_kcv_ref;
    wire [55:0]  core_kcv_ctx;
    wire [55:0]  core_enroll_ctx;
    wire         core_kcv_enable;
    wire [223:0] core_fe_kcv;
    wire zeroize = core_zeroize || SW[0];

    edge_puf_mlkem_core u_core (
        .clk(CLK100MHZ), .rst_n(por_done), .zeroize(zeroize),
        .start(core_start), .enroll(core_enroll), .puf_seed(8'h42),
        .helper_in(helper_in), .helper_out(helper_out),
        .fe_success(fe_success),
        .kcv_enable(core_kcv_enable), .kcv_ref(core_kcv_ref),
        .kcv_ctx(core_kcv_ctx), .enroll_ctx(core_enroll_ctx),
        .kcv_pass(), .fe_kcv(core_fe_kcv),
        .stream_in_valid(stream_in_valid),
        .peer_ready_c(peer_ready_c), .peer_req_pk(peer_req_pk),
        .stream_in_data(stream_in_data), .ready_pk(ready_pk), .req_c(req_c),
        .stream_out_valid(stream_out_valid),
        .stream_out_data(stream_out_data), .busy(busy), .done(done),
        .scrub_done(scrub_done), .protocol_start(protocol_start),
        .secret_valid(secret_valid), .shared_secret(shared_secret)
    );

    edge_uart_transport #(
        .CLKS_PER_BIT(UART_CLKS_PER_BIT),
        // Diagnostic bring-up lifecycle allows enrollment; a release
        // operational build must override this to 1'b0.
        .ALLOW_ENROLL(1'b1)
    ) u_transport (
        .clk(CLK100MHZ), .rst_n(por_done), .uart_rx_i(UART_RXD),
        .uart_tx_o(UART_TXD), .tx_active(tx_active), .core_start(core_start),
        .core_zeroize(core_zeroize), .core_enroll(core_enroll),
        .helper_in(helper_in), .helper_out(helper_out),
        .core_fe_kcv(core_fe_kcv), .core_kcv_enable(core_kcv_enable),
        .core_kcv_ref(core_kcv_ref), .core_kcv_ctx(core_kcv_ctx), .core_enroll_ctx(core_enroll_ctx),
        .fe_success(fe_success), .core_done(done), .core_busy(busy),
        .ready_pk(ready_pk), .req_c(req_c),
        .stream_out_valid(stream_out_valid),
        .stream_out_data(stream_out_data), .peer_req_pk(peer_req_pk),
        .peer_ready_c(peer_ready_c), .stream_in_valid(stream_in_valid),
        .stream_in_data(stream_in_data), .secret_valid(secret_valid),
        .shared_secret(shared_secret)
    );

    assign LED[0] = tx_active;
    assign LED[1] = busy;
    assign LED[2] = ready_pk || req_c;
    assign LED[3] = scrub_done;
    wire unused_sw = SW[1] ^ protocol_start;
endmodule

`default_nettype wire
