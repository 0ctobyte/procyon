/*
 * Copyright (c) 2019 Sekhar Bhattacharya
 *
 * SPDX-License-Identifier: MIT
 */

#include <iomanip>
#include <iostream>
#include <fstream>
#include <sstream>
#include <vector>
#include <cassert>

#include "utils.h"

void procyon::utils::load_hex(const std::string& filename, std::vector<uint8_t>& m_vec) {
    std::ifstream file(filename);

    for (std::string line; std::getline(file, line); ) {
        std::string hex;
        std::istringstream iss(line);
        if (!(iss >> hex)) break;
        if (hex == "//") continue;
        m_vec.push_back(std::stol(hex, NULL, 16));
    }
}

void procyon::utils::load_hex(const std::string& filename, uint8_t *m_buf, size_t size) {
    std::ifstream file(filename);
    std::string line;

    for (uint32_t cnt = 0; std::getline(file, line) && cnt < size; cnt++) {
        std::string hex;
        std::istringstream iss(line);
        if (!(iss >> hex)) break;
        if (hex == "//") continue;
        m_buf[cnt] = std::stol(hex, NULL, 16);
    }
}

void procyon::utils::load_bin(const std::string& filename, std::vector<uint8_t>& m_vec) {
    std::ifstream file(filename, std::ifstream::binary);

    for (uint8_t insn; file.read((char*)&insn, sizeof(insn)); ) {
        m_vec.push_back(insn);
    }
}

void procyon::utils::load_bin(const std::string& filename, uint8_t *m_buf, size_t size) {
    std::ifstream file(filename, std::ifstream::binary);
    uint8_t b;

    for (uint32_t cnt = 0; file.read((char*)&b, sizeof(b)) && cnt < size; cnt++) {
        m_buf[cnt] = b;
    }
}

void procyon::utils::dump_mem(const uint8_t *m_buf, size_t size, procyon::utils::dump_format_t group_fmt, procyon::utils::dump_format_t line_fmt) {
    assert(group_fmt <= line_fmt);

    for (uint32_t i = 0; i < size; i += line_fmt) {
        std::cout << std::setw(8) << std::setfill('0') << std::hex << i << ":\t";

        size_t count = line_fmt > (size-i) ? (size-i) : line_fmt;

        // Dump the bytes in hex format
        for (int j = count-1; j >= 0; j--) {
            std::cout << std::setw(2) << std::setfill('0') << std::hex << (int)m_buf[i+j];
            if ((j % group_fmt) == 0 && j != 0) std::cout << " ";
        }

        std::cout << "\t: ";

        // Interpret the bytes as characters and dump it
        for (int j = count-1; j >= 0; j--) {
            char c = (char)m_buf[i+j];
            std::cout << ((c >= 32 && c < 126) ? c : '.');
        }

        std::cout << std::endl;
    }
}

void procyon::utils::dump_mem(const std::vector<uint8_t>& m_vec, procyon::utils::dump_format_t group_fmt, procyon::utils::dump_format_t line_fmt) {
    procyon::utils::dump_mem(static_cast<const uint8_t*>(m_vec.data()), m_vec.size(), group_fmt, line_fmt);
}
