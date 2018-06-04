#include <vector>

#include <systemc.h>

SC_MODULE(BootRom) {
    sc_in<bool> i_ic_en;
    sc_in<uint32_t> i_ic_pc;
    sc_out<bool> o_ic_valid;
    sc_out<uint32_t> o_ic_insn;

    SC_CTOR(BootRom) {
        SC_METHOD(process);
        sensitive << i_ic_en << i_ic_pc;
        m_bootrom = std::vector<uint8_t>();
    }

    void trace_all(sc_trace_file *tf, const std::string& parent_name);
    void load_hex(const std::string& filename);
    void load_bin(const std::string& filename);

    ~BootRom();

private:
    std::vector<uint8_t> m_bootrom;

    void process();
};
