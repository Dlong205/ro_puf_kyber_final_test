module IOTA (
    input wire Clk,
    input wire reset,
    input wire enable,
    input wire en_ctr,
    input wire [1599:0] Str_in,
    input wire [575:0] Chi1_data,
    input wire [511:0] Chi2_data,
    input wire [4:0] RC_index,
    output reg [1599:0] Str_out
);
    wire [1599:0] str_data;
    wire [63:0] RC_data;

    Chi_3_Iota IOTA_ALG (
        .A(Str_in),
        .chi2_data(Chi2_data),
        .chi1_data(Chi1_data),
        .RC_data(RC_data),
        .Iota(str_data)
    );
    
    RC IOTA_RC (
        .index(RC_index),
        .RC_out(RC_data)
    );

    always @(posedge Clk or negedge reset) begin
        if (!reset) begin
            Str_out <= 1600'b0;
        end else if (!en_ctr) begin
            Str_out <= 1600'b0;
        end else begin
            if (enable && en_ctr) begin
                Str_out <= str_data;
            end
        end
    end
endmodule
