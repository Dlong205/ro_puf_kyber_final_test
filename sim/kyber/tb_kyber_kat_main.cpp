#include <verilated.h>
#include <verilated_vcd_c.h>
#include "Vkat_wrapper.h"
#include <cstdio>
#include <cstdint>

vluint64_t main_time = 0;

double sc_time_stamp() {
    return main_time;
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    
    Vkat_wrapper* dut = new Vkat_wrapper;
    VerilatedVcdC* tfp = nullptr;
    
    Verilated::traceEverOn(true);
    tfp = new VerilatedVcdC;
    dut->trace(tfp, 99);
    tfp->open("waveform.vcd");
    
    printf("Starting Kyber-512 KAT Verification...\n");
    
    // Run for enough cycles to complete all KAT tests
    // The SV testbench will drive signals and check results
    int max_cycles = 50000000;
    for (int i = 0; i < max_cycles; i++) {
        dut->clk = 0;
        dut->eval();
        // tfp->dump(main_time);
        main_time += 5;
        
        dut->clk = 1;
        dut->eval();
        // tfp->dump(main_time);
        main_time += 5;
        
        // Check for finish signal from SV testbench
        if (Verilated::gotFinish()) {
            printf("Simulation finished at cycle %d\n", i);
            break;
        }
    }
    
    tfp->close();
    delete dut;
    delete tfp;
    
    printf("KAT Verification Complete\n");
    return 0;
}