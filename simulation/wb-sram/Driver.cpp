#include <cmath>
#include <chrono>
#include <random>

#include "Driver.h"

Driver::~Driver() {
}

void Driver::trace_all(sc_trace_file *tf, const std::string& parent_name) {
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

void Driver::reset() {
    o_biu_en.write(false);
    o_biu_we.write(false);
    o_biu_addr.write(0);
    o_biu_data.write(0);
}

void Driver::biu_read(sc_uint<ADDR_WIDTH> addr) {
    addr.range(CACHE_OFFSET_WIDTH-1, 0) = 0;

    o_biu_en.write(true);
    o_biu_we.write(false);
    o_biu_addr.write(addr.to_uint());
}

void Driver::biu_write(sc_uint<ADDR_WIDTH> addr, sc_bv<CACHE_LINE_WIDTH> data) {
    addr.range(CACHE_OFFSET_WIDTH-1, 0) = 0;

    o_biu_en.write(true);
    o_biu_we.write(true);
    o_biu_addr.write(addr.to_uint());
    o_biu_data.write(data);
}

void Driver::randomize() {
    std::mt19937 genrand(std::chrono::system_clock::now().time_since_epoch().count());
    std::uniform_int_distribution<int> genbit(0, 1);
    std::uniform_int_distribution<int> genaddr(0, SRAM_SIZE-1);

    while (true) {
        m_rnd_addr.write(genaddr(genrand));

        sc_bv<CACHE_LINE_WIDTH> data;
        for (int i = 0; i < data.length(); i++) {
            data[i] = genbit(genrand);
        }

        m_rnd_data.write(data);
        wait();
    }
}

void Driver::process() {
    sc_uint<ADDR_WIDTH> addr;
    sc_bv<CACHE_LINE_WIDTH> data;

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
