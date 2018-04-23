#include <systemc.h>

#include "test_common.h"

SC_MODULE(Monitor) {
    sc_in<bool> i_biu_en;
    sc_in<bool> i_biu_we;
    sc_in<uint32_t> i_biu_addr;
    sc_in< sc_bv<CACHE_LINE_WIDTH> > i_biu_data_i;
    sc_in<bool> i_biu_done;
    sc_in<bool> i_biu_busy;
    sc_in< sc_bv<CACHE_LINE_WIDTH> > i_biu_data_o;

    SC_CTOR(Monitor) {
        SC_THREAD(process);
        sensitive << i_biu_en << i_biu_we << i_biu_addr << i_biu_data_i << i_biu_done << i_biu_data_o;
    }

    void trace_all(sc_trace_file *tf, const std::string& parent_name);

    ~Monitor();

private:
    void process();
};
