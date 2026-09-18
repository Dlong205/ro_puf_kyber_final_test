#include "Vpuf_allpairs_uart.h"
#include "verilated.h"

#include <array>
#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

static VerilatedContext* single_thread(VerilatedContext& context) {
    context.threads(1);
    return &context;
}

class Test {
public:
    static constexpr unsigned bit_clocks = TEST_CLKS_PER_BIT;
    VerilatedContext context;
    Vpuf_allpairs_uart dut{single_thread(context)};
    std::vector<uint8_t> received;
    uint64_t starts = 0;

    Test() {
        dut.clk = 0;
        dut.rst_n = 0;
        dut.uart_rx_i = 1;
        dut.puf_done = 0;
        dut.telemetry_valid = 0;
        dut.telemetry_index = 0;
        dut.telemetry_pair_a = 0;
        dut.telemetry_pair_b = 0;
        dut.telemetry_count0 = 0;
        dut.telemetry_count1 = 0;
        dut.telemetry_winner = 0;
        dut.mmcm_locked = 1;
        clear_response();
        tick(8);
        dut.rst_n = 1;
        tick(2 * bit_clocks);
    }

    void require(bool condition, const std::string& reason) {
        if (!condition) throw std::runtime_error(reason);
    }

    void tick(uint64_t count = 1) {
        for (uint64_t n = 0; n < count; ++n) {
            dut.clk = 0;
            dut.eval();
            context.timeInc(5);
            dut.clk = 1;
            dut.eval();
            context.timeInc(5);
            if (dut.rst_n && dut.puf_start) {
                require(!previous_start, "puf_start exceeded one clock");
                ++starts;
            }
            previous_start = dut.puf_start;
            if (dut.rst_n) sample_tx();
        }
    }

    void send(uint8_t value) {
        dut.uart_rx_i = 0;
        tick(bit_clocks);
        for (unsigned bit = 0; bit < 8; ++bit) {
            dut.uart_rx_i = (value >> bit) & 1U;
            tick(bit_clocks);
        }
        dut.uart_rx_i = 1;
        tick(bit_clocks + 4);
    }

    void expect(const std::vector<uint8_t>& expected, const std::string& label) {
        const uint64_t deadline = (expected.size() + 1) * 12 * bit_clocks;
        for (uint64_t n = 0; received.size() < expected.size() && n < deadline; ++n)
            tick();
        require(received == expected, label + ": byte stream mismatch");
        tick(12 * bit_clocks);
        require(received == expected && !dut.tx_active,
                label + ": unexpected trailing byte");
        received.clear();
    }

    void info() {
        const auto old_starts = starts;
        send(0x00);
        expect({0x50, 0x55, 0x46, 0x02, 0x00, 0x07}, "INFO");
        require(starts == old_starts, "INFO started the PUF");
    }

    static void append_u16(std::vector<uint8_t>& out, uint16_t value) {
        out.push_back(uint8_t(value));
        out.push_back(uint8_t(value >> 8));
    }

    static void append_u32(std::vector<uint8_t>& out, uint32_t value) {
        for (unsigned shift = 0; shift < 32; shift += 8)
            out.push_back(uint8_t(value >> shift));
    }

    void margin() {
        const auto old_starts = starts;
        send(0x71);
        require(starts == old_starts + 1, "MARGIN did not start exactly once");
        std::vector<uint8_t> expected{0xaa};
        unsigned a = 0;
        unsigned b = 1;
        for (unsigned index = 0; index < 496; ++index) {
            const uint32_t count0 = 1000 + index * 3;
            const uint32_t count1 = 1800 + index * 5;
            const uint32_t margin = count1 - count0;
            dut.telemetry_index = index;
            dut.telemetry_pair_a = a;
            dut.telemetry_pair_b = b;
            dut.telemetry_count0 = count0;
            dut.telemetry_count1 = count1;
            dut.telemetry_winner = 1;
            dut.telemetry_valid = 1;
            dut.puf_done = index == 495;
            tick();
            dut.telemetry_valid = 0;
            dut.puf_done = 0;

            append_u16(expected, index);
            expected.push_back(uint8_t(a));
            expected.push_back(uint8_t((1U << 5) | b));
            append_u32(expected, count0);
            append_u32(expected, count1);
            append_u32(expected, margin);

            if (b == 31) {
                ++a;
                b = a + 1;
            } else {
                ++b;
            }
        }
        expect(expected, "MARGIN");
        require(starts == old_starts + 1, "MARGIN emitted an extra start");
    }

    void raw() {
        std::array<uint8_t, 62> bytes{};
        clear_response();
        for (unsigned i = 0; i < bytes.size(); ++i) {
            bytes[i] = uint8_t(i * 37 + 11);
            dut.puf_response[i / 4] |= uint32_t(bytes[i]) << (8 * (i % 4));
        }
        const auto old_starts = starts;
        send(0x70);
        require(starts == old_starts + 1, "RAW did not start exactly once");
        tick(7);
        dut.puf_done = 1;
        tick();
        dut.puf_done = 0;
        clear_response();
        std::vector<uint8_t> expected{0xaa};
        expected.insert(expected.end(), bytes.begin(), bytes.end());
        expect(expected, "RAW");
    }

private:
    bool previous_start = false;
    bool receiving = false;
    unsigned remaining = 0;
    unsigned position = 0;
    uint8_t byte = 0;

    void clear_response() {
        for (unsigned word = 0; word < 16; ++word)
            dut.puf_response[word] = 0;
    }

    void sample_tx() {
        if (!receiving) {
            if (!dut.uart_tx_o) {
                receiving = true;
                remaining = bit_clocks / 2;
                position = 0;
                byte = 0;
            }
            return;
        }
        if (--remaining != 0) return;
        remaining = bit_clocks;
        if (position == 0) {
            require(!dut.uart_tx_o, "bad UART start bit");
        } else if (position <= 8) {
            byte |= unsigned(dut.uart_tx_o) << (position - 1);
        } else {
            require(dut.uart_tx_o, "bad UART stop bit");
            received.push_back(byte);
            receiving = false;
        }
        ++position;
    }
};

int main(int argc, char** argv) {
    try {
        Verilated::commandArgs(argc, argv);
        Test test;
        test.info();
        test.info();
        std::cout << "PASS INFO protocol 2.0 exact/repeated\n";
        test.margin();
        test.info();
        std::cout << "PASS MARGIN 496 coherent indexed pairs/final-record race\n";
        test.raw();
        std::cout << "PASS RAW exact 62-byte snapshot\n";
        const auto old_starts = test.starts;
        test.send(0x55);
        test.expect({0x3f}, "invalid command");
        test.require(test.starts == old_starts, "invalid command started PUF");
        test.info();
        std::cout << "PASS invalid command recovery\n";
        std::cout << "ALL ALL-PAIRS UART TESTS PASSED\n";
        return EXIT_SUCCESS;
    } catch (const std::exception& error) {
        std::cerr << "FAIL " << error.what() << '\n';
        return EXIT_FAILURE;
    }
}
