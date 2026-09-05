#include "Vpuf_characterization_uart.h"
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

// Independent wire-level 8N1 receiver: this test does not reuse uart_rx RTL.
// The endpoint's timeout is exercised for its full 2^24-clock interval.
class Test {
public:
    static constexpr unsigned bit_clocks = TEST_CLKS_PER_BIT;
    VerilatedContext context;
    Vpuf_characterization_uart dut{single_thread(context)};
    std::vector<uint8_t> received;
    uint64_t cycles = 0;
    uint64_t starts = 0;
    uint64_t last_start_cycle = 0;

    Test() {
        dut.clk = 0;
        dut.rst_n = 0;
        dut.uart_rx_i = 1;
        dut.puf_done = 0;
        for (unsigned i = 0; i < 9; ++i) dut.puf_response[i] = 0;
        reset();
    }

    void require(bool condition, const std::string& reason) {
        if (!condition) throw std::runtime_error(reason);
    }

    void tick(uint64_t count = 1) {
        for (uint64_t i = 0; i < count; ++i) {
            dut.clk = 0;
            dut.eval();
            context.timeInc(5);
            dut.clk = 1;
            dut.eval();
            context.timeInc(5);
            ++cycles;
            if (dut.rst_n && dut.puf_start) {
                require(!previous_start, "puf_start lasted more than one clock");
                ++starts;
                last_start_cycle = cycles;
            }
            previous_start = dut.puf_start;
            if (dut.rst_n) sample_tx();
        }
    }

    void reset() {
        dut.rst_n = 0;
        dut.uart_rx_i = 1;
        dut.puf_done = 0;
        tick(8);
        receiving = false;
        previous_start = false;
        received.clear();
        require(dut.uart_tx_o == 1 && !dut.tx_active && !dut.puf_start,
                "reset did not return UART/start to idle");
        dut.rst_n = 1;
        tick(2 * bit_clocks);
    }

    void send(uint8_t byte) {
        dut.uart_rx_i = 0;
        tick(bit_clocks);
        for (unsigned bit = 0; bit < 8; ++bit) {
            dut.uart_rx_i = (byte >> bit) & 1U;
            tick(bit_clocks);
        }
        dut.uart_rx_i = 1;
        tick(bit_clocks + 4);
    }

    void expect(const std::vector<uint8_t>& expected, const std::string& label) {
        const auto deadline = (expected.size() + 1) * 12 * bit_clocks;
        for (unsigned n = 0; received.size() < expected.size() && n < deadline; ++n)
            tick();
        require(received == expected, label + ": response bytes/length mismatch");
        tick(12 * bit_clocks);
        require(received == expected && !dut.tx_active,
                label + ": unexpected trailing bytes or active transmitter");
        received.clear();
    }

    void info() {
        const auto old_starts = starts;
        send(0x00);
        expect({0x50, 0x55, 0x46, 0x01, 0x00, 0x01}, "INFO");
        require(starts == old_starts, "INFO started PUF");
    }

    void response(const std::array<uint8_t, 33>& bytes) {
        for (unsigned i = 0; i < 9; ++i) dut.puf_response[i] = 0;
        for (unsigned i = 0; i < bytes.size(); ++i)
            dut.puf_response[i / 4] |= uint32_t(bytes[i]) << (8 * (i % 4));
    }

    void raw(const std::array<uint8_t, 33>& bytes, unsigned delay = 13) {
        const auto old_starts = starts;
        send(0x70);
        require(starts == old_starts + 1, "RAW did not emit exactly one start");
        tick(delay);
        require(received.empty() && !dut.tx_active, "RAW replied before done");
        response(bytes);
        dut.puf_done = 1;
        tick();
        dut.puf_done = 0;
        // Destroy the live bus immediately: all 33 transmitted bytes must come
        // from the endpoint's response snapshot at done, including byte 32.
        std::array<uint8_t, 33> poison{};
        poison.fill(0xe7);
        response(poison);
        std::vector<uint8_t> expected{0xaa};
        expected.insert(expected.end(), bytes.begin(), bytes.end());
        expect(expected, "RAW");
        require(starts == old_starts + 1, "RAW emitted spurious second start");
    }

private:
    bool previous_start = false;
    bool receiving = false;
    unsigned remaining = 0;
    unsigned position = 0;
    uint8_t byte = 0;

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
            require(!dut.uart_tx_o, "invalid UART start bit");
        } else if (position <= 8) {
            byte |= unsigned(dut.uart_tx_o) << (position - 1);
        } else {
            require(dut.uart_tx_o, "invalid UART stop bit");
            received.push_back(byte);
            receiving = false;
        }
        ++position;
    }
};

int main(int argc, char** argv) {
    try {
        Verilated::commandArgs(argc, argv);
        Test t;
        t.info();
        t.info();
        std::cout << "PASS INFO exact 6 bytes, repeated\n";

        std::array<uint8_t, 33> bytes{};
        for (unsigned frame = 0; frame < 8; ++frame) {
            for (unsigned i = 0; i < bytes.size(); ++i)
                bytes[i] = uint8_t(frame * 33 + i);
            t.raw(bytes, frame + 1);
            t.info();
        }
        bytes.fill(0x00);
        t.raw(bytes);
        bytes.fill(0xff);
        t.raw(bytes);
        bytes.fill(0xaa);
        t.raw(bytes);
        std::cout << "PASS RAW status+33 bytes, all 256 byte values, response latch, 11 repeated requests\n";

        for (uint8_t command : {uint8_t(0x01), uint8_t(0x55), uint8_t(0xff)}) {
            const auto old_starts = t.starts;
            t.send(command);
            t.expect({0x3f}, "invalid command");
            t.require(t.starts == old_starts, "invalid command started PUF");
            t.info();
        }
        std::cout << "PASS invalid commands return exactly '?', then recover\n";

        t.send(0x70);
        const auto timeout_origin = t.last_start_cycle;
        // Verify that no early failure occurs, then cross the real counter
        // rollover. No force/deposit or shortened RTL timeout is used.
        while (t.cycles - timeout_origin < (uint64_t(1) << 24) - 1) {
            t.tick();
            t.require(t.received.empty() && !t.dut.tx_active,
                      "timeout replied too early");
        }
        t.tick(8);
        t.expect({0xff}, "PUF timeout");
        t.info();
        bytes.fill(0x5a);
        t.raw(bytes);
        std::cout << "PASS full 2^24-clock timeout, one failure byte, INFO/RAW recovery\n";

        t.send(0x70);
        t.tick(100);
        t.reset();
        t.info();
        t.raw(bytes);
        std::cout << "PASS reset while waiting for PUF, INFO/RAW recovery\n";

        t.send(0x70);
        t.response(bytes);
        t.dut.puf_done = 1;
        t.tick();
        t.dut.puf_done = 0;
        t.tick(13 * Test::bit_clocks);
        t.require(!t.received.empty(), "reset-during-TX setup produced no status byte");
        t.reset();
        t.info();
        t.raw(bytes);
        std::cout << "PASS reset during RAW transmission, INFO/RAW recovery\n";
        std::cout << "ALL PASS CLKS_PER_BIT=" << Test::bit_clocks
                  << " cycles=" << t.cycles << '\n';
        return EXIT_SUCCESS;
    } catch (const std::exception& error) {
        std::cerr << "FAIL " << error.what() << '\n';
        return EXIT_FAILURE;
    }
}
