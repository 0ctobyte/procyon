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

void procyon::utils::dump_mem(const std::vector<uint8_t>& m_vec) {
    for (uint32_t i = 0; i < m_vec.size(); i++) {
        std::cout << std::setw(2) << std::setfill('0') << std::hex << (int)m_vec[i] << std::endl;
    }
}

void procyon::utils::dump_mem(uint8_t *m_buf, size_t size) {
    for (uint32_t i = 0; i < size; i++) {
        std::cout << std::setw(2) << std::setfill('0') << std::hex << (int)m_buf[i] << std::endl;
    }
}
