#include <verilated.h>
#include "Vmlkem_decap_probe.h"

#include <cctype>
#include <cstdint>
#include <cstdio>
#include <fstream>
#include <map>
#include <string>
#include <vector>

static std::vector<uint8_t> parse_hex(const std::string& text) {
    std::vector<uint8_t> bytes;
    int high = -1;
    for (unsigned char ch : text) {
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

static std::map<std::string, std::vector<uint8_t>> load_vector(
    const char* path) {
    std::ifstream input(path);
    std::map<std::string, std::string> encoded;
    std::string current;
    std::string line;
    while (std::getline(input, line)) {
        const auto equals = line.find('=');
        if (equals != std::string::npos) {
            current = line.substr(0, equals);
            encoded[current] += line.substr(equals + 1);
        } else if (!current.empty()) {
            encoded[current] += line;
        }
    }
    std::map<std::string, std::vector<uint8_t>> result;
    for (const auto& item : encoded)
        result[item.first] = parse_hex(item.second);
    return result;
}

static uint32_t load_word(const std::vector<uint8_t>& bytes, size_t offset) {
    return static_cast<uint32_t>(bytes[offset]) |
           (static_cast<uint32_t>(bytes[offset + 1]) << 8) |
           (static_cast<uint32_t>(bytes[offset + 2]) << 16) |
           (static_cast<uint32_t>(bytes[offset + 3]) << 24);
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    const auto vector = load_vector("mlkem512_decap_ref_tc1.txt");
    const auto& ciphertext = vector.at("C");
    const auto& expected_k = vector.at("K");
    if (ciphertext.size() != 768 || expected_k.size() != 32) {
        std::fprintf(stderr, "FAIL: malformed decap vector (c=%zu, k=%zu)\n",
                     ciphertext.size(), expected_k.size());
        return 2;
    }

    Vmlkem_decap_probe dut;
    size_t ct_offset = 0;
    int completed_cycle = -1;

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
        if (dut.ct_valid)
            ct_offset += 4;
        if (dut.server_done) {
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
    const unsigned state = dut.server_state;
    const bool equal = dut.server_equal;
    const unsigned pk_words = dut.pk_word_count;
    dut.final();

    if (completed_cycle < 0) {
        std::fprintf(stderr,
                     "FAIL: decapsulation timeout (state=%02x, c=%zu bytes)\n",
                     state, ct_offset);
        return 1;
    }
    if (ct_offset != ciphertext.size() || pk_words != 200) {
        std::fprintf(stderr,
                     "FAIL: handshake lengths are c=%zu/768 bytes, ek=%u/200 words\n",
                     ct_offset, pk_words);
        return 1;
    }
    if (!equal) {
        std::fprintf(stderr, "FAIL: reference ciphertext was rejected\n");
        return 1;
    }
    for (size_t i = 0; i < expected_k.size(); ++i) {
        if (observed_k[i] != expected_k[i]) {
            std::fprintf(stderr,
                         "FAIL: decaps K byte %zu is %02x, expected %02x\n",
                         i, observed_k[i], expected_k[i]);
            return 1;
        }
    }

    std::printf("PASS: ML-KEM-512 Decaps matches independent reference "
                "(768-byte c, 32-byte K, cycle %d)\n", completed_cycle);
    return 0;
}
