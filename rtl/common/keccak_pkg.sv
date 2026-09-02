`timescale 1ns / 1ps

package keccak_pkg;

    // Keccak-f[1600] parameters
    parameter int STATE_WIDTH = 1600;
    parameter int RATE_SHA3_256 = 1088;
    parameter int RATE_SHA3_512 = 576;
    parameter int RATE_SHAKE_128 = 1344;
    parameter int RATE_SHAKE_256 = 1088;
    parameter int CAPACITY_SHA3_256 = 512;
    parameter int CAPACITY_SHA3_512 = 1024;
    parameter int CAPACITY_SHAKE_128 = 256;
    parameter int CAPACITY_SHAKE_256 = 512;
    
    // Canonical mode encoding used by sha3_shake_core and fips202_sponge.
    // Keep this mapping stable: legacy Kyber adapters depend on it.
    typedef enum logic [1:0] {
        MODE_SHA3_512  = 2'b00,
        MODE_SHAKE_256 = 2'b01,
        MODE_SHAKE_128 = 2'b10,
        MODE_SHA3_256  = 2'b11
    } mode_t;
    
    // Domain separators
    parameter logic [7:0] DOMAIN_SHA3    = 8'h06;  // 00000110
    parameter logic [7:0] DOMAIN_SHAKE   = 8'h1F;  // 00011111
    
    // Round constants (24 rounds)
    parameter logic [63:0] RC [0:23] = '{
        64'h0000000000000001,
        64'h0000000000008082,
        64'h800000000000808a,
        64'h8000000080008000,
        64'h000000000000808b,
        64'h0000000080000001,
        64'h8000000080008081,
        64'h8000000000008009,
        64'h000000000000008a,
        64'h0000000000000088,
        64'h0000000080008009,
        64'h000000008000000a,
        64'h000000008000808b,
        64'h800000000000008b,
        64'h8000000000008089,
        64'h8000000000008003,
        64'h8000000000008002,
        64'h8000000000000080,
        64'h000000000000800a,
        64'h800000008000000a,
        64'h8000000080008081,
        64'h8000000000008080,
        64'h0000000080000001,
        64'h8000000080008008
    };
    
    // Rotation constants for rho step
    parameter int RHO_ROT [0:24] = '{
        0, 1, 62, 28, 27,
        36, 44, 6, 55, 20,
        3, 10, 43, 25, 39,
        41, 45, 15, 21, 8,
        18, 2, 61, 56, 14
    };
    
    // Pi step mapping
    parameter int PI_MAP [0:24] = '{
        0, 6, 12, 18, 24,
        3, 9, 10, 16, 22,
        1, 7, 13, 19, 20,
        4, 5, 11, 17, 23,
        2, 8, 14, 15, 21
    };

    // Helper functions
    function automatic logic [STATE_WIDTH-1:0] rot_left(input logic [STATE_WIDTH-1:0] val, input int shift);
        return (val << shift) | (val >> (64 - shift));
    endfunction

    function automatic logic [63:0] rot64_left(input logic [63:0] val, input int shift);
        return (val << shift) | (val >> (64 - shift));
    endfunction

    // Get rate for mode (in bits)
    function automatic int get_rate(input mode_t mode);
        case (mode)
            MODE_SHA3_256:  return 1088;
            MODE_SHA3_512:  return 576;
            MODE_SHAKE_128: return 1344;
            MODE_SHAKE_256: return 1088;
            default:        return 1344;
        endcase
    endfunction

    // Get domain separator for mode
    function automatic logic [7:0] get_domain(input mode_t mode);
        case (mode)
            MODE_SHA3_256,
            MODE_SHA3_512:  return 8'h06;
            MODE_SHAKE_128,
            MODE_SHAKE_256: return 8'h1F;
            default:        return 8'h1F;
        endcase
    endfunction

    // Get capacity for mode
    function automatic int get_capacity(input mode_t mode);
        case (mode)
            MODE_SHA3_256:  return 512;
            MODE_SHA3_512:  return 1024;
            MODE_SHAKE_128: return 256;
            MODE_SHAKE_256: return 512;
            default:        return 256;
        endcase
    endfunction

    // Check if mode is SHAKE (variable output)
    function automatic logic is_shake(input mode_t mode);
        return (mode == MODE_SHAKE_128) || (mode == MODE_SHAKE_256);
    endfunction

    // Check if mode is SHA3 (fixed output)
    function automatic logic is_sha3(input mode_t mode);
        return (mode == MODE_SHA3_256) || (mode == MODE_SHA3_512);
    endfunction

    // Get fixed output length in bits for SHA3 modes
    function automatic int get_sha3_output_bits(input mode_t mode);
        case (mode)
            MODE_SHA3_256: return 256;
            MODE_SHA3_512: return 512;
            default:       return 0;
        endcase
    endfunction

endpackage
