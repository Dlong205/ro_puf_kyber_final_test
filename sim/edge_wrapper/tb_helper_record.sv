`timescale 1ns / 1ps
`default_nettype none

// Unit tests for the Phase-1 helper-record parser.  The parser enforces the
// header/mapping binding (magic/version/profile/FE/reserved/mapping) before
// any BCH or KDF work; the CRC is now computed sequentially by the transport
// and passed in as crc_ok, so this module only checks the header and the
// CRC-decision slot in the error precedence chain.  Same-root is the KCV
// gate's job, not the parser's.  Vectors come from scripts/helper_record_spec.py.
module tb_helper_record;
    `include "helper_record_spec.vh"
    `include "helper_record_kat.vh"

    reg  [8*HREC_BYTES-1:0] raw = HREC_KAT_RAW;
    reg  [7:0]  exp_profile = HREC_KAT_PROFILE;
    reg  [7:0]  exp_fe      = HREC_KAT_FE;
    reg  [7:0]  exp_maplen  = HREC_KAT_MAPLEN;
    reg  [15:0] exp_maptag  = HREC_KAT_MAPTAG;
    reg  crc_ok = 1'b1;
    wire [3:0]   status;
    wire [263:0] helper;
    wire [223:0] kcv_ref;
    wire [55:0]  kcv_ctx;
    wire [7:0]   generation;

    integer checks = 0;
    integer i;

    helper_record_parse dut (
        .raw(raw),
        .expected_profile(exp_profile),
        .expected_fe_param(exp_fe),
        .expected_mapping_len(exp_maplen),
        .expected_mapping_tag(exp_maptag),
        .crc_ok(crc_ok),
        .status(status),
        .helper(helper),
        .kcv_ref(kcv_ref),
        .kcv_ctx(kcv_ctx),
        .generation(generation)
    );

    function automatic [8*HREC_BYTES-1:0] with_byte(
        input [8*HREC_BYTES-1:0] v,
        input integer index,
        input [7:0] value
    );
        begin
            v[8*index +: 8] = value;
            with_byte = v;
        end
    endfunction

    task automatic expect_status(
        input [8*HREC_BYTES-1:0] test_raw,
        input [7:0] profile, fe, maplen,
        input [15:0] maptag,
        input crc_good,
        input [3:0] want,
        input [95:0] name
    );
        begin
            raw = test_raw;
            exp_profile = profile;
            exp_fe = fe;
            exp_maplen = maplen;
            exp_maptag = maptag;
            crc_ok = crc_good;
            #1;
            checks = checks + 1;
            if (status !== want)
                $fatal(1, "record %0s: status=%0d expected=%0d",
                       name, status, want);
        end
    endtask

    reg [15:0] step_crc;
    initial begin
        // 1. Golden record with valid CRC must validate and expose fields.
        expect_status(HREC_KAT_RAW, HREC_KAT_PROFILE, HREC_KAT_FE,
                      HREC_KAT_MAPLEN, HREC_KAT_MAPTAG, 1'b1, HREC_OK, "kat");
        if (helper !== HREC_KAT_HELPER)
            $fatal(1, "helper field mismatch");
        if (kcv_ref !== HREC_KAT_KCV)
            $fatal(1, "kcv field mismatch");
        if (kcv_ctx !== HREC_KAT_CTX)
            $fatal(1, "ctx field mismatch");
        if (generation !== HREC_KAT_GEN)
            $fatal(1, "generation mismatch");
        $display("RECORD_KAT_OK helper=%066x kcv=%056x ctx=%014x",
                 helper, kcv_ref, kcv_ctx);

        // 2. CRC-valid record with a different helper must still parse; the
        //    parser is integrity-only, same-root is enforced by the KCV gate.
        expect_status(HREC_KAT_RAW_ALT, HREC_KAT_PROFILE, HREC_KAT_FE,
                      HREC_KAT_MAPLEN, HREC_KAT_MAPTAG, 1'b1, HREC_OK,
                      "alt-valid");
        if (helper === HREC_KAT_HELPER)
            $fatal(1, "alt helper did not differ");
        $display("RECORD_ALT_OK (integrity only, not same-root)");

        // 3-8. Header/binding rejections (crc_ok = 1, so the code must be a
        //      header/binding error, not CRC).
        expect_status(with_byte(HREC_KAT_RAW, 0, 8'h00), HREC_KAT_PROFILE,
                      HREC_KAT_FE, HREC_KAT_MAPLEN, HREC_KAT_MAPTAG, 1'b1,
                      HREC_ERR_MAGIC, "magic");
        expect_status(with_byte(HREC_KAT_RAW, 4, 8'h02), HREC_KAT_PROFILE,
                      HREC_KAT_FE, HREC_KAT_MAPLEN, HREC_KAT_MAPTAG, 1'b1,
                      HREC_ERR_RECORD_VER, "recordver");
        expect_status(with_byte(HREC_KAT_RAW, 5, 8'h02), HREC_KAT_PROFILE,
                      HREC_KAT_FE, HREC_KAT_MAPLEN, HREC_KAT_MAPTAG, 1'b1,
                      HREC_ERR_PROTOCOL_VER, "protover");
        expect_status(HREC_KAT_RAW, 8'h02, HREC_KAT_FE, HREC_KAT_MAPLEN,
                      HREC_KAT_MAPTAG, 1'b1, HREC_ERR_PROFILE, "profile");
        expect_status(HREC_KAT_RAW, HREC_KAT_PROFILE, 8'h02, HREC_KAT_MAPLEN,
                      HREC_KAT_MAPTAG, 1'b1, HREC_ERR_FE_PARAM, "feparam");
        expect_status(with_byte(HREC_KAT_RAW, 12, 8'h01), HREC_KAT_PROFILE,
                      HREC_KAT_FE, HREC_KAT_MAPLEN, HREC_KAT_MAPTAG, 1'b1,
                      HREC_ERR_RESERVED, "reserved");
        expect_status(HREC_KAT_RAW, HREC_KAT_PROFILE, HREC_KAT_FE,
                      HREC_KAT_MAPLEN, 16'hBEEF, 1'b1, HREC_ERR_MAPPING,
                      "mapping");
        expect_status(with_byte(HREC_KAT_RAW, 9, 8'h01), HREC_KAT_PROFILE,
                      HREC_KAT_FE, HREC_KAT_MAPLEN, HREC_KAT_MAPTAG, 1'b1,
                      HREC_ERR_MAPPING, "mappingbyte");
        $display("RECORD_HEADER_BINDING_OK");

        // 9. Valid header but crc_ok = 0 must report CRC error, proving the
        //    CRC decision occupies the last slot in the precedence chain.
        expect_status(HREC_KAT_RAW, HREC_KAT_PROFILE, HREC_KAT_FE,
                      HREC_KAT_MAPLEN, HREC_KAT_MAPTAG, 1'b0, HREC_ERR_CRC,
                      "crc-slot");
        $display("RECORD_CRC_SLOT_OK");

        // 10. The per-byte step function must reproduce the reference CRC:
        //     the transport advances hrec_crc16_step byte by byte over bytes
        //     0..73, so its running value must equal the stored CRC.
        step_crc = 16'hFFFF;
        for (i = 0; i < HREC_OFF_CRC; i = i + 1)
            step_crc = hrec_crc16_step(step_crc, HREC_KAT_RAW[8*i +: 8]);
        if (step_crc !== hrec_crc16(HREC_KAT_RAW))
            $fatal(1, "step CRC %04x != reference %04x",
                   step_crc, hrec_crc16(HREC_KAT_RAW));
        if (step_crc !== HREC_KAT_RAW[8*HREC_OFF_CRC +: 16])
            $fatal(1, "step CRC %04x != stored %04x",
                   step_crc, HREC_KAT_RAW[8*HREC_OFF_CRC +: 16]);
        $display("RECORD_CRC_STEP_CONSISTENT crc=%04x", step_crc);

        $display("HELPER_RECORD_PARSER_PASS checks=%0d", checks);
        $finish;
    end
endmodule

`default_nettype wire
