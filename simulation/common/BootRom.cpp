#include <iomanip>
#include <fstream>
#include <sstream>

#include "BootRom.h"

BootRom::~BootRom() {
}

void BootRom::trace_all(sc_trace_file *tf, const std::string& parent_name) {
    const std::string module_name = parent_name+"."+name();
    sc_trace(tf, i_ic_en, module_name+".i_ic_en");
    sc_trace(tf, i_ic_pc, module_name+".i_ic_pc");
    sc_trace(tf, o_ic_valid, module_name+".o_ic_valid");
    sc_trace(tf, o_ic_insn, module_name+".o_ic_insn");
}

void BootRom::process() {
    uint32_t insn_num = i_ic_pc.read() >> 2;
    o_ic_valid.write(i_ic_en.read() && insn_num < m_bootrom.size());
    o_ic_insn.write(m_bootrom[insn_num]);
}

void BootRom::load_hex(const std::string& filename) {
    std::ifstream file(filename);

    for (std::string line; std::getline(file, line); ) {
        std::string hex;
        std::istringstream iss(line);
        if (!(iss >> hex)) break;
        if (hex == "//") continue;
        m_bootrom.push_back(std::stol(hex, NULL, 16));
    }

    // for (auto const& values : m_bootrom) {
    //     std::cout << std::setw(8) << std::setfill('0') << std::hex << values << std::endl;
    // }
}

void BootRom::load_bin(const std::string& filename) {
    std::ifstream file(filename, std::ifstream::binary);

    for (uint32_t insn; file.read((char*)&insn, sizeof(insn)); ) {
        m_bootrom.push_back(insn);
    }

    // for (auto const& values : m_bootrom) {
    //     std::cout << std::setw(8) << std::setfill('0') << std::hex << values << std::endl;
    // }
}