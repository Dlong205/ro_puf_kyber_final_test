`timescale 1ns / 1ps
`default_nettype none

// Phase-1 helper-record enforcement parser.
//
// Pure combinational validator for the 76-byte record defined by
// scripts/helper_record_spec.py (single source of truth shared by RTL,
// firmware and host).  The record must be rejected here, before any BCH
// decode or KDF work, when the magic, version, profile, FE parameter,
// reserved byte, mapping binding or CRC-16 is wrong.
//
// rtl/top/edge_puf_mlkem_core.sv only receives helper data once this module
// reports HREC_OK, so a corrupted or foreign record can never reach the
// fuzzy extractor.  The CRC is a transport/storage integrity check only; it
// is not authentication against an attacker who can replace the record.
module helper_record_parse (
    input  wire [8*HREC_BYTES-1:0] raw,          // byte 0 in raw[7:0]
    input  wire [7:0]              expected_profile,
    input  wire [7:0]              expected_fe_param,
    input  wire [7:0]              expected_mapping_len_bytes,
    input  wire [15:0]             expected_mapping_tag,
    input  wire                    crc_ok,       // running CRC vs stored CRC
    output reg  [3:0]              status,
    output reg  [263:0]            helper,
    output reg  [223:0]            kcv_ref,
    output reg  [55:0]             kcv_ctx,
    output reg  [7:0]              generation
);
    `include "helper_record_spec.vh"

    function automatic [7:0] byte_at;
        input integer index;
        begin
            byte_at = raw[8*index +: 8];
        end
    endfunction

    wire [31:0] magic         = raw[8*0  +: 32];
    wire [7:0]  record_version = byte_at(4);
    wire [7:0]  proto_version  = byte_at(5);
    wire [7:0]  profile        = byte_at(6);
    wire [7:0]  fe_param       = byte_at(7);
    wire [7:0]  mapping_len_bytes = byte_at(8);
    wire [15:0] mapping_tag    = raw[8*9 +: 16];
    wire [7:0]  generation_r   = byte_at(11);
    wire [7:0]  reserved       = byte_at(12);

    always @* begin
        helper     = raw[8*HREC_OFF_HELPER +: 264];
        kcv_ref    = raw[8*HREC_OFF_KCV +: 224];
        generation = generation_r;
        kcv_ctx    = {generation_r, mapping_tag, fe_param, profile,
                      proto_version, record_version};

        if (magic != HREC_MAGIC)
            status = HREC_ERR_MAGIC;
        else if (record_version != HREC_RECORD_VERSION)
            status = HREC_ERR_RECORD_VER;
        else if (proto_version != HREC_PROTOCOL_VERSION)
            status = HREC_ERR_PROTOCOL_VER;
        else if (profile != expected_profile)
            status = HREC_ERR_PROFILE;
        else if (fe_param != expected_fe_param)
            status = HREC_ERR_FE_PARAM;
        else if (reserved != 8'h00)
            status = HREC_ERR_RESERVED;
        else if (mapping_len_bytes != expected_mapping_len_bytes ||
                 mapping_tag != expected_mapping_tag)
            status = HREC_ERR_MAPPING;
        else if (!crc_ok)
            status = HREC_ERR_CRC;
        else
            status = HREC_OK;
    end
endmodule

`default_nettype wire
