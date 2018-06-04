#include <vector>

#include <systemc.h>

SC_MODULE(DataRam) {
    sc_in<bool> i_dc_re;
    sc_in<uint32_t> i_dc_raddr;
    sc_out<bool> o_dc_hit;
    sc_out<uint32_t> o_dc_rdata;
    sc_in<bool> i_sq_retire_en;
    sc_in<uint32_t> i_sq_retire_byte_en;
    sc_in<uint32_t> i_sq_retire_addr;
    sc_in<uint32_t> i_sq_retire_data;
    sc_out<bool> o_sq_retire_dc_hit;
    sc_out<bool> o_sq_retire_msq_full;

    SC_CTOR(DataRam) {
        SC_METHOD(process);
        sensitive << i_dc_re << i_dc_raddr << i_sq_retire_en << i_sq_retire_byte_en << i_sq_retire_addr << i_sq_retire_data;
        m_dataram = std::vector<uint8_t>();
    }

    void trace_all(sc_trace_file *tf, const std::string& parent_name);
    void load_hex(const std::string& filename);
    void load_bin(const std::string& filename);

    ~DataRam();

private:
    std::vector<uint8_t> m_dataram;

    void process();
};
