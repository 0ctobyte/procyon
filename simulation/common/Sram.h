#include <systemc.h>

#include "test_common.h"

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
        m_sram = new uint16_t[SRAM_SIZE >> 1];
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
