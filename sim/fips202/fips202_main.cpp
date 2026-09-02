#include "Vfips202_sponge.h"
#include "verilated.h"

#include <cstdint>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <memory>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

namespace {

struct Vector {
    std::string name;
    uint8_t mode;
    std::vector<uint8_t> message;
    uint32_t output_length;
    std::vector<uint8_t> expected;
};

std::vector<uint8_t> from_hex(const std::string& text) {
    if (text == "-") {
        return {};
    }
    if ((text.size() % 2U) != 0U) {
        throw std::runtime_error("odd-length hexadecimal field");
    }

    std::vector<uint8_t> result;
    result.reserve(text.size() / 2U);
    for (std::size_t index = 0; index < text.size(); index += 2U) {
        const auto byte = static_cast<uint8_t>(
            std::stoul(text.substr(index, 2U), nullptr, 16));
        result.push_back(byte);
    }
    return result;
}

std::vector<Vector> load_vectors(const std::string& path) {
    std::ifstream input(path);
    if (!input) {
        throw std::runtime_error("cannot open vector file: " + path);
    }

    std::vector<Vector> vectors;
    std::string line;
    unsigned line_number = 0;
    while (std::getline(input, line)) {
        ++line_number;
        if (line.empty() || line.front() == '#') {
            continue;
        }

        std::vector<std::string> fields;
        std::stringstream parser(line);
        std::string field;
        while (std::getline(parser, field, '|')) {
            fields.push_back(field);
        }
        if (fields.size() != 5U) {
            throw std::runtime_error("bad vector format at line " +
                                     std::to_string(line_number));
        }

        Vector vector;
        vector.name = fields[0];
        vector.mode = static_cast<uint8_t>(std::stoul(fields[1]));
        vector.message = from_hex(fields[2]);
        vector.output_length = static_cast<uint32_t>(std::stoul(fields[3]));
        vector.expected = from_hex(fields[4]);
        if (vector.expected.size() != vector.output_length) {
            throw std::runtime_error("expected length mismatch in " + vector.name);
        }
        vectors.push_back(std::move(vector));
    }
    return vectors;
}

std::string to_hex(const std::vector<uint8_t>& bytes) {
    std::ostringstream output;
    output << std::hex << std::setfill('0');
    for (const auto byte : bytes) {
        output << std::setw(2) << static_cast<unsigned>(byte);
    }
    return output.str();
}

class Testbench {
  public:
    Testbench() : dut_(std::make_unique<Vfips202_sponge>()) {
        dut_->clk = 0;
        dut_->rst_n = 1;
        dut_->start = 0;
        dut_->mode = 0;
        dut_->msg_len_bytes = 0;
        dut_->out_len_bytes = 0;
        dut_->in_valid = 0;
        dut_->in_data = 0;
        dut_->out_ready = 0;
        dut_->eval();
    }

    ~Testbench() { dut_->final(); }

    void reset() {
        drive_idle();
        dut_->rst_n = 0;
        cycle();
        cycle();
        dut_->rst_n = 1;
        cycle();
        if (dut_->busy || dut_->out_valid) {
            throw std::runtime_error("DUT did not return idle after reset");
        }
    }

    bool run_vector(const Vector& vector, bool reset_first = true) {
        if (reset_first) {
            reset();
        }
        start(vector.mode, static_cast<uint32_t>(vector.message.size()),
              vector.output_length);

        std::size_t input_index = 0;
        std::vector<uint8_t> output;
        bool saw_last = false;
        bool completed = false;

        for (unsigned timeout = 0; timeout < 200000U; ++timeout) {
            const bool offer_input = input_index < vector.message.size() &&
                                     ((cycles_ % 5U) != 1U);
            dut_->in_valid = offer_input;
            dut_->in_data = offer_input ? vector.message[input_index] : 0;
            dut_->out_ready = ((cycles_ % 7U) != 2U);

            dut_->clk = 0;
            dut_->eval();
            const bool input_fire = dut_->in_valid && dut_->in_ready;
            const bool output_fire = dut_->out_valid && dut_->out_ready;
            const uint8_t output_byte = static_cast<uint8_t>(dut_->out_data);
            const bool output_last = dut_->out_last;

            dut_->clk = 1;
            dut_->eval();
            ++cycles_;

            if (input_fire) {
                ++input_index;
            }
            if (output_fire) {
                output.push_back(output_byte);
                if (output_last) {
                    saw_last = true;
                }
            }
            if (dut_->error) {
                std::cerr << "[FAIL] " << vector.name << ": unexpected error\n";
                return false;
            }
            if (dut_->done) {
                completed = true;
                break;
            }
        }

        drive_idle();
        if (!completed) {
            std::cerr << "[FAIL] " << vector.name << ": timeout\n";
            return false;
        }
        if (input_index != vector.message.size()) {
            std::cerr << "[FAIL] " << vector.name << ": input count mismatch\n";
            return false;
        }
        if (output != vector.expected) {
            std::cerr << "[FAIL] " << vector.name << ": digest mismatch\n"
                      << "  expected: " << to_hex(vector.expected) << "\n"
                      << "  actual:   " << to_hex(output) << "\n";
            return false;
        }
        if ((vector.output_length != 0U) && !saw_last) {
            std::cerr << "[FAIL] " << vector.name << ": out_last not observed\n";
            return false;
        }
        std::cout << "[PASS] " << vector.name << " (msg="
                  << vector.message.size() << " B, out=" << output.size()
                  << " B)\n";
        return true;
    }

