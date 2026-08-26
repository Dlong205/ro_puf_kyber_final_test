module Chi_3_Iota (
    input wire [1599:0] A,
    input wire [511:0] chi2_data,
    input wire [575:0] chi1_data,
    input wire [63:0] RC_data,
    output wire [1599:0] Iota
);
    wire [1599:0] A_in;
    wire [1599:0] A_after_chi;
    wire [1599:0] A_blk;

    assign A_in = A;

    assign A_after_chi[1151:1088] = A_in[1151:1088] ^ (~A_in[1215:1152] & A_in[1279:1216]);
    assign A_after_chi[1215:1152] = A_in[1215:1152] ^ (~A_in[1279:1216] & A_in[1023:960]);
    assign A_after_chi[1279:1216] = A_in[1279:1216] ^ (~A_in[1023:960] & A_in[1087:1024]);
    assign A_after_chi[1343:1280] = A_in[1343:1280] ^ (~A_in[1407:1344] & A_in[1471:1408]);
    assign A_after_chi[1407:1344] = A_in[1407:1344] ^ (~A_in[1471:1408] & A_in[1535:1472]);
    assign A_after_chi[1471:1408] = A_in[1471:1408] ^ (~A_in[1535:1472] & A_in[1599:1536]);
    assign A_after_chi[1535:1472] = A_in[1535:1472] ^ (~A_in[1599:1536] & A_in[1343:1280]);
    assign A_after_chi[1599:1536] = A_in[1599:1536] ^ (~A_in[1343:1280] & A_in[1407:1344]);
    assign A_after_chi[63:0] = chi1_data[63:0];
    assign A_after_chi[127:64] = chi1_data[127:64];
    assign A_after_chi[191:128] = chi1_data[191:128];
    assign A_after_chi[255:192] = chi1_data[255:192];
    assign A_after_chi[319:256] = chi1_data[319:256];
    assign A_after_chi[383:320] = chi1_data[383:320];
    assign A_after_chi[447:384] = chi1_data[447:384];
    assign A_after_chi[511:448] = chi1_data[511:448];
    assign A_after_chi[575:512] = chi1_data[575:512];
    assign A_after_chi[639:576] = chi2_data[63:0];
    assign A_after_chi[703:640] = chi2_data[127:64];
    assign A_after_chi[767:704] = chi2_data[191:128];
    assign A_after_chi[831:768] = chi2_data[255:192];
    assign A_after_chi[895:832] = chi2_data[319:256];
    assign A_after_chi[959:896] = chi2_data[383:320];
    assign A_after_chi[1023:960] = chi2_data[447:384];
    assign A_after_chi[1087:1024] = chi2_data[511:448];

    assign A_blk[63:0] = A_after_chi[63:0] ^ RC_data;
    assign A_blk[127:64] = A_after_chi[127:64];
    assign A_blk[191:128] = A_after_chi[191:128];
    assign A_blk[255:192] = A_after_chi[255:192];
    assign A_blk[319:256] = A_after_chi[319:256];
    assign A_blk[383:320] = A_after_chi[383:320];
    assign A_blk[447:384] = A_after_chi[447:384];
    assign A_blk[511:448] = A_after_chi[511:448];
    assign A_blk[575:512] = A_after_chi[575:512];
    assign A_blk[639:576] = A_after_chi[639:576];
    assign A_blk[703:640] = A_after_chi[703:640];
    assign A_blk[767:704] = A_after_chi[767:704];
    assign A_blk[831:768] = A_after_chi[831:768];
    assign A_blk[895:832] = A_after_chi[895:832];
    assign A_blk[959:896] = A_after_chi[959:896];
    assign A_blk[1023:960] = A_after_chi[1023:960];
    assign A_blk[1087:1024] = A_after_chi[1087:1024];
    assign A_blk[1151:1088] = A_after_chi[1151:1088];
    assign A_blk[1215:1152] = A_after_chi[1215:1152];
    assign A_blk[1279:1216] = A_after_chi[1279:1216];
    assign A_blk[1343:1280] = A_after_chi[1343:1280];
    assign A_blk[1407:1344] = A_after_chi[1407:1344];
    assign A_blk[1471:1408] = A_after_chi[1471:1408];
    assign A_blk[1535:1472] = A_after_chi[1535:1472];
    assign A_blk[1599:1536] = A_after_chi[1599:1536];

    assign Iota = A_blk;
endmodule
