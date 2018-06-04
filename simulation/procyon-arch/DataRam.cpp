#include <iomanip>
#include <fstream>
#include <sstream>

#include "DataRam.h"

DataRam::~DataRam() {
}

void DataRam::trace_all(sc_trace_file *tf, const std::string& parent_name) {
    const std::string module_name = parent_name+"."+name();
    sc_trace(tf, i_dc_re, module_name+".i_dc_re");
    sc_trace(tf, i_dc_raddr, module_name+".i_dc_raddr");
    sc_trace(tf, o_dc_hit, module_name+".o_dc_hit");
    sc_trace(tf, o_dc_rdata, module_name+".o_dc_rdata");
    sc_trace(tf, i_sq_retire_en, module_name+".i_sq_retire_en");
    sc_trace(tf, i_sq_retire_byte_en, module_name+".i_sq_retire_byte_en");
    sc_trace(tf, i_sq_retire_addr, module_name+".i_sq_retire_addr");
    sc_trace(tf, i_sq_retire_data, module_name+".i_sq_retire_data");
    sc_trace(tf, o_sq_retire_dc_hit, module_name+".o_sq_retire_dc_hit");
    sc_trace(tf, o_sq_retire_msq_full, module_name+".o_sq_retire_msq_full");
}

void DataRam::process() {
    uint8_t *ram = (uint8_t*)m_dataram.data();
    uint32_t size = m_dataram.size() << 2;

    o_sq_retire_msq_full.write(false);
    o_sq_retire_dc_hit.write(true);
    o_dc_hit.write(i_dc_re.read());

    if (i_dc_re.read()) {
        uint32_t dc_raddr = i_dc_raddr.read();
        uint8_t byte0, byte1, byte2, byte3;
        byte0 = dc_raddr < size ? ram[dc_raddr] : 0x0;
        byte1 = (dc_raddr + 1) < size ? ram[dc_raddr+1] : 0x0;
        byte2 = (dc_raddr + 2) < size ? ram[dc_raddr+2] : 0x0;
        byte3 = (dc_raddr + 3) < size ? ram[dc_raddr+3] : 0x0;
        o_dc_rdata.write((byte3 << 24) | (byte2 << 16) | (byte1 << 8) | byte0);
    }

    if (i_sq_retire_en.read()) {
        uint32_t retire_addr = i_sq_retire_addr.read();
        uint32_t byte_en = i_sq_retire_byte_en.read();
        uint32_t data = i_sq_retire_data.read();
        if (byte_en & 0x1 && retire_addr < size) ram[retire_addr] = data & 0xff;
        if (byte_en & 0x2 && (retire_addr + 1) < size) ram[retire_addr+1] = (data >> 8) & 0xff;
        if (byte_en & 0x4 && (retire_addr + 2) < size) ram[retire_addr+2] = (data >> 16) & 0xff;
        if (byte_en & 0x8 && (retire_addr + 3) < size) ram[retire_addr+3] = (data >> 24) & 0xff;
    }
}

void DataRam::load_hex(const std::string& filename) {
    std::ifstream file(filename);

    for (std::string line; std::getline(file, line); ) {
        std::string hex;
        std::istringstream iss(line);
        if (!(iss >> hex)) break;
        if (hex == "//") continue;
        m_dataram.push_back(std::stol(hex, NULL, 16));
    }

    // for (auto const& values : m_dataram) {
    //     std::cout << std::setw(8) << std::setfill('0') << std::hex << values << std::endl;
    // }
}

void DataRam::load_bin(const std::string& filename) {
    std::ifstream file(filename, std::ifstream::binary);

    for (uint32_t insn; file.read((char*)&insn, sizeof(insn)); ) {
        m_dataram.push_back(insn);
    }

    // for (auto const& values : m_dataram) {
    //     std::cout << std::setw(8) << std::setfill('0') << std::hex << values << std::endl;
    // }
}
