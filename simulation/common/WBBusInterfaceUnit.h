#include <systemc.h>

#include "test_common.h"

#define WB_WORD_SIZE (WB_DATA_WIDTH/8)
#define NUM_REQS     (CACHE_LINE_WIDTH/WB_DATA_WIDTH)
#define NUM_ACKS     (NUM_REQS)

SC_MODULE(WBBusInterfaceUnit) {
    sc_in<bool> i_wb_clk;
    sc_in<bool> i_wb_rst;
    sc_in<uint32_t> i_wb_data;
    sc_in<bool> i_wb_ack;
    sc_in<bool> i_wb_stall;
    sc_out<bool> o_wb_cyc;
    sc_out<bool> o_wb_stb;
    sc_out<bool> o_wb_we;
    sc_out<uint32_t> o_wb_sel;
    sc_out<uint32_t> o_wb_addr;
    sc_out<uint32_t> o_wb_data;

    sc_in<bool> i_biu_en;
    sc_in<bool> i_biu_we;
    sc_in<uint32_t> i_biu_addr;
    sc_in< sc_bv<CACHE_LINE_WIDTH> > i_biu_data;
    sc_out< sc_bv<CACHE_LINE_WIDTH> > o_biu_data;
    sc_out<bool> o_biu_done;
    sc_out<bool> o_biu_busy;

    SC_CTOR(WBBusInterfaceUnit) {
        SC_THREAD(process);
        sensitive << i_biu_we << i_biu_data << i_biu_addr << i_wb_data << m_ack_count << m_req_count << m_state;
        SC_METHOD(update_state);
        sensitive << i_wb_clk.pos() << i_wb_rst.pos();
        SC_METHOD(update_counts);
        sensitive << i_wb_clk.pos() << i_wb_rst.pos();
    }

    void trace_all(sc_trace_file *tf, const std::string& parent_name);

    ~WBBusInterfaceUnit();

private:
    typedef enum {
        IDLE,
        REQS,
        ACKS,
        DONE
    } state_t;

    sc_signal<state_t> m_state;
    sc_signal<uint32_t> m_req_count, m_ack_count;

    void reset();
    void send_req(bool we, uint32_t addr, sc_uint<WB_DATA_WIDTH> data);
    void wait_ack();
    void done(sc_bv<CACHE_LINE_WIDTH> data_in);
    void update_counts();
    void update_state();
    void process();
};
