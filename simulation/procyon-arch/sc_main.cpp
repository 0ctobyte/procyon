#include "Vdut.h"
#include "verilated_vcd_sc.h"

#include "BootRom.h"
#include "DataRam.h"

bool ends_with(const std::string& str, const std::string& suffix) {
    return (str.size() >= suffix.size() && str.compare(str.size() - suffix.size(), suffix.size(), suffix) == 0);
}

int sc_main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    Verilated::traceEverOn(true);

    if (argc < 2) {
        std::cerr << "ERROR: No binary or hex file specified" << std::endl;
    }

    std::string top_name("top");
    sc_trace_file *tf = sc_create_vcd_trace_file("sysc");

    sc_clock clk("clk", sc_time(10, SC_NS));
    sc_signal<bool> n_rst(0);

    sc_trace(tf, clk, top_name+".clk");
    sc_trace(tf, n_rst, top_name+".n_rst");

    sc_signal<uint32_t> sim_tp;
    sc_signal<uint32_t> ic_insn;
    sc_signal<bool> ic_valid;
    sc_signal<uint32_t> ic_pc;
    sc_signal<bool> ic_en;
    sc_signal<bool> dc_hit;
    sc_signal<uint32_t> dc_rdata;
    sc_signal<bool> dc_re;
    sc_signal<uint32_t> dc_addr;
    sc_signal<bool> sq_retire_dc_hit;
    sc_signal<bool> sq_retire_msq_full;
    sc_signal<bool> sq_retire_en;
    sc_signal<uint32_t> sq_retire_byte_en;
    sc_signal<uint32_t> sq_retire_addr;
    sc_signal<uint32_t> sq_retire_data;

    BootRom bootrom("bootrom");
    bootrom.trace_all(tf, top_name);
    bootrom.i_ic_en(ic_en);
    bootrom.i_ic_pc(ic_pc);
    bootrom.o_ic_valid(ic_valid);
    bootrom.o_ic_insn(ic_insn);

    std::string rom_file(argv[1]);
    std::string suffix_str("hex");
    if (ends_with(rom_file, suffix_str)) {
        bootrom.load_hex(rom_file);
    } else {
        bootrom.load_bin(rom_file);
    }

    DataRam dataram("dataram");
    dataram.trace_all(tf, top_name);
    dataram.o_dc_hit(dc_hit);
    dataram.o_dc_rdata(dc_rdata);
    dataram.i_dc_re(dc_re);
    dataram.i_dc_addr(dc_addr);
    dataram.o_sq_retire_dc_hit(sq_retire_dc_hit);
    dataram.o_sq_retire_msq_full(sq_retire_msq_full);
    dataram.i_sq_retire_en(sq_retire_en);
    dataram.i_sq_retire_byte_en(sq_retire_byte_en);
    dataram.i_sq_retire_addr(sq_retire_addr);
    dataram.i_sq_retire_data(sq_retire_data);

    if (ends_with(rom_file, suffix_str)) {
        dataram.load_hex(rom_file);
    } else {
        dataram.load_bin(rom_file);
    }

    Vdut dut("dut");
    dut.clk(clk);
    dut.n_rst(n_rst);
    dut.o_sim_tp(sim_tp);
    dut.i_ic_insn(ic_insn);
    dut.i_ic_valid(ic_valid);
    dut.o_ic_pc(ic_pc);
    dut.o_ic_en(ic_en);
    dut.i_dc_hit(dc_hit);
    dut.i_dc_rdata(dc_rdata);
    dut.o_dc_re(dc_re);
    dut.o_dc_addr(dc_addr);
    dut.i_sq_retire_dc_hit(sq_retire_dc_hit);
    dut.i_sq_retire_msq_full(sq_retire_msq_full);
    dut.o_sq_retire_en(sq_retire_en);
    dut.o_sq_retire_byte_en(sq_retire_byte_en);
    dut.o_sq_retire_addr(sq_retire_addr);
    dut.o_sq_retire_data(sq_retire_data);

    VerilatedVcdSc tfp;
    dut.trace(&tfp, 100);
    tfp.open("dut.vcd");

    while (sim_tp != 0xfffffbd2 && sim_tp != 0xfffffae5 && sc_get_status() != SC_STOPPED) {
        if (sc_time_stamp() >= sc_time(10, SC_NS)) n_rst = 1;
        sc_start(1, SC_NS);
    }


    int err = 0;
    if (sim_tp == 0xfffffbd2 && sc_get_status() != SC_STOPPED) {
        std::cout << "\n\n" << "*********************************    PASS    *********************************" << std::endl;
    } else {
        std::cout << "\n\n" << "*********************************    FAIL    *********************************" << std::endl;
        err = 1;
    }

    dut.final();
    sc_close_vcd_trace_file(tf);
    tfp.close();
    return err;
}
