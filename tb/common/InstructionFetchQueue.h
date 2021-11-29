/*
 * Copyright (c) 2019 Sekhar Bhattacharya
 *
 * SPDX-License-Identifier: MIT
 */

#include <vector>
#include <bitset>
#include <string>

#include <systemc.h>

#include "utils.h"

SC_MODULE(InstructionFetchQueue) {
    sc_in<bool> clk;
    sc_in<bool> n_rst;
    sc_in<bool> o_full;
    sc_in<bool> i_alloc_en;
    sc_in<uint32_t> i_alloc_addr;
    sc_out<bool> o_fill_en;
    sc_out<uint32_t> o_fill_addr;
    sc_out<sc_bv<256>> o_fill_data;

    SC_CTOR(InstructionFetchQueue) {
        SC_METHOD(process);
        sensitive << clk.pos();
        m_bootrom = std::vector<uint8_t>();
    }

    void trace_all(sc_trace_file *tf, const std::string& parent_name);
    void load_hex(const std::string& filename);
    void load_bin(const std::string& filename);
    void dump_mem();

    ~InstructionFetchQueue();

private:
    std::vector<uint8_t> m_bootrom;

    void process();
};

InstructionFetchQueue::~InstructionFetchQueue() {
}

void InstructionFetchQueue::trace_all(sc_trace_file *tf, const std::string& parent_name) {
    const std::string module_name = parent_name+"."+name();
    sc_trace(tf, clk, module_name+".clk");
    sc_trace(tf, n_rst, module_name+".n_rst");
    sc_trace(tf, o_full, module_name+".o_full");
    sc_trace(tf, i_alloc_en, module_name+".i_alloc_en");
    sc_trace(tf, i_alloc_addr, module_name+".i_alloc_addr");
    sc_trace(tf, o_fill_en, module_name+".o_fill_en");
    sc_trace(tf, o_fill_addr, module_name+".o_fill_addr");
    sc_trace(tf, o_fill_data, module_name+".o_fill_data");
}

void InstructionFetchQueue::process() {
    uint32_t insn_num = i_alloc_addr.read();
    insn_num = insn_num & ~(0x1f);

    std::bitset<256> bytes;

    for (int i = 0; i < 32; i++) {
        uint32_t addr = insn_num + i;
        uint8_t data = addr < m_bootrom.size() ? m_bootrom[addr] : 0x0;
        std::bitset<256> byte(data);
        bytes = (byte << (i*8)) | bytes;
    }

    sc_bv<256> cacheline(bytes.to_string().c_str());

    o_fill_en.write(i_alloc_en);
    o_fill_addr.write(insn_num);
    o_fill_data.write(cacheline);
}

void InstructionFetchQueue::load_hex(const std::string& filename) {
    procyon::utils::load_hex(filename, m_bootrom);
}

void InstructionFetchQueue::load_bin(const std::string& filename) {
    procyon::utils::load_bin(filename, m_bootrom);
}

void InstructionFetchQueue::dump_mem() {
    procyon::utils::dump_mem(m_bootrom);
}
