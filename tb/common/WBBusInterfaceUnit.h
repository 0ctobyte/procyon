#include <systemc.h>

template <int cache_line_width, int wb_data_width>
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
    sc_in< sc_bv<cache_line_width> > i_biu_data;
    sc_out< sc_bv<cache_line_width> > o_biu_data;
    sc_out<bool> o_biu_done;
    sc_out<bool> o_biu_busy;

    SC_CTOR(WBBusInterfaceUnit)
        : m_num_reqs(cache_line_width / wb_data_width), m_num_acks(m_num_reqs), m_wb_word_size(wb_data_width / 8)
    {
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

    const int m_num_reqs;
    const int m_num_acks;
    const int m_wb_word_size;

    sc_signal<state_t> m_state;
    sc_signal<uint32_t> m_req_count, m_ack_count;

    void reset();
    void send_req(bool we, uint32_t addr, sc_uint<wb_data_width> data);
    void wait_ack();
    void done(sc_bv<cache_line_width> data_in);
    void update_counts();
    void update_state();
    void process();
};

template <int cache_line_width, int wb_data_width>
WBBusInterfaceUnit<cache_line_width, wb_data_width>::~WBBusInterfaceUnit() {
}

template <int cache_line_width, int wb_data_width>
void WBBusInterfaceUnit<cache_line_width, wb_data_width>::trace_all(sc_trace_file *tf, const std::string& parent_name) {
    const std::string module_name = parent_name+"."+name();
    sc_trace(tf, i_wb_clk, module_name+".i_wb_clk");
    sc_trace(tf, i_wb_rst, module_name+".i_wb_rst");
    sc_trace(tf, o_wb_cyc, module_name+".o_wb_cyc");
    sc_trace(tf, o_wb_stb, module_name+".o_wb_stb");
    sc_trace(tf, o_wb_we, module_name+".o_wb_we");
    sc_trace(tf, o_wb_sel, module_name+".o_wb_sel");
    sc_trace(tf, o_wb_addr, module_name+".o_wb_addr");
    sc_trace(tf, o_wb_data, module_name+".o_wb_data");
    sc_trace(tf, i_wb_data, module_name+".i_wb_data");
    sc_trace(tf, i_wb_ack, module_name+".i_wb_ack");
    sc_trace(tf, i_wb_stall, module_name+".i_wb_stall");
    sc_trace(tf, i_biu_en, module_name+".i_biu_en");
    sc_trace(tf, i_biu_we, module_name+".i_biu_we");
    sc_trace(tf, i_biu_addr, module_name+".i_biu_addr");
    sc_trace(tf, i_biu_data, module_name+".i_biu_data");
    sc_trace(tf, o_biu_data, module_name+".o_biu_data");
    sc_trace(tf, o_biu_done, module_name+".o_biu_done");
    sc_trace(tf, o_biu_busy, module_name+".o_biu_busy");
    sc_trace(tf, m_state, module_name+".m_state");
    sc_trace(tf, m_req_count, module_name+".m_req_count");
    sc_trace(tf, m_ack_count, module_name+".m_ack_count");
}

template <int cache_line_width, int wb_data_width>
void WBBusInterfaceUnit<cache_line_width, wb_data_width>::reset() {
    o_wb_cyc.write(false);
    o_wb_stb.write(false);
    o_wb_we.write(false);
    o_wb_sel.write(0);
    o_wb_addr.write(0);
    o_wb_data.write(0);

    o_biu_busy.write(false);
    o_biu_done.write(false);
}

template <int cache_line_width, int wb_data_width>
void WBBusInterfaceUnit<cache_line_width, wb_data_width>::send_req(bool we, uint32_t addr, sc_uint<wb_data_width> data) {
    o_wb_cyc.write(true);
    o_wb_stb.write(true);
    o_wb_we.write(we);
    o_wb_sel.write(0xf);
    o_wb_addr.write(addr);
    o_wb_data.write(data.to_uint());

    o_biu_busy.write(true);
    o_biu_done.write(false);
}

template <int cache_line_width, int wb_data_width>
void WBBusInterfaceUnit<cache_line_width, wb_data_width>::wait_ack() {
    o_wb_cyc.write(true);
    o_wb_stb.write(false);
    o_wb_we.write(false);
    o_wb_sel.write(false);
    o_wb_addr.write(0);
    o_wb_data.write(0);

    o_biu_busy.write(true);
    o_biu_done.write(false);
}

template <int cache_line_width, int wb_data_width>
void WBBusInterfaceUnit<cache_line_width, wb_data_width>::done(sc_bv<cache_line_width> data_in) {
    o_wb_cyc.write(false);
    o_wb_stb.write(false);
    o_wb_we.write(false);
    o_wb_sel.write(false);
    o_wb_addr.write(0);
    o_wb_data.write(0);

    o_biu_busy.write(false);
    o_biu_done.write(true);
    o_biu_data.write(data_in);
}

template <int cache_line_width, int wb_data_width>
void WBBusInterfaceUnit<cache_line_width, wb_data_width>::update_counts() {
    if (i_wb_rst.read() || m_state.read() == IDLE) {
        m_req_count.write(0);
        m_ack_count.write(0);
        return;
    }

    if (i_wb_ack.read()) {
        m_ack_count.write(m_ack_count.read() + 1);
    }

    if (m_state.read() == REQS && !i_wb_stall.read()) {
        m_req_count.write(m_req_count.read() + 1);
    }
}

template <int cache_line_width, int wb_data_width>
void WBBusInterfaceUnit<cache_line_width, wb_data_width>::update_state() {
    if (i_wb_rst.read()) {
        m_state.write(IDLE);
        return;
    }

    switch (m_state.read()) {
        case IDLE: {
            m_state.write(i_biu_en.read() ? REQS : IDLE);
            break;
        }
        case REQS: {
            m_state.write(m_req_count.read() == (m_num_reqs-1) ? ACKS : REQS);
            break;
        }
        case ACKS: {
            m_state.write(m_ack_count.read() == m_num_acks ? DONE : ACKS);
            break;
        }
        case DONE: {
            m_state.write(!i_biu_en.read() ? IDLE : DONE);
            break;
        }
    }
}

template <int cache_line_width, int wb_data_width>
void WBBusInterfaceUnit<cache_line_width, wb_data_width>::process() {
    bool we = i_biu_we.read();
    sc_bv<cache_line_width> data_out (i_biu_data.read());
    sc_bv<cache_line_width> data_in (false);
    uint32_t addr = i_biu_addr.read();

    while (true) {
        reset();

        if (m_ack_count.read() < m_num_acks) {
            uint32_t idx = m_ack_count.read() * wb_data_width;
            data_in.range(idx + wb_data_width - 1, idx) = i_wb_data.read();
        }

        switch (m_state.read()) {
            case IDLE: {
                we = i_biu_we.read();
                addr = i_biu_addr.read();
                data_out = i_biu_data.read();
                break;
            }
            case REQS: {
                uint32_t idx = m_req_count.read() * wb_data_width;
                sc_uint<wb_data_width> data (data_out.range(idx + wb_data_width - 1, idx).to_uint());
                uint32_t next_addr = addr + m_req_count.read() * m_wb_word_size;
                send_req(we, next_addr, data);
                break;
            }
            case ACKS: {
                wait_ack();
                break;
            }
            case DONE: {
                done(data_in);
                break;
            }
        }

        wait();
    }
}
