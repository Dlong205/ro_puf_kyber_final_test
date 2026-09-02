#include "Vntt_multiplier_tb.h"
#include "verilated.h"

#include <memory>

int main(int argc, char** argv) {
    const std::unique_ptr<VerilatedContext> context{new VerilatedContext};
    context->threads(1);
    context->commandArgs(argc, argv);
    const std::unique_ptr<Vntt_multiplier_tb> top{
        new Vntt_multiplier_tb{context.get(), ""}};

    while (!context->gotFinish()) {
        top->eval();
        if (!top->eventsPending()) break;
        context->time(top->nextTimeSlot());
    }
    top->final();
    return context->gotError() ? 1 : 0;
}
