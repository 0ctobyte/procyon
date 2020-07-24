/*
 * Copyright (c) 2019 Sekhar Bhattacharya
 *
 * SPDS-License-Identifier: MIT
 */

#include <systemc.h>

#include "utils.h"

template <int sram_size>
SC_MODULE(Sram) {
    sc_in<uint32_t> i_sram_addr;
    sc_in<uint32_t> i_sram_dq;
    sc_out<uint32_t> o_sram_dq;
    sc_in<bool> i_sram_ce_n;
    sc_in<bool> i_sram_we_n;
    sc_in<bool> i_sram_oe_n;
    sc_in<bool> i_sram_ub_n;
    sc_in<bool> i_sram_lb_n;

    SC_CTOR(Sram) {
        SC_METHOD(process);
        sensitive << i_sram_addr << i_sram_dq << i_sram_we_n << i_sram_ce_n << i_sram_oe_n << i_sram_ub_n << i_sram_lb_n;
        m_sram = new uint16_t[sram_size >> 1];
    }

    void trace_all(sc_trace_file *tf, const std::string& parent_name);
    void load_hex(const std::string& filename);
    void load_bin(const std::string& filename);
    void dump_mem();

    ~Sram();

private:
    uint16_t* m_sram;

    void process();
};

template <int sram_size>
Sram<sram_size>::~Sram() {
    if (m_sram != NULL) delete m_sram;
}

template <int sram_size>
void Sram<sram_size>::trace_all(sc_trace_file *tf, const std::string& parent_name) {
    const std::string module_name = parent_name+"."+name();
    sc_trace(tf, i_sram_addr, module_name+".i_sram_addr");
    sc_trace(tf, i_sram_dq, module_name+".i_sram_dq");
    sc_trace(tf, o_sram_dq, module_name+".o_sram_dq");
    sc_trace(tf, i_sram_ce_n, module_name+".i_sram_ce_n");
    sc_trace(tf, i_sram_we_n, module_name+".i_sram_we_n");
    sc_trace(tf, i_sram_oe_n, module_name+".i_sram_oe_n");
    sc_trace(tf, i_sram_ub_n, module_name+".i_sram_ub_n");
    sc_trace(tf, i_sram_lb_n, module_name+".i_sram_lb_n");
}

template <int sram_size>
void Sram<sram_size>::process() {
    uint32_t addr = i_sram_addr.read();
    bool we_n = i_sram_we_n.read();
    uint8_t sram_lb = i_sram_lb_n.read() ? 0 : m_sram[addr] & 0xff;
    uint8_t sram_ub = i_sram_ub_n.read() ? 0 : (m_sram[addr] >> 8) & 0xff;

    o_sram_dq.write((sram_ub << 8) | sram_lb);

    if (!we_n) {
        uint16_t data_in = i_sram_dq.read();
        sram_lb = i_sram_lb_n.read() ? m_sram[addr] & 0xff : data_in & 0xff;
        sram_ub = i_sram_ub_n.read() ? (m_sram[addr] >> 8) & 0xff : (data_in >> 8) & 0xff;
        m_sram[addr] = (sram_ub << 8) | sram_lb;
    }
}

template <int sram_size>
void Sram<sram_size>::load_hex(const std::string& filename) {
    procyon::utils::load_hex(filename, (uint8_t*)m_sram, sram_size);
}

template <int sram_size>
void Sram<sram_size>::load_bin(const std::string& filename) {
    procyon::utils::load_bin(filename, (uint8_t*)m_sram, sram_size);
}

template <int sram_size>
void Sram<sram_size>::dump_mem() {
    procyon::utils::dump_mem((uint8_t*)m_sram, sram_size);
}
