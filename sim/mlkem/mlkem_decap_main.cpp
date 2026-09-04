#include <verilated.h>
#include "Vmlkem_decap_probe.h"

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

struct RunResult {
    int cycle = -1;
    bool equal = false;
    std::vector<uint8_t> key;
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

static bool compare_key(int tc_id, const char* path,
                        const std::vector<uint8_t>& observed,
                        const std::vector<uint8_t>& expected) {
    for (size_t i = 0; i < expected.size(); ++i) {
        if (observed[i] != expected[i]) {
            std::fprintf(stderr,
                         "FAIL tcId=%d %s: K byte %zu is %02x, expected %02x\n",
                         tc_id, path, i, observed[i], expected[i]);
            std::fprintf(stderr, "observed=");
            for (const uint8_t byte : observed)
                std::fprintf(stderr, "%02X", byte);
            std::fprintf(stderr, "\nexpected=");
            for (const uint8_t byte : expected)
                std::fprintf(stderr, "%02X", byte);
            std::fprintf(stderr, "\n");
            return false;
        }
    }
    return true;
}

static RunResult run_server(const std::vector<uint8_t>& d,
                            const std::vector<uint8_t>& z,
                            const std::vector<uint8_t>& ciphertext) {
    Vmlkem_decap_probe dut;
    dut.clk = 0;
    dut.ct_valid = 0;
    dut.ct_word = 0;
    set_seed(dut.seed_d, d);
    set_seed(dut.seed_z, z);

    size_t ct_offset = 0;
    RunResult result;
    for (int cycle = 0; cycle < 100000; ++cycle) {
        dut.clk = 0;
        dut.ct_valid = 0;
        dut.ct_word = 0;
        dut.eval();
        if (dut.ct_req && ct_offset < ciphertext.size()) {
            dut.ct_valid = 1;
            dut.ct_word = load_word(ciphertext, ct_offset);
        }
        dut.eval();
        dut.clk = 1;
        dut.eval();
        if (dut.ct_valid) ct_offset += 4;
        if (dut.server_done && result.cycle < 0)
            result.cycle = cycle;
        // Let the edge that returns the FSM to idle settle before sampling
        // the wide K register.  The done output is combinational from the
        // state/next-state pair and may be observed during that final edge.
        if (result.cycle >= 0 && cycle >= result.cycle + 2)
            break;
    }

    result.key.resize(32);
    for (size_t word = 0; word < 8; ++word) {
        const uint32_t value = dut.shared_key[word];
        for (size_t byte = 0; byte < 4; ++byte)
            result.key[4 * word + byte] =
                static_cast<uint8_t>(value >> (8 * byte));
    }
    result.equal = dut.server_equal;
    const unsigned state = dut.server_state;
    const unsigned pk_words = dut.pk_word_count;
    dut.final();
    if (result.cycle < 0 || ct_offset != 768 || pk_words != 200) {
        std::fprintf(stderr,
                     "FAIL: Decaps transaction (cycle=%d state=%02x c=%zu ek=%u)\n",
                     result.cycle, state, ct_offset, pk_words);
        result.cycle = -1;
    }
    return result;
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    std::vector<KatVector> vectors;
    try {
        vectors = load_vectors("mlkem512_decap_ref.txt");
    } catch (const std::exception& error) {
        std::fprintf(stderr, "FAIL: %s\n", error.what());
        return 2;
    }
    if (vectors.size() != 25) {
        std::fprintf(stderr, "FAIL: loaded %zu Decaps vectors, expected 25\n",
                     vectors.size());
        return 2;
    }

    int min_cycle = 100000;
    int max_cycle = 0;
    for (const auto& vector : vectors) {
        const auto& d = vector.fields.at("D");
        const auto& z = vector.fields.at("Z");
        const auto& ciphertext = vector.fields.at("C");
        const auto& expected_k = vector.fields.at("K");
        const auto& expected_j = vector.fields.at("INVALID_J");
        if (d.size() != 32 || z.size() != 32 || ciphertext.size() != 768 ||
            expected_k.size() != 32 || expected_j.size() != 32) {
            std::fprintf(stderr, "FAIL tcId=%d: malformed Decaps vector\n",
                         vector.tc_id);
            return 2;
        }

        const RunResult valid = run_server(d, z, ciphertext);
        std::vector<uint8_t> invalid_ciphertext = ciphertext;
        invalid_ciphertext[0] ^= 1;
        const RunResult invalid = run_server(d, z, invalid_ciphertext);
        if (valid.cycle < 0 || invalid.cycle < 0) return 1;
        if (!valid.equal || invalid.equal) {
            std::fprintf(stderr,
                         "FAIL tcId=%d: compare flags valid=%d invalid=%d\n",
                         vector.tc_id, valid.equal, invalid.equal);
            return 1;
        }
        if (!compare_key(vector.tc_id, "valid", valid.key, expected_k) ||
            !compare_key(vector.tc_id, "invalid", invalid.key, expected_j))
            return 1;
        if (valid.cycle != invalid.cycle) {
            std::fprintf(stderr,
                         "FAIL tcId=%d: timing differs valid=%d invalid=%d\n",
                         vector.tc_id, valid.cycle, invalid.cycle);
            return 1;
        }
        min_cycle = std::min(min_cycle, valid.cycle);
        max_cycle = std::max(max_cycle, valid.cycle);
    }

    std::printf("PASS: ML-KEM-512 Decaps 25/25 valid and 25/25 implicit-"
                "rejection vectors; K/J exact, timing equal (cycles %d..%d)\n",
                min_cycle, max_cycle);
    return 0;
}
