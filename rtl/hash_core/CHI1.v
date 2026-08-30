module CHI1 (
    input wire Clk,
    input wire reset,
    input wire enable,
    input wire en_ctr,
    input wire [1599:0] Chi1_data_in,
    input wire [1599:0] Chi1_str_in,
    input wire [4:0] RC_id_in,
    output reg [4:0] RC_id_out,
    output reg [575:0] Chi1_data_out,
    output reg en_out,
    output reg [1599:0] Chi1_str_out
);
    wire [575:0] chi1_tmp;
    assign chi1_tmp[63:0] = Chi1_data_in[63:0] ^ (~Chi1_data_in[127:64] & Chi1_data_in[191:128]);
    assign chi1_tmp[127:64] = Chi1_data_in[127:64] ^ (~Chi1_data_in[191:128] & Chi1_data_in[255:192]);
    assign chi1_tmp[191:128] = Chi1_data_in[191:128] ^ (~Chi1_data_in[255:192] & Chi1_data_in[319:256]);
    assign chi1_tmp[255:192] = Chi1_data_in[255:192] ^ (~Chi1_data_in[319:256] & Chi1_data_in[63:0]);
    assign chi1_tmp[319:256] = Chi1_data_in[319:256] ^ (~Chi1_data_in[63:0] & Chi1_data_in[127:64]);
    assign chi1_tmp[383:320] = Chi1_data_in[383:320] ^ (~Chi1_data_in[447:384] & Chi1_data_in[511:448]);
    assign chi1_tmp[447:384] = Chi1_data_in[447:384] ^ (~Chi1_data_in[511:448] & Chi1_data_in[575:512]);
    assign chi1_tmp[511:448] = Chi1_data_in[511:448] ^ (~Chi1_data_in[575:512] & Chi1_data_in[639:576]);
    assign chi1_tmp[575:512] = Chi1_data_in[575:512] ^ (~Chi1_data_in[639:576] & Chi1_data_in[383:320]);

    always @(*) begin
        if (reset == 1'b0 || en_ctr == 1'b0) begin
            Chi1_data_out = 576'b0;
            Chi1_str_out = 1600'b0;
            en_out = 1'b0;
            RC_id_out = 5'b0;
        end else if (enable == 1'b1 && en_ctr == 1'b1) begin
            Chi1_data_out = chi1_tmp;
            Chi1_str_out = Chi1_str_in;
            RC_id_out = RC_id_in;
            en_out = enable;
        end else begin
            Chi1_data_out = 576'b0;
            Chi1_str_out = 1600'b0;
            RC_id_out = RC_id_in;
            en_out = 1'b0;
        end
    end
endmodule
