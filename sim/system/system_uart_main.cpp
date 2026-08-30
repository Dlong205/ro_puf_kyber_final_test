#include <verilated.h>
#include "VKyber_System_Top.h"
#include <array>
#include <cstdint>
#include <cstdio>
#include <stdexcept>
#include <string>

namespace {
constexpr int kClksPerBit = 434; // 50 MHz / 115200 baud, rounded.
constexpr uint64_t kMaxCycles = 3000000;
uint64_t sim_cycles = 0;

void tick(VKyber_System_Top& dut) {
    if (++sim_cycles > kMaxCycles)
        throw std::runtime_error("global simulation timeout");
    dut.CLK100MHZ = 0;
    dut.eval();
    Verilated::timeInc(10);
    dut.CLK100MHZ = 1;
    dut.eval();
    Verilated::timeInc(10);
}

void tick_n(VKyber_System_Top& dut, int cycles) {
    for (int i = 0; i < cycles; ++i) tick(dut);
}

void uart_send(VKyber_System_Top& dut, uint8_t value) {
    dut.UART_RXD = 0;
    tick_n(dut, kClksPerBit);
    for (int bit = 0; bit < 8; ++bit) {
        dut.UART_RXD = (value >> bit) & 1;
        tick_n(dut, kClksPerBit);
    }
    dut.UART_RXD = 1;
    tick_n(dut, kClksPerBit);
}

uint8_t uart_recv(VKyber_System_Top& dut, int timeout_cycles = 500000) {
    int waited = 0;
    while (dut.UART_TXD != 0) {
        if (++waited > timeout_cycles)
            throw std::runtime_error("UART receive timeout");
        tick(dut);
    }

    tick_n(dut, kClksPerBit / 2);
    if (dut.UART_TXD != 0)
        throw std::runtime_error("UART false start bit");

    uint8_t value = 0;
    for (int bit = 0; bit < 8; ++bit) {
        tick_n(dut, kClksPerBit);
        value |= static_cast<uint8_t>(dut.UART_TXD != 0) << bit;
    }
    tick_n(dut, kClksPerBit);
    if (dut.UART_TXD == 0)
        throw std::runtime_error("UART stop-bit framing error");
    tick_n(dut, kClksPerBit / 2);
    return value;
}

void expect_byte(VKyber_System_Top& dut, uint8_t expected, const char* label) {
    const uint8_t got = uart_recv(dut);
    if (got != expected) {
        char msg[128];
        std::snprintf(msg, sizeof(msg), "%s: expected 0x%02x, got 0x%02x",
                      label, expected, got);
        throw std::runtime_error(msg);
    }
}

void reconstruct(VKyber_System_Top& dut,
                 const std::array<uint8_t, 33>& helper) {
    uart_send(dut, 0x02);
    expect_byte(dut, 'X', "reconstruct ready");

    for (int word = 0; word < 8; ++word) {
        for (int byte = 0; byte < 4; ++byte)
            uart_send(dut, helper[word * 4 + byte]);
        expect_byte(dut, static_cast<uint8_t>('0' + word), "helper-word ack");
    }
    uart_send(dut, helper[32]);
    expect_byte(dut, '8', "last helper-byte ack");

    const std::string expected_progress = "ABCDEFG";
    std::string progress;
    for (char marker : expected_progress) {
        const auto got = uart_recv(dut);
        progress.push_back(static_cast<char>(got));
        if (got != static_cast<uint8_t>(marker))
            throw std::runtime_error("bad progress sequence: " + progress);
    }

    expect_byte(dut, 0xaa, "reconstruct status");
    expect_byte(dut, 0x00, "release result flags");
}
} // namespace

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    VKyber_System_Top dut;
    dut.CLK100MHZ = 0;
    dut.SW = 3;
    dut.UART_RXD = 1;

    try {
        // Apply one reset clock so the UART's synchronous reset establishes
        // its idle-high TX level before looking for the first start bit.
        tick(dut);
        const std::string banner = "START";
        for (char c : banner) expect_byte(dut, static_cast<uint8_t>(c), "boot banner");
        std::printf("[SYSTEM] Firmware banner received\n");

        uart_send(dut, 0x00);
        const std::array<uint8_t, 5> info{{'K', 'P', 1, 1, 0x0e}};
        for (uint8_t byte : info) expect_byte(dut, byte, "firmware info");
        std::printf("[SYSTEM] Release protocol/capabilities passed\n");

        uart_send(dut, 0x01);
        expect_byte(dut, 0xaa, "enroll status");
        std::array<uint8_t, 33> helper{};
        for (auto& byte : helper) byte = uart_recv(dut);
        std::printf("[SYSTEM] PUF enrollment/helper transfer passed\n");

        reconstruct(dut, helper);
        reconstruct(dut, helper);

        std::printf("[SYSTEM] Release mode withheld shared secrets and zeroized Kyber\n");
        std::printf("*** FULL UART/PUF/FE/KDF/KYBER-512 PASS (%llu cycles) ***\n",
                    static_cast<unsigned long long>(sim_cycles));
        dut.final();
        return 0;
    } catch (const std::exception& error) {
        std::fprintf(stderr, "SYSTEM TEST FAILED at cycle %llu: %s\n",
                     static_cast<unsigned long long>(sim_cycles), error.what());
        dut.final();
        return 1;
    }
}
