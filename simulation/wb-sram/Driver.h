#include <systemc.h>

#include "test_common.h"

SC_MODULE(Driver) {
    sc_in<bool> clk;
    sc_in<bool> n_rst;

    sc_out<bool> o_biu_en;
    sc_out<bool> o_biu_we;
    sc_out<uint32_t> o_biu_addr;
    sc_out< sc_bv<CACHE_LINE_WIDTH> > o_biu_data;
    sc_in<bool> i_biu_done;
    sc_in<bool> i_biu_busy;
    sc_in< sc_bv<CACHE_LINE_WIDTH> > i_biu_data;

    SC_CTOR(Driver) {
        SC_THREAD(process);
        sensitive << clk.pos();
        SC_THREAD(randomize);
        sensitive << clk.pos();
    }

    void trace_all(sc_trace_file *tf, const std::string& parent_name);

    ~Driver();

private:
    sc_signal< sc_uint<ADDR_WIDTH> > m_rnd_addr;
    sc_signal< sc_bv<CACHE_LINE_WIDTH> > m_rnd_data;

    void reset();
    void biu_read(sc_uint<ADDR_WIDTH> addr);
    void biu_write(sc_uint<ADDR_WIDTH> addr, sc_bv<CACHE_LINE_WIDTH> data);
    void randomize();
    void process();
};
