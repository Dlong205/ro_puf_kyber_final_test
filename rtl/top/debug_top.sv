module debug_top (
    input CLK100MHZ,
    input [1:0] SW,
    output [1:0] LED
);
    // 1. Asynchronous Combinational Logic
    // If the FPGA is programmed and PL is alive, SW[0] will instantly toggle LED[0]
    assign LED[0] = SW[0];

    // 2. Clocked Logic
    // If the 50MHz clock is alive, LED[1] will blink at ~1.5Hz.
    // If clock is dead, LED[1] will stay OFF (or solid if active-low and cnt=0).
    reg [24:0] cnt = 0;
    always @(posedge CLK100MHZ) begin
        cnt <= cnt + 1;
    end
    assign LED[1] = cnt[24];
endmodule
