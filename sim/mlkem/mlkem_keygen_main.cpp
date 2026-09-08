#include <verilated.h>
#include "Vmlkem_keygen_probe.h"

#include <algorithm>
#include <cctype>
#include <cstdint>
#include <cstdio>
#include <fstream>
#include <map>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

struct KatVector {
    int tc_id = -1;
    std::map<std::string, std::vector<uint8_t>> fields;
};

static std::vector<uint8_t> parse_hex(const std::string& text) {
    std::vector<uint8_t> bytes;
    int high = -1;
    for (const unsigned char ch : text) {
        if (!std::isxdigit(ch)) continue;
        const int value = std::isdigit(ch) ? ch - '0'
                                           : std::tolower(ch) - 'a' + 10;
        if (high < 0)
            high = value;
        else {
            bytes.push_back(static_cast<uint8_t>((high << 4) | value));
            high = -1;
        }
    }
    return bytes;
}

static std::vector<KatVector> load_vectors(const char* path) {
    std::ifstream input(path);
    if (!input) throw std::runtime_error("cannot open vector file");
    std::vector<KatVector> vectors;
    KatVector current;
    std::string line;
    while (std::getline(input, line)) {
        const auto equals = line.find('=');
        if (equals == std::string::npos) continue;
        const std::string name = line.substr(0, equals);
        const std::string value = line.substr(equals + 1);
        if (name == "TCID") {
            if (current.tc_id >= 0) vectors.push_back(std::move(current));
            current = KatVector{};
            current.tc_id = std::stoi(value);
        } else {
            current.fields[name] = parse_hex(value);
        }
    }
    if (current.tc_id >= 0) vectors.push_back(std::move(current));
    return vectors;
}

static uint32_t load_word(const std::vector<uint8_t>& bytes, size_t offset) {
    return static_cast<uint32_t>(bytes[offset]) |
           (static_cast<uint32_t>(bytes[offset + 1]) << 8) |
           (static_cast<uint32_t>(bytes[offset + 2]) << 16) |
           (static_cast<uint32_t>(bytes[offset + 3]) << 24);
}

static void set_seed(VlWide<8>& target, const std::vector<uint8_t>& seed) {
    for (size_t word = 0; word < 8; ++word)
        target[word] = load_word(seed, 4 * word);
}

static bool compare_bytes(const char* name, int tc_id,
                          const std::vector<uint8_t>& observed,
                          const std::vector<uint8_t>& expected) {
    if (observed.size() != expected.size()) {
        std::fprintf(stderr,
                     "FAIL tcId=%d: %s length is %zu, expected %zu\n",
                     tc_id, name, observed.size(), expected.size());
        return false;
    }
    for (size_t i = 0; i < expected.size(); ++i) {
        if (observed[i] != expected[i]) {
            std::fprintf(stderr,
                         "FAIL tcId=%d: %s byte %zu is %02x, expected %02x\n",
                         tc_id, name, i, observed[i], expected[i]);
            return false;
        }
    }
    return true;
}

static int run_vector(const KatVector& vector) {
    const auto& d = vector.fields.at("D");
    const auto& z = vector.fields.at("Z");
    const auto& expected_ek = vector.fields.at("EK");
    const auto& expected_dk = vector.fields.at("DK");
    if (d.size() != 32 || z.size() != 32 || expected_ek.size() != 800 ||
        expected_dk.size() != 1632) {
        std::fprintf(stderr, "FAIL tcId=%d: malformed KeyGen vector\n",
                     vector.tc_id);
        return -1;
    }

    Vmlkem_keygen_probe dut;
    dut.clk = 0;
    dut.inspect_addr = 0;
    dut.tail_addr = 0;
    set_seed(dut.seed_d, d);
    set_seed(dut.seed_z, z);

    std::vector<uint8_t> observed_ek;
    int completed_cycle = -1;
    for (int cycle = 0; cycle < 100000; ++cycle) {
        dut.clk = 0;
        dut.eval();
        dut.clk = 1;
        dut.eval();
        if (dut.pk_valid) {
            const uint32_t word = dut.pk_word;
            for (unsigned byte = 0; byte < 4; ++byte)
                observed_ek.push_back(
                    static_cast<uint8_t>(word >> (8 * byte)));
        }
        // H(ek) is committed before state 0x22.  Stop before Decaps reuses
        // the secret-key RAM.
        if (observed_ek.size() >= 800 && dut.server_state == 0x22) {
            completed_cycle = cycle;
            break;
        }
    }

    std::vector<uint8_t> observed_dk;
    observed_dk.reserve(1632);
    auto append_pair = [&observed_dk](uint16_t a, uint16_t b) {
        observed_dk.push_back(static_cast<uint8_t>(a));
        observed_dk.push_back(static_cast<uint8_t>((a >> 8) |
                                                   ((b & 0x0f) << 4)));
        observed_dk.push_back(static_cast<uint8_t>(b >> 4));
    };
    if (completed_cycle >= 0) {
        for (unsigned addr = 0; addr < 128; ++addr) {
            dut.inspect_addr = addr;
            dut.eval();
            const uint64_t packed = dut.sk_quad;
            const uint32_t ram0 = static_cast<uint32_t>(packed & 0x00ffffffu);
            const uint32_t ram1 = static_cast<uint32_t>((packed >> 24) &
                                                        0x00ffffffu);
            append_pair(ram0 & 0x0fff, (ram0 >> 12) & 0x0fff);
            append_pair(ram1 & 0x0fff, (ram1 >> 12) & 0x0fff);
        }
        observed_dk.insert(observed_dk.end(), observed_ek.begin(),
                           observed_ek.end());
        for (unsigned word = 0; word < 16; ++word) {
            dut.tail_addr = word;
            dut.eval();
            const uint32_t value = dut.dk_tail_word;
            for (unsigned byte = 0; byte < 4; ++byte)
                observed_dk.push_back(
                    static_cast<uint8_t>(value >> (8 * byte)));
        }
    }
    dut.final();

    if (completed_cycle < 0) {
        std::fprintf(stderr, "FAIL tcId=%d: KeyGen timeout\n", vector.tc_id);
        return -1;
    }
    if (!compare_bytes("ek", vector.tc_id, observed_ek, expected_ek) ||
        !compare_bytes("dk", vector.tc_id, observed_dk, expected_dk))
        return -1;
    return completed_cycle;
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    std::vector<KatVector> vectors;
    try {
        vectors = load_vectors("mlkem512_keygen_acvp.txt");
    } catch (const std::exception& error) {
        std::fprintf(stderr, "FAIL: %s\n", error.what());
        return 2;
    }
    if (vectors.size() != 25) {
        std::fprintf(stderr, "FAIL: loaded %zu KeyGen vectors, expected 25\n",
                     vectors.size());
        return 2;
    }

    int min_cycle = 100000;
    int max_cycle = 0;
    for (const auto& vector : vectors) {
        const int cycle = run_vector(vector);
        if (cycle < 0) return 1;
        min_cycle = std::min(min_cycle, cycle);
        max_cycle = std::max(max_cycle, cycle);
    }
    std::printf("PASS: ML-KEM-512 KeyGen 25/25 NIST ACVP vectors; "
                "ek/dk bit-exact (cycles %d..%d)\n",
                min_cycle, max_cycle);
    return 0;
}
