//------------------------------------------------------------------------------
// keccak_pkg.vh - Verilog header for Keccak SHA-3
// Converted from VHDL package KECCAK_pkg
//
// Include this file inside any module that needs the rotl function.
// Usage: `include "keccak_pkg.vh"
//
// Type mappings from VHDL:
//   blk_array(x,y)  ->  wire [1599:0], element A(x,y) = bits [64*(5*x+y)+63 : 64*(5*x+y)]
//   state_t(i)      ->  wire [319:0],  element C(i)   = bits [64*i+63 : 64*i]
//   chi_1_blk(i)    ->  wire [575:0],  element(i)     = bits [64*i+63 : 64*i]
//   chi_2_blk(i)    ->  wire [511:0],  element(i)     = bits [64*i+63 : 64*i]
//   converse_blk(S) ->  identity (same bit layout as 1600-bit string)
//   converse_str(A) ->  identity (same bit layout as 1600-bit string)
//------------------------------------------------------------------------------

// rotl function - rotate left a 64-bit value by 'offset' positions
// Equivalent to VHDL: value((63-offset) downto 0) & value(63 downto 64-offset)
function [63:0] rotl;
    input [63:0] value;
    input integer offset;
    begin
        rotl = (value << offset) | (value >> (64 - offset));
    end
endfunction
