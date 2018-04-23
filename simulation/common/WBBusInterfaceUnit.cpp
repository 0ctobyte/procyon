#include "WBBusInterfaceUnit.h"

WBBusInterfaceUnit::~WBBusInterfaceUnit() {
}

void WBBusInterfaceUnit::trace_all(sc_trace_file *tf, const std::string& parent_name) {
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

void WBBusInterfaceUnit::reset() {
    o_wb_cyc.write(false);
    o_wb_stb.write(false);
    o_wb_we.write(false);
    o_wb_sel.write(0);
    o_wb_addr.write(0);
    o_wb_data.write(0);

    o_biu_busy.write(false);
    o_biu_done.write(false);
}

void WBBusInterfaceUnit::send_req(bool we, uint32_t addr, sc_uint<WB_DATA_WIDTH> data) {
    o_wb_cyc.write(true);
    o_wb_stb.write(true);
    o_wb_we.write(we);
    o_wb_sel.write(0xf);
    o_wb_addr.write(addr);
    o_wb_data.write(data.to_uint());

    o_biu_busy.write(true);
    o_biu_done.write(false);
}

void WBBusInterfaceUnit::wait_ack() {
    o_wb_cyc.write(true);
    o_wb_stb.write(false);
    o_wb_we.write(false);
    o_wb_sel.write(false);
    o_wb_addr.write(0);
    o_wb_data.write(0);

    o_biu_busy.write(true);
    o_biu_done.write(false);
}

void WBBusInterfaceUnit::done(sc_bv<CACHE_LINE_WIDTH> data_in) {
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

void WBBusInterfaceUnit::update_counts() {
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

void WBBusInterfaceUnit::update_state() {
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
            m_state.write(m_req_count.read() == (NUM_REQS-1) ? ACKS : REQS);
            break;
        }
        case ACKS: {
            m_state.write(m_ack_count.read() == NUM_ACKS ? DONE : ACKS);
            break;
        }
        case DONE: {
            m_state.write(!i_biu_en.read() ? IDLE : DONE);
            break;
        }
    }
}

void WBBusInterfaceUnit::process() {
    bool we = i_biu_we.read();
    sc_bv<CACHE_LINE_WIDTH> data_out (i_biu_data.read());
    sc_bv<CACHE_LINE_WIDTH> data_in (false);
    uint32_t addr = i_biu_addr.read();

    while (true) {
        reset();

        if (m_ack_count.read() < NUM_ACKS) {
            uint32_t idx = m_ack_count.read() * WB_DATA_WIDTH;
            data_in.range(idx + WB_DATA_WIDTH - 1, idx) = i_wb_data.read();
        }

        switch (m_state.read()) {
            case IDLE: {
                we = i_biu_we.read();
                addr = i_biu_addr.read();
                data_out = i_biu_data.read();
                break;
            }
            case REQS: {
                uint32_t idx = m_req_count.read() * WB_DATA_WIDTH;
                sc_uint<WB_DATA_WIDTH> data (data_out.range(idx + WB_DATA_WIDTH - 1, idx).to_uint());
                uint32_t next_addr = addr + m_req_count.read() * WB_WORD_SIZE;
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
