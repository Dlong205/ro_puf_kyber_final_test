module echo_top (
    input CLK100MHZ,
    input UART_RXD,
    output UART_TXD,
    output [1:0] LED
);
    // blink led0 to prove clock is alive
    reg [24:0] cnt = 0;
    always @(posedge CLK100MHZ) cnt <= cnt + 1;
    assign LED[0] = cnt[24]; // ~1.5Hz blink @ 50MHz

    wire rx_dv;
    wire [7:0] rx_byte;
    wire tx_active;

    uart_rx #(.CLKS_PER_BIT(434)) u_rx (
        .i_Clock(CLK100MHZ),
        .i_Rst(1'b0),
        .i_Rx_Serial(UART_RXD),
        .o_Rx_DV(rx_dv),
        .o_Rx_Byte(rx_byte)
    );

    uart_tx #(.CLKS_PER_BIT(434)) u_tx (
        .i_Clock(CLK100MHZ),
        .i_Rst(1'b0),
        .i_Tx_DV(rx_dv),
        .i_Tx_Byte(rx_byte),
        .o_Tx_Active(tx_active),
        .o_Tx_Serial(UART_TXD),
        .o_Tx_Done()
    );

    assign LED[1] = tx_active; // blink on tx
endmodule
