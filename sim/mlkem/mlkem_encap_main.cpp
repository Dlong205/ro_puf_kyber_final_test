#include <verilated.h>
#include "Vmlkem_encap_probe.h"

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
    const auto& m = vector.fields.at("M");
    const auto& ek = vector.fields.at("EK");
    const auto& expected_c = vector.fields.at("C");
    const auto& expected_k = vector.fields.at("K");
    if (m.size() != 32 || ek.size() != 800 || expected_c.size() != 768 ||
        expected_k.size() != 32) {
        std::fprintf(stderr, "FAIL tcId=%d: malformed Encaps vector\n",
                     vector.tc_id);
        return -1;
    }

    Vmlkem_encap_probe dut;
    dut.clk = 0;
    dut.pk_valid = 0;
    dut.pk_word = 0;
    dut.ct_req = 0;
    set_seed(dut.seed_m, m);

    std::vector<uint8_t> observed_c;
    size_t pk_offset = 0;
    int completed_cycle = -1;
    for (int cycle = 0; cycle < 100000; ++cycle) {
        dut.clk = 0;
        dut.pk_valid = 0;
        dut.pk_word = 0;
        dut.ct_req = 0;
        dut.eval();
        if (dut.pk_req && pk_offset < ek.size()) {
            dut.pk_valid = 1;
            dut.pk_word = load_word(ek, pk_offset);
        }
        // Match the Server handshake: request ciphertext only in the Client's
        // transmit state so no word is drained before its length counter.
        dut.ct_req = dut.ready_c && dut.client_state == 0x23;
        dut.eval();
        dut.clk = 1;
        dut.eval();

        if (dut.pk_valid) pk_offset += 4;
        if (dut.ct_valid) {
            const uint32_t word = dut.ct_word;
            for (unsigned byte = 0; byte < 4; ++byte)
                observed_c.push_back(
                    static_cast<uint8_t>(word >> (8 * byte)));
        }
        if (dut.client_done) {
            completed_cycle = cycle;
            break;
        }
    }

    std::vector<uint8_t> observed_k(32);
    for (size_t word = 0; word < 8; ++word) {
        const uint32_t value = dut.shared_key[word];
        for (size_t byte = 0; byte < 4; ++byte)
            observed_k[4 * word + byte] =
                static_cast<uint8_t>(value >> (8 * byte));
    }
    const unsigned state = dut.client_state;
    dut.final();

    if (completed_cycle < 0) {
        std::fprintf(stderr,
                     "FAIL tcId=%d: Encaps timeout (state=%02x, pk=%zu, c=%zu)\n",
                     vector.tc_id, state, pk_offset, observed_c.size());
        return -1;
    }
    if (pk_offset != ek.size() ||
        !compare_bytes("ciphertext", vector.tc_id, observed_c, expected_c) ||
        !compare_bytes("K", vector.tc_id, observed_k, expected_k))
        return -1;
    return completed_cycle;
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    std::vector<KatVector> vectors;
    try {
        vectors = load_vectors("mlkem512_encap_acvp.txt");
    } catch (const std::exception& error) {
        std::fprintf(stderr, "FAIL: %s\n", error.what());
        return 2;
    }
    if (vectors.size() != 25) {
        std::fprintf(stderr, "FAIL: loaded %zu Encaps vectors, expected 25\n",
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
    std::printf("PASS: ML-KEM-512 Encaps 25/25 NIST ACVP vectors; "
                "ciphertext/K bit-exact (cycles %d..%d)\n",
                min_cycle, max_cycle);
    return 0;
}
