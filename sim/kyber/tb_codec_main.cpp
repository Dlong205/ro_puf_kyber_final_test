#include <verilated.h>
#include "Vcodec_roundtrip_tb.h"
#include <cstdio>

vluint64_t main_time = 0;
double sc_time_stamp() { return main_time; }

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    Vcodec_roundtrip_tb dut;
    for (int cycle = 0; cycle < 200000 && !Verilated::gotFinish(); ++cycle) {
        dut.clk = 0;
        dut.eval();
        main_time += 5;
        dut.clk = 1;
        dut.eval();
        main_time += 5;
    }
    dut.final();
    if (!Verilated::gotFinish()) {
        std::fprintf(stderr, "Codec round-trip timed out\n");
        return 1;
    }
    return 0;
}
