module THETA2_RHO_PI (
    input wire Clk,
    input wire reset,
    input wire enable,
    input wire en_ctr,
    input wire [1599:0] Rho_str_in,
    input wire [319:0] Rho_data_in,
    input wire [4:0] RC_id_in,
    output reg [4:0] RC_id_out,
    output reg [1599:0] String_out,
    output reg en_out,
    output reg [1599:0] Rho_data_out
);
    `include "keccak_pkg.vh"

    wire [1599:0] A_initial;
    wire [1599:0] A_theta;
    wire [1599:0] A_rho;
    wire [1599:0] Rho_data;

    assign A_initial = Rho_str_in;

    assign A_theta[63:0] = A_initial[63:0] ^ Rho_data_in[63:0];
    assign A_theta[127:64] = A_initial[127:64] ^ Rho_data_in[127:64];
    assign A_theta[191:128] = A_initial[191:128] ^ Rho_data_in[191:128];
    assign A_theta[255:192] = A_initial[255:192] ^ Rho_data_in[255:192];
    assign A_theta[319:256] = A_initial[319:256] ^ Rho_data_in[319:256];
    assign A_theta[383:320] = A_initial[383:320] ^ Rho_data_in[63:0];
    assign A_theta[447:384] = A_initial[447:384] ^ Rho_data_in[127:64];
    assign A_theta[511:448] = A_initial[511:448] ^ Rho_data_in[191:128];
    assign A_theta[575:512] = A_initial[575:512] ^ Rho_data_in[255:192];
    assign A_theta[639:576] = A_initial[639:576] ^ Rho_data_in[319:256];
    assign A_theta[703:640] = A_initial[703:640] ^ Rho_data_in[63:0];
    assign A_theta[767:704] = A_initial[767:704] ^ Rho_data_in[127:64];
    assign A_theta[831:768] = A_initial[831:768] ^ Rho_data_in[191:128];
    assign A_theta[895:832] = A_initial[895:832] ^ Rho_data_in[255:192];
    assign A_theta[959:896] = A_initial[959:896] ^ Rho_data_in[319:256];
    assign A_theta[1023:960] = A_initial[1023:960] ^ Rho_data_in[63:0];
    assign A_theta[1087:1024] = A_initial[1087:1024] ^ Rho_data_in[127:64];
    assign A_theta[1151:1088] = A_initial[1151:1088] ^ Rho_data_in[191:128];
    assign A_theta[1215:1152] = A_initial[1215:1152] ^ Rho_data_in[255:192];
    assign A_theta[1279:1216] = A_initial[1279:1216] ^ Rho_data_in[319:256];
    assign A_theta[1343:1280] = A_initial[1343:1280] ^ Rho_data_in[63:0];
    assign A_theta[1407:1344] = A_initial[1407:1344] ^ Rho_data_in[127:64];
    assign A_theta[1471:1408] = A_initial[1471:1408] ^ Rho_data_in[191:128];
    assign A_theta[1535:1472] = A_initial[1535:1472] ^ Rho_data_in[255:192];
    assign A_theta[1599:1536] = A_initial[1599:1536] ^ Rho_data_in[319:256];

    assign A_rho[63:0] = rotl(A_theta[63:0], 0);
    assign A_rho[127:64] = rotl(A_theta[127:64], 1);
    assign A_rho[191:128] = rotl(A_theta[191:128], 62);
    assign A_rho[255:192] = rotl(A_theta[255:192], 28);
    assign A_rho[319:256] = rotl(A_theta[319:256], 27);
    assign A_rho[383:320] = rotl(A_theta[383:320], 36);
    assign A_rho[447:384] = rotl(A_theta[447:384], 44);
    assign A_rho[511:448] = rotl(A_theta[511:448], 6);
    assign A_rho[575:512] = rotl(A_theta[575:512], 55);
    assign A_rho[639:576] = rotl(A_theta[639:576], 20);
    assign A_rho[703:640] = rotl(A_theta[703:640], 3);
    assign A_rho[767:704] = rotl(A_theta[767:704], 10);
    assign A_rho[831:768] = rotl(A_theta[831:768], 43);
    assign A_rho[895:832] = rotl(A_theta[895:832], 25);
    assign A_rho[959:896] = rotl(A_theta[959:896], 39);
    assign A_rho[1023:960] = rotl(A_theta[1023:960], 41);
    assign A_rho[1087:1024] = rotl(A_theta[1087:1024], 45);
    assign A_rho[1151:1088] = rotl(A_theta[1151:1088], 15);
    assign A_rho[1215:1152] = rotl(A_theta[1215:1152], 21);
    assign A_rho[1279:1216] = rotl(A_theta[1279:1216], 8);
    assign A_rho[1343:1280] = rotl(A_theta[1343:1280], 18);
    assign A_rho[1407:1344] = rotl(A_theta[1407:1344], 2);
    assign A_rho[1471:1408] = rotl(A_theta[1471:1408], 61);
    assign A_rho[1535:1472] = rotl(A_theta[1535:1472], 56);
    assign A_rho[1599:1536] = rotl(A_theta[1599:1536], 14);

    assign Rho_data[63:0] = A_rho[63:0];
    assign Rho_data[127:64] = A_rho[447:384];
    assign Rho_data[191:128] = A_rho[831:768];
    assign Rho_data[255:192] = A_rho[1215:1152];
    assign Rho_data[319:256] = A_rho[1599:1536];
    assign Rho_data[383:320] = A_rho[255:192];
    assign Rho_data[447:384] = A_rho[639:576];
    assign Rho_data[511:448] = A_rho[703:640];
    assign Rho_data[575:512] = A_rho[1087:1024];
    assign Rho_data[639:576] = A_rho[1471:1408];
    assign Rho_data[703:640] = A_rho[127:64];
    assign Rho_data[767:704] = A_rho[511:448];
    assign Rho_data[831:768] = A_rho[895:832];
    assign Rho_data[895:832] = A_rho[1279:1216];
    assign Rho_data[959:896] = A_rho[1343:1280];
    assign Rho_data[1023:960] = A_rho[319:256];
    assign Rho_data[1087:1024] = A_rho[383:320];
    assign Rho_data[1151:1088] = A_rho[767:704];
    assign Rho_data[1215:1152] = A_rho[1151:1088];
    assign Rho_data[1279:1216] = A_rho[1535:1472];
    assign Rho_data[1343:1280] = A_rho[191:128];
    assign Rho_data[1407:1344] = A_rho[575:512];
    assign Rho_data[1471:1408] = A_rho[959:896];
    assign Rho_data[1535:1472] = A_rho[1023:960];
    assign Rho_data[1599:1536] = A_rho[1407:1344];

    always @(*) begin
        if (reset == 1'b0 || en_ctr == 1'b0) begin
            Rho_data_out = 1600'b0;
            String_out = 1600'b0;
            en_out = 1'b0;
            RC_id_out = 5'b0;
        end else if (enable == 1'b1 && en_ctr == 1'b1) begin
            Rho_data_out = Rho_data;
            String_out = Rho_data; // Rho_str_next = converse_str(Rho_data) = Rho_data
            RC_id_out = RC_id_in;
            en_out = enable;
        end else begin
            Rho_data_out = 1600'b0;
            String_out = 1600'b0;
            RC_id_out = RC_id_in;
            en_out = 1'b0;
        end
    end
endmodule
