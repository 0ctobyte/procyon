#include "Monitor.h"

Monitor::~Monitor() {
}

void Monitor::trace_all(sc_trace_file *tf, const std::string& parent_name) {
    const std::string module_name = parent_name+"."+name();
    sc_trace(tf, i_biu_en, module_name+".i_biu_en");
    sc_trace(tf, i_biu_we, module_name+".i_biu_we");
    sc_trace(tf, i_biu_addr, module_name+".i_biu_addr");
    sc_trace(tf, i_biu_data_i, module_name+".i_biu_data_i");
    sc_trace(tf, i_biu_data_o, module_name+".i_biu_data_o");
    sc_trace(tf, i_biu_done, module_name+".i_biu_done");
    sc_trace(tf, i_biu_busy, module_name+".i_biu_busy");
}

void Monitor::process() {
    sc_uint<ADDR_WIDTH> addr;
    sc_bv<CACHE_LINE_WIDTH> write_data;

    while (true) {
        while (!i_biu_en.read() || !i_biu_we.read()) wait();
        addr = i_biu_addr.read();
        write_data = i_biu_data_i.read();
        while (!i_biu_en.read() || !i_biu_done.read() || i_biu_we.read()) wait();
        printf("%s - %s = %s from %#010x\n", sc_time_stamp().to_string().c_str(), i_biu_data_o.read().to_string(SC_HEX).c_str(), write_data.to_string(SC_HEX).c_str(), addr.to_uint());
        if (write_data != i_biu_data_o.read()) sc_stop();
    }
}
