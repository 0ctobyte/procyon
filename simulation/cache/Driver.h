#include <systemc.h>

#include "test_common.h"

SC_MODULE(Driver) {
    sc_in<bool> clk;
    sc_in<bool> n_rst;

    sc_out<bool> o_cache_re;
    sc_out<bool> o_cache_we;
    sc_out<bool> o_cache_fe;
    sc_out<bool> o_cache_valid;
    sc_out<bool> o_cache_dirty;
    sc_out<uint32_t> o_cache_tag;
    sc_out<uint32_t> o_cache_index;
    sc_out<uint32_t> o_cache_offset;
    sc_out<uint32_t> o_cache_wdata;
    sc_out< sc_bv<CACHE_LINE_WIDTH> > o_cache_fdata;
    sc_in<bool> i_cache_dirty;
    sc_in<bool> i_cache_hit;
    sc_in<uint32_t> i_cache_tag;
    sc_in<uint32_t> i_cache_rdata;
    sc_in< sc_bv<CACHE_LINE_WIDTH> > i_cache_vdata;

    sc_out<bool> o_biu_en;
    sc_out<bool> o_biu_we;
    sc_out<uint32_t> o_biu_addr;
    sc_out< sc_bv<CACHE_LINE_WIDTH> > o_biu_data;
    sc_in<bool> i_biu_done;
    sc_in<bool> i_biu_busy;
    sc_in< sc_bv<CACHE_LINE_WIDTH> > i_biu_data;

    SC_CTOR(Driver) {
        SC_THREAD(process);
        sensitive << i_cache_vdata << i_cache_tag << i_biu_data << m_rnd_we << m_rnd_addr << m_rnd_data << m_state;
        SC_THREAD(randomize);
        sensitive << clk.pos();
        SC_METHOD(update_state);
        sensitive << clk.pos() << n_rst.neg();
    }

    void trace_all(sc_trace_file *tf, const std::string& parent_name);

    ~Driver();

private:
    typedef enum {
        IDLE,
        MISS,
        FILL,
        VICTIM
    } state_t;

    sc_signal<state_t> m_state;
    sc_signal< sc_uint<ADDR_WIDTH> > m_rnd_addr;
    sc_signal< sc_uint<DATA_WIDTH> > m_rnd_data;
    sc_signal<bool> m_rnd_we;

    void reset();
    void cache_write(sc_uint<ADDR_WIDTH> addr, sc_uint<DATA_WIDTH> data);
    void cache_read(sc_uint<ADDR_WIDTH> addr);
    void cache_fill(sc_uint<ADDR_WIDTH> addr, sc_bv<CACHE_LINE_WIDTH> fdata);
    void biu_read(sc_uint<ADDR_WIDTH> addr);
    void biu_write(sc_uint<ADDR_WIDTH> addr, sc_bv<CACHE_LINE_WIDTH> data);
    void update_state();
    void randomize();
    void process();
};
