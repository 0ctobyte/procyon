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

#define IC_LINE_WIDTH (ic_line_size*8)

template <int ic_line_size>
SC_MODULE(InstructionFetchQueueStub) {
    sc_in<bool> clk;
    sc_in<bool> n_rst;
    sc_in<bool> o_full;
    sc_in<bool> i_alloc_en;
    sc_in<uint32_t> i_alloc_addr;
    sc_out<bool> o_fill_en;
    sc_out<uint32_t> o_fill_addr;
    sc_out<sc_bv<IC_LINE_WIDTH>> o_fill_data;

    SC_CTOR(InstructionFetchQueueStub) {
        SC_METHOD(process);
        sensitive << clk.pos();
        m_rom = std::vector<uint8_t>();
    }

    void trace_all(sc_trace_file *tf, const std::string& parent_name);
    void load_hex(const std::string& filename);
    void load_bin(const std::string& filename);
    void dump_mem(procyon::utils::dump_format_t group_fmt = procyon::utils::DUMP_FORMAT_4B, procyon::utils::dump_format_t line_fmt = procyon::utils::DUMP_FORMAT_16B);

    ~InstructionFetchQueueStub();

private:
    std::vector<uint8_t> m_rom;

    void process();
};

template <int ic_line_size>
InstructionFetchQueueStub<ic_line_size>::~InstructionFetchQueueStub() {
}

template <int ic_line_size>
void InstructionFetchQueueStub<ic_line_size>::trace_all(sc_trace_file *tf, const std::string& parent_name) {
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

template <int ic_line_size>
void InstructionFetchQueueStub<ic_line_size>::process() {
    uint32_t insn_num = i_alloc_addr.read();
    insn_num = insn_num & ~(ic_line_size-1);

    std::bitset<IC_LINE_WIDTH> bytes;

    for (int i = 0; i < ic_line_size; i++) {
        uint32_t addr = insn_num + i;
        uint8_t data = addr < m_rom.size() ? m_rom[addr] : 0x0;
        std::bitset<IC_LINE_WIDTH> byte(data);
        bytes = (byte << (i*8)) | bytes;
    }

    sc_bv<IC_LINE_WIDTH> cacheline(bytes.to_string().c_str());

    o_fill_en.write(n_rst ? i_alloc_en : 0);
    o_fill_addr.write(insn_num);
    o_fill_data.write(cacheline);
}

template <int ic_line_size>
void InstructionFetchQueueStub<ic_line_size>::load_hex(const std::string& filename) {
    procyon::utils::load_hex(filename, m_rom);
}

template <int ic_line_size>
void InstructionFetchQueueStub<ic_line_size>::load_bin(const std::string& filename) {
    procyon::utils::load_bin(filename, m_rom);
}

template <int ic_line_size>
void InstructionFetchQueueStub<ic_line_size>::dump_mem(procyon::utils::dump_format_t group_fmt, procyon::utils::dump_format_t line_fmt) {
    procyon::utils::dump_mem(m_rom, group_fmt, line_fmt);
}
