#include "BootRom.h"
#include "utils.h"

BootRom::~BootRom() {
}

void BootRom::trace_all(sc_trace_file *tf, const std::string& parent_name) {
    const std::string module_name = parent_name+"."+name();
    sc_trace(tf, clk, module_name+".clk");
    sc_trace(tf, i_ic_en, module_name+".i_ic_en");
    sc_trace(tf, i_ic_pc, module_name+".i_ic_pc");
    sc_trace(tf, o_ic_valid, module_name+".o_ic_valid");
    sc_trace(tf, o_ic_insn, module_name+".o_ic_insn");
}

void BootRom::process() {
    uint32_t insn_num = i_ic_pc.read();
    uint8_t byte0 = insn_num < m_bootrom.size() ? m_bootrom[insn_num] : 0x0;
    uint8_t byte1 = (insn_num + 1) < m_bootrom.size() ? m_bootrom[insn_num + 1] : 0x0;
    uint8_t byte2 = (insn_num + 2) < m_bootrom.size() ? m_bootrom[insn_num + 2] : 0x0;
    uint8_t byte3 = (insn_num + 3) < m_bootrom.size() ? m_bootrom[insn_num + 3] : 0x0;

    o_ic_valid.write(i_ic_en.read() && insn_num < m_bootrom.size());
    o_ic_insn.write((byte3 << 24) | (byte2 << 16) | (byte1 << 8) | byte0);
}

void BootRom::load_hex(const std::string& filename) {
    procyon::utils::load_hex(filename, m_bootrom);
}

void BootRom::load_bin(const std::string& filename) {
    procyon::utils::load_bin(filename, m_bootrom);
}

void BootRom::dump_mem() {
    procyon::utils::dump_mem(m_bootrom);
}
