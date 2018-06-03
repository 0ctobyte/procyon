#include <systemc.h>

#include "test_common.h"

SC_MODULE(Monitor) {
    sc_in<bool> clk;
    sc_in<bool> i_cache_re;
    sc_in<bool> i_cache_we;
    sc_in<uint32_t> i_cache_tag;
    sc_in<uint32_t> i_cache_index;
    sc_in<uint32_t> i_cache_offset;
    sc_in<uint32_t> i_cache_wdata;
    sc_in<bool> i_cache_hit;
    sc_in<uint32_t> i_cache_rdata;

    SC_CTOR(Monitor) {
        SC_METHOD(process);
        sensitive << clk.pos();
        m_sram = new uint8_t[SRAM_SIZE];
    }

    void trace_all(sc_trace_file *tf, const std::string& parent_name);

    ~Monitor();

private:
    uint8_t* m_sram;

    void process();
};
