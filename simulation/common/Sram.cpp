#include <iomanip>
#include <fstream>
#include <sstream>

#include "Sram.h"

Sram::~Sram() {
    if (m_sram != NULL) delete m_sram;
}

void Sram::trace_all(sc_trace_file *tf, const std::string& parent_name) {
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

void Sram::process() {
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

void Sram::load_hex(const std::string& filename) {
    std::ifstream file(filename);

    uint32_t a = 0;
    for (std::string line; std::getline(file, line) && a < SRAM_SIZE; ) {
        std::string hex;
        std::istringstream iss(line);
        if (!(iss >> hex)) break;
        if (hex == "//") continue;
        int j = a >> 1;
        uint8_t h = std::stol(hex, NULL, 16);
        uint16_t x = (h << 8) | (m_sram[j] & 0xff);
        uint16_t y = (m_sram[j] & 0xff00) | h;
        m_sram[j] = (a & 1) ? x : y;
        a++;
    }

    // for (uint32_t i = 0; i < (SRAM_SIZE >> 1); i++) {
    //     std::cout << std::setw(4) << std::setfill('0') << std::hex << m_sram[i] << std::endl;
    // }
}

void Sram::load_bin(const std::string& filename) {
    std::ifstream file(filename, std::ifstream::binary);

    uint32_t a = 0;
    for (uint16_t b; file.read((char*)&b, sizeof(b)) && a < (SRAM_SIZE >> 1); ) {
        m_sram[a] = b;
        a++;
    }

    // for (uint32_t i = 0; i < (SRAM_SIZE >> 1); i++) {
    //     std::cout << std::setw(4) << std::setfill('0') << std::hex << m_sram[i] << std::endl;
    // }
}
