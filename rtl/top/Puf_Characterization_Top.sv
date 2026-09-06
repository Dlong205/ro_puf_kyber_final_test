`timescale 1ns / 1ps

// Standalone PUF-only top for laboratory characterization. It intentionally
// exposes raw responses over UART and must not be shipped as a release image.
module Puf_Characterization_Top(
    input  wire       CLK100MHZ,
    input  wire [1:0] SW,
    input  wire       UART_RXD,
    output wire       UART_TXD,
    output wire [1:0] LED
);
    wire clk = CLK100MHZ;

    reg [15:0] por_cnt = 16'd0;
    reg        por_done = 1'b0;
    always @(posedge clk) begin
        if (!por_done) begin
            por_cnt <= por_cnt + 1'b1;
            por_done <= (por_cnt == 16'hFFFF);
        end
    end

    wire puf_start;
    wire puf_busy;
    wire puf_done;
    wire tx_active;
    wire [263:0] puf_response;

    // Keep the instance name identical to the release top so its LOC/BEL map
    // resolves to the same 128 physical LUTs.
    kp_puf_top u_puf (
        .clk(clk),
        .rst_n(por_done),
        .start(puf_start),
        .seed(8'h42),
        .busy(puf_busy),
        .done(puf_done),
        .response(puf_response)
    );

    puf_characterization_uart #(.CLKS_PER_BIT(434)) u_uart (
        .clk(clk),
        .rst_n(por_done),
        .uart_rx_i(UART_RXD),
        .uart_tx_o(UART_TXD),
        .tx_active(tx_active),
        .puf_start(puf_start),
        .puf_done(puf_done),
        .puf_response(puf_response)
    );

    assign LED[0] = tx_active;
    assign LED[1] = puf_busy;

    // SW is intentionally unused in this diagnostic image.
    wire unused_sw = &SW;
endmodule
