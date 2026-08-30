#include <verilated.h>
#include "Vaxi_wrapper_tb.h"
#include <cstdio>

vluint64_t main_time = 0;

double sc_time_stamp() { return main_time; }

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    Vaxi_wrapper_tb dut;

    // The default 32-vector regression exits early.  The larger ceiling also
    // permits +STRESS_COUNT=1024 qualification runs without rebuilding the
    // harness or accidentally timing out the C++ driver first.
    const int max_cycles = 40000000;
    for (int cycle = 0; cycle < max_cycles && !Verilated::gotFinish(); ++cycle) {
        dut.clk = 0;
        dut.eval();
        main_time += 5;
        dut.clk = 1;
        dut.eval();
        main_time += 5;
    }

    dut.final();
    if (!Verilated::gotFinish()) {
        std::fprintf(stderr, "AXI testbench timed out\n");
        return 1;
    }
    return 0;
}
