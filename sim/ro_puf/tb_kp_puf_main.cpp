#include "Vtb_kp_puf_simple.h"
#include "verilated.h"

namespace {
constexpr vluint64_t kHalfPeriodNs = 5;
constexpr vluint64_t kSimulationTimeoutNs = 1'000'000;
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    Vtb_kp_puf_simple* top = new Vtb_kp_puf_simple();

    top->clk = 0;
    top->eval();

    while (!Verilated::gotFinish() &&
           Verilated::time() < kSimulationTimeoutNs) {
        top->clk = !top->clk;
        top->eval();
        Verilated::timeInc(kHalfPeriodNs);
    }

    const bool timed_out = !Verilated::gotFinish();
    if (timed_out)
        VL_PRINTF("FAIL: RO-PUF simulation timed out at %llu ns\n",
                  static_cast<unsigned long long>(Verilated::time()));

    top->final();
    delete top;
    return timed_out ? 1 : 0;
}