    bool test_invalid_sha3_length() {
        reset();
        start(3, 0, 31);
        const bool passed = dut_->done && dut_->error && !dut_->busy;
        std::cout << (passed ? "[PASS]" : "[FAIL]")
                  << " reject_invalid_sha3_length\n";
        drive_idle();
        return passed;
    }

    bool test_mid_operation_reset(const Vector& recovery_vector) {
        reset();
        start(1, 200, 200);

        unsigned accepted = 0;
        while (accepted < 40U) {
            dut_->in_valid = 1;
            dut_->in_data = static_cast<uint8_t>((accepted * 13U) & 0xffU);
            dut_->out_ready = 1;
            dut_->clk = 0;
            dut_->eval();
            const bool fire = dut_->in_ready;
            dut_->clk = 1;
            dut_->eval();
            ++cycles_;
            if (fire) {
                ++accepted;
            }
        }

        dut_->rst_n = 0;
        drive_idle(false);
        cycle();
        cycle();
        dut_->rst_n = 1;
        cycle();
        if (dut_->busy || dut_->out_valid || dut_->done || dut_->error) {
            std::cerr << "[FAIL] mid_operation_reset: interface not idle\n";
            return false;
        }

        const bool recovered = run_vector(recovery_vector, false);
        std::cout << (recovered ? "[PASS]" : "[FAIL]")
                  << " mid_operation_reset_and_recovery\n";
        return recovered;
    }

    bool test_mid_squeeze_reset(const Vector& recovery_vector) {
        reset();
        start(1, 0, 200);

        unsigned consumed = 0;
        while (consumed < 40U) {
            dut_->in_valid = 0;
            dut_->out_ready = 1;
            dut_->clk = 0;
            dut_->eval();
            const bool fire = dut_->out_valid;
            dut_->clk = 1;
            dut_->eval();
            ++cycles_;
            if (fire) {
                ++consumed;
            }
        }

        dut_->rst_n = 0;
        drive_idle(false);
        cycle();
        cycle();
        dut_->rst_n = 1;
        cycle();
        if (dut_->busy || dut_->out_valid || dut_->done || dut_->error) {
            std::cerr << "[FAIL] mid_squeeze_reset: interface not idle\n";
            return false;
        }

        const bool recovered = run_vector(recovery_vector, false);
        std::cout << (recovered ? "[PASS]" : "[FAIL]")
                  << " mid_squeeze_reset_and_recovery\n";
        return recovered;
    }

    bool test_back_to_back(const Vector& first, const Vector& second) {
        reset();
        const bool passed = run_vector(first, false) && run_vector(second, false);
        std::cout << (passed ? "[PASS]" : "[FAIL]")
                  << " back_to_back_without_reset\n";
        return passed;
    }

  private:
    std::unique_ptr<Vfips202_sponge> dut_;
    uint64_t cycles_ = 0;

    void cycle() {
        dut_->clk = 0;
        dut_->eval();
        dut_->clk = 1;
        dut_->eval();
        ++cycles_;
    }

    void drive_idle(bool clear_reset = true) {
        dut_->start = 0;
        dut_->in_valid = 0;
        dut_->in_data = 0;
        dut_->out_ready = 0;
        if (clear_reset) {
            dut_->rst_n = 1;
        }
    }

    void start(uint8_t mode, uint32_t message_length, uint32_t output_length) {
        drive_idle();
        dut_->mode = mode;
        dut_->msg_len_bytes = message_length;
        dut_->out_len_bytes = output_length;
        dut_->start = 1;
        cycle();
        dut_->start = 0;
    }
};

}  // namespace

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    try {
        std::vector<Vector> vectors;
        if (argc > 1) {
            for (int index = 1; index < argc; ++index) {
                const auto loaded = load_vectors(argv[index]);
                vectors.insert(vectors.end(), loaded.begin(), loaded.end());
            }
        } else {
            const auto local = load_vectors("fips202_vectors.txt");
            const auto nist = load_vectors("nist_cavp_vectors.txt");
            vectors.insert(vectors.end(), local.begin(), local.end());
            vectors.insert(vectors.end(), nist.begin(), nist.end());
        }
        if (vectors.empty()) {
            throw std::runtime_error("vector set is empty");
        }

        Testbench testbench;
        unsigned failures = 0;
        for (const auto& vector : vectors) {
            if (!testbench.run_vector(vector)) {
                ++failures;
            }
        }

        if (!testbench.test_invalid_sha3_length()) {
            ++failures;
        }

        const auto recovery = vectors.at(1);  // SHA3-512("abc")
        if (!testbench.test_mid_operation_reset(recovery)) {
            ++failures;
        }

        if (!testbench.test_mid_squeeze_reset(recovery)) {
            ++failures;
        }

        if (!testbench.test_back_to_back(vectors.at(6), vectors.at(20))) {
            ++failures;
        }

        std::cout << "\nFIPS 202 regression: " << (vectors.size() + 4U - failures)
                  << "/" << (vectors.size() + 4U) << " tests passed\n";
        return failures == 0U ? 0 : 1;
    } catch (const std::exception& error) {
        std::cerr << "fatal: " << error.what() << '\n';
        return 2;
    }
}
