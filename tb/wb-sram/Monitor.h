#include <iomanip>

#include <systemc.h>

template <int cache_line_width, int addr_width>
SC_MODULE(Monitor) {
    sc_in<bool> i_biu_en;
    sc_in<bool> i_biu_we;
    sc_in<uint32_t> i_biu_addr;
    sc_in< sc_bv<cache_line_width> > i_biu_data_i;
    sc_in<bool> i_biu_done;
    sc_in<bool> i_biu_busy;
    sc_in< sc_bv<cache_line_width> > i_biu_data_o;

    SC_CTOR(Monitor) {
        SC_THREAD(process);
        sensitive << i_biu_en << i_biu_we << i_biu_addr << i_biu_data_i << i_biu_done << i_biu_data_o;
    }

    void trace_all(sc_trace_file *tf, const std::string& parent_name);

    ~Monitor();

private:
    void process();
};

template <int cache_line_width, int addr_width>
Monitor<cache_line_width, addr_width>::~Monitor() {
}

template <int cache_line_width, int addr_width>
void Monitor<cache_line_width, addr_width>::trace_all(sc_trace_file *tf, const std::string& parent_name) {
    const std::string module_name = parent_name+"."+name();
    sc_trace(tf, i_biu_en, module_name+".i_biu_en");
    sc_trace(tf, i_biu_we, module_name+".i_biu_we");
    sc_trace(tf, i_biu_addr, module_name+".i_biu_addr");
    sc_trace(tf, i_biu_data_i, module_name+".i_biu_data_i");
    sc_trace(tf, i_biu_data_o, module_name+".i_biu_data_o");
    sc_trace(tf, i_biu_done, module_name+".i_biu_done");
    sc_trace(tf, i_biu_busy, module_name+".i_biu_busy");
}

template <int cache_line_width, int addr_width>
void Monitor<cache_line_width, addr_width>::process() {
    sc_uint<addr_width> addr;
    sc_bv<cache_line_width> write_data;

    while (true) {
        while (!i_biu_en.read() || !i_biu_we.read()) wait();
        addr = i_biu_addr.read();
        write_data = i_biu_data_i.read();
        while (!i_biu_en.read() || !i_biu_done.read() || i_biu_we.read()) wait();

        std::cout << sc_time_stamp() << " - "
            << i_biu_data_o.read().to_string(SC_HEX) << " = "
            << write_data.to_string(SC_HEX) << " from "
            << std::setw(10) << std::internal << std::hex << std::showbase << std::setfill('0')
            << addr.to_uint()
            << std::endl;

        if (write_data != i_biu_data_o.read()) sc_stop();
    }
}
