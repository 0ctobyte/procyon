#include <iomanip>

#include "Monitor.h"

Monitor::~Monitor() {
    if (m_sram != NULL) delete m_sram;
}

void Monitor::trace_all(sc_trace_file *tf, const std::string& parent_name) {
    const std::string module_name = parent_name+"."+name();
    sc_trace(tf, clk, module_name+".clk");
    sc_trace(tf, i_cache_re, module_name+".i_cache_re");
    sc_trace(tf, i_cache_we, module_name+".i_cache_we");
    sc_trace(tf, i_cache_tag, module_name+".i_cache_tag");
    sc_trace(tf, i_cache_index, module_name+".i_cache_index");
    sc_trace(tf, i_cache_offset, module_name+".i_cache_offset");
    sc_trace(tf, i_cache_wdata, module_name+".i_cache_wdata");
    sc_trace(tf, i_cache_hit, module_name+".i_cache_hit");
    sc_trace(tf, i_cache_rdata, module_name+".i_cache_rdata");
}

void Monitor::process() {
    sc_uint<ADDR_WIDTH> addr(0);
    addr.range(ADDR_WIDTH-1, ADDR_WIDTH-CACHE_TAG_WIDTH) = i_cache_tag;
    addr.range(CACHE_INDEX_WIDTH+CACHE_OFFSET_WIDTH-1, CACHE_OFFSET_WIDTH) = i_cache_index;
    addr.range(CACHE_OFFSET_WIDTH-1, 0) = i_cache_offset;
    sc_uint<ADDR_WIDTH> addr1 = addr + 1;

    if (i_cache_we.read() && i_cache_hit.read()) {
        std::cout << sc_time_stamp() << " - STORE: "
            << std::setw(6) << std::internal << std::hex << std::showbase << std::setfill('0')
            << i_cache_wdata.read() << " to "
            << std::setw(10) << std::internal << std::hex << std::showbase << std::setfill('0')
            << addr.to_uint()
            << std::endl;

        m_sram[addr.to_uint()] = i_cache_wdata.read() & 0xff;
        if (addr1.to_uint() != 0 && addr1.to_uint() % CACHE_LINE_SIZE != 0) {
            m_sram[addr1.to_uint()] = (i_cache_wdata.read() >> 8) & 0xff;
        }
    }

    if (i_cache_re.read() && i_cache_hit.read()) {
        uint16_t rdata = (addr1.to_uint() != 0 && addr1.to_uint() % CACHE_LINE_SIZE != 0 ? m_sram[addr1.to_uint()] << 8 : 0) | m_sram[addr.to_uint()];

        std::cout << sc_time_stamp() << " - LOAD: "
            << std::setw(6) << std::internal << std::hex << std::showbase << std::setfill('0')
            << i_cache_rdata.read() << " = "
            << std::setw(6) << std::internal << std::hex << std::showbase << std::setfill('0')
            << rdata << " from "
            << std::setw(10) << std::internal << std::hex << std::showbase << std::setfill('0')
            << addr.to_uint()
            << std::endl;

        if (i_cache_rdata.read() != rdata) sc_stop();
    }
}
