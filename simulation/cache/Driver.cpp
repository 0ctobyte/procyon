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
    sc_trace(tf, o_cache_re, module_name+".o_cache_re");
    sc_trace(tf, o_cache_we, module_name+".o_cache_we");
    sc_trace(tf, o_cache_fe, module_name+".o_cache_fe");
    sc_trace(tf, o_cache_valid, module_name+".o_cache_valid");
    sc_trace(tf, o_cache_tag, module_name+".o_cache_tag");
    sc_trace(tf, o_cache_index, module_name+".o_cache_index");
    sc_trace(tf, o_cache_offset, module_name+".o_cache_offset");
    sc_trace(tf, o_cache_wdata, module_name+".o_cache_wdata");
    sc_trace(tf, o_cache_fdata, module_name+".o_cache_fdata");
    sc_trace(tf, i_cache_dirty, module_name+".i_cache_dirty");
    sc_trace(tf, i_cache_hit, module_name+".i_cache_hit");
    sc_trace(tf, i_cache_tag, module_name+".i_cache_tag");
    sc_trace(tf, i_cache_rdata, module_name+".i_cache_rdata");
    sc_trace(tf, i_cache_vdata, module_name+".i_cache_vdata");
    sc_trace(tf, o_biu_en, module_name+".o_biu_en");
    sc_trace(tf, o_biu_we, module_name+".o_biu_we");
    sc_trace(tf, o_biu_addr, module_name+".o_biu_addr");
    sc_trace(tf, o_biu_data, module_name+".o_biu_data");
    sc_trace(tf, i_biu_data, module_name+".i_biu_data");
    sc_trace(tf, i_biu_done, module_name+".i_biu_done");
    sc_trace(tf, i_biu_busy, module_name+".i_biu_busy");
    sc_trace(tf, m_state, module_name+".m_name");
}

void Driver::reset() {
    o_cache_re.write(false);
    o_cache_we.write(false);
    o_cache_fe.write(false);
    o_cache_valid.write(false);
    o_cache_tag.write(0);
    o_cache_index.write(0);
    o_cache_offset.write(0);
    o_cache_wdata.write(0);
    o_cache_fdata.write(false);

    o_biu_en.write(false);
    o_biu_we.write(false);
    o_biu_addr.write(0);
    o_biu_data.write(0);
}

void Driver::cache_write(sc_uint<ADDR_WIDTH> addr, sc_uint<DATA_WIDTH> data) {
    uint32_t offset = addr.range(CACHE_OFFSET_WIDTH-1, 0).to_uint();
    uint32_t index = addr.range(CACHE_INDEX_WIDTH+CACHE_OFFSET_WIDTH-1, CACHE_OFFSET_WIDTH).to_uint();
    uint32_t tag = addr.range(ADDR_WIDTH-1, ADDR_WIDTH-CACHE_TAG_WIDTH);

    o_cache_we.write(true);
    o_cache_re.write(false);
    o_cache_fe.write(false);
    o_cache_valid.write(true);
    o_cache_tag.write(tag);
    o_cache_index.write(index);
    o_cache_offset.write(offset);
    o_cache_wdata.write(data);
}

void Driver::cache_read(sc_uint<ADDR_WIDTH> addr) {
    uint32_t offset = addr.range(CACHE_OFFSET_WIDTH-1, 0).to_uint();
    uint32_t index = addr.range(CACHE_INDEX_WIDTH+CACHE_OFFSET_WIDTH-1, CACHE_OFFSET_WIDTH).to_uint();
    uint32_t tag = addr.range(ADDR_WIDTH-1, ADDR_WIDTH-CACHE_TAG_WIDTH);

    o_cache_we.write(false);
    o_cache_re.write(true);
    o_cache_fe.write(false);
    o_cache_valid.write(true);
    o_cache_tag.write(tag);
    o_cache_index.write(index);
    o_cache_offset.write(offset);
}

void Driver::cache_fill(sc_uint<ADDR_WIDTH> addr, sc_bv<CACHE_LINE_WIDTH> fdata) {
    uint32_t offset = addr.range(CACHE_OFFSET_WIDTH-1, 0).to_uint();
    uint32_t index = addr.range(CACHE_INDEX_WIDTH+CACHE_OFFSET_WIDTH-1, CACHE_OFFSET_WIDTH).to_uint();
    uint32_t tag = addr.range(ADDR_WIDTH-1, ADDR_WIDTH-CACHE_TAG_WIDTH);

    o_cache_we.write(false);
    o_cache_re.write(false);
    o_cache_fe.write(true);
    o_cache_valid.write(true);
    o_cache_tag.write(tag);
    o_cache_index.write(index);
    o_cache_offset.write(offset);
    o_cache_fdata.write(fdata);
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
    std::uniform_int_distribution<int> read_or_write(0, 1);
    std::uniform_int_distribution<int> genaddr(0, CACHE_SIZE*2);

    while (true) {
        m_rnd_addr.write(genaddr(genrand));
        m_rnd_data.write(genrand());
        m_rnd_we.write(read_or_write(genrand));
        wait();
    }
}

void Driver::process() {
    sc_uint<ADDR_WIDTH> addr, vaddr;
    sc_uint<DATA_WIDTH> data;
    sc_bv<CACHE_LINE_WIDTH> fdata, vdata;

    while (true) {
        reset();
        switch (m_state.read()) {
            case IDLE: {
                addr = m_rnd_addr.read();
                data = m_rnd_data.read();

                if (m_rnd_we.read()) {
                    cache_write(addr, data);
                } else {
                    cache_read(addr);
                }
                break;
            }
            case MISS: {
                biu_read(addr);
                fdata = i_biu_data.read();
                break;
            }
            case FILL: {
                cache_fill(addr, fdata);
                vdata = i_cache_vdata.read();
                vaddr = addr;
                vaddr(ADDR_WIDTH-1, ADDR_WIDTH-CACHE_TAG_WIDTH) = i_cache_tag.read();
                break;
            }
            case VICTIM: {
                biu_write(vaddr, vdata);
                break;
            }
        }

        wait();
    }
}

void Driver::update_state() {
    if (!n_rst.read()) {
        m_state.write(IDLE);
        return;
    }

    switch (m_state.read()) {
        case IDLE: {
            m_state.write(((o_cache_we.read() || o_cache_re.read()) && !i_cache_hit.read()) ? MISS : IDLE);
            break;
        }
        case MISS: {
            m_state.write(i_biu_done.read() ? FILL : MISS);
            break;
        }
        case FILL: {
            bool victimized = i_cache_dirty.read();
            m_state.write(victimized ? VICTIM : IDLE);
            break;
        }
        case VICTIM: {
            m_state.write(i_biu_done.read() ? IDLE : VICTIM);
            break;
        }
    }
}

