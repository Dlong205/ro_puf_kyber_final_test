#include "Vtb_kdf_kat.h"
#include "verilated.h"
#include <memory>
#include <cstdio>

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    auto top = std::make_unique<Vtb_kdf_kat>();

    vluint64_t tick = 0;
    while (!Verilated::gotFinish() && tick < 200000) {
        top->clk = tick & 1;
        top->eval();
        tick++;
    }
    return 0;
}
