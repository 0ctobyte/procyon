#include <cmath>
#include <chrono>
#include <random>

#include <systemc.h>

template <int cache_line_width, int sram_size, int addr_width>
SC_MODULE(Driver) {
    sc_in<bool> clk;
    sc_in<bool> n_rst;

    sc_out<bool> o_biu_en;
    sc_out<bool> o_biu_we;
    sc_out<uint32_t> o_biu_addr;
    sc_out< sc_bv<cache_line_width> > o_biu_data;
    sc_in<bool> i_biu_done;
    sc_in<bool> i_biu_busy;
    sc_in< sc_bv<cache_line_width> > i_biu_data;

    SC_CTOR(Driver) {
        SC_THREAD(process);
        sensitive << clk.pos();
        SC_THREAD(randomize);
        sensitive << clk.pos();
    }

    void trace_all(sc_trace_file *tf, const std::string& parent_name);

    ~Driver();

private:
    sc_signal< sc_uint<addr_width> > m_rnd_addr;
    sc_signal< sc_bv<cache_line_width> > m_rnd_data;

    void reset();
    void biu_read(sc_uint<addr_width> addr);
    void biu_write(sc_uint<addr_width> addr, sc_bv<cache_line_width> data);
    void randomize();
    void process();
};

template <int cache_line_width, int sram_size, int addr_width>
Driver<cache_line_width, sram_size, addr_width>::~Driver() {
}

template <int cache_line_width, int sram_size, int addr_width>
void Driver<cache_line_width, sram_size, addr_width>::trace_all(sc_trace_file *tf, const std::string& parent_name) {
    const std::string module_name = parent_name+"."+name();
    sc_trace(tf, clk, module_name+".clk");
    sc_trace(tf, n_rst, module_name+".n_rst");
    sc_trace(tf, o_biu_en, module_name+".o_biu_en");
    sc_trace(tf, o_biu_we, module_name+".o_biu_we");
    sc_trace(tf, o_biu_addr, module_name+".o_biu_addr");
    sc_trace(tf, o_biu_data, module_name+".o_biu_data");
    sc_trace(tf, i_biu_data, module_name+".i_biu_data");
    sc_trace(tf, i_biu_done, module_name+".i_biu_done");
    sc_trace(tf, i_biu_busy, module_name+".i_biu_busy");
}

template <int cache_line_width, int sram_size, int addr_width>
void Driver<cache_line_width, sram_size, addr_width>::reset() {
    o_biu_en.write(false);
    o_biu_we.write(false);
    o_biu_addr.write(0);
    o_biu_data.write(0);
}

template <int cache_line_width, int sram_size, int addr_width>
void Driver<cache_line_width, sram_size, addr_width>::biu_read(sc_uint<addr_width> addr) {
    uint32_t cache_offset_width = (uint32_t)ceil(log2(cache_line_width / 8));
    addr.range(cache_offset_width-1, 0) = 0;

    o_biu_en.write(true);
    o_biu_we.write(false);
    o_biu_addr.write(addr.to_uint());
}

template <int cache_line_width, int sram_size, int addr_width>
void Driver<cache_line_width, sram_size, addr_width>::biu_write(sc_uint<addr_width> addr, sc_bv<cache_line_width> data) {
    uint32_t cache_offset_width = (uint32_t)ceil(log2(cache_line_width / 8));
    addr.range(cache_offset_width-1, 0) = 0;

    o_biu_en.write(true);
    o_biu_we.write(true);
    o_biu_addr.write(addr.to_uint());
    o_biu_data.write(data);
}

template <int cache_line_width, int sram_size, int addr_width>
void Driver<cache_line_width, sram_size, addr_width>::randomize() {
    std::mt19937 genrand(std::chrono::system_clock::now().time_since_epoch().count());
    std::uniform_int_distribution<int> genbit(0, 1);
    std::uniform_int_distribution<int> genaddr(0, sram_size-1);

    while (true) {
        m_rnd_addr.write(genaddr(genrand));

        sc_bv<cache_line_width> data;
        for (int i = 0; i < data.length(); i++) {
            data[i] = genbit(genrand);
        }

        m_rnd_data.write(data);
        wait();
    }
}

template <int cache_line_width, int sram_size, int addr_width>
void Driver<cache_line_width, sram_size, addr_width>::process() {
    sc_uint<addr_width> addr;
    sc_bv<cache_line_width> data;

    while (true) {
        addr = m_rnd_addr.read();
        data = m_rnd_data.read();

        reset();
        while(i_biu_done.read()) wait();

        biu_write(addr, data);
        while (!i_biu_done.read()) wait();

        reset();
        while (i_biu_done.read()) wait();

        biu_read(addr);
        while (!i_biu_done.read()) wait();
    }
}
