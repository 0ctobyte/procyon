#include "Vdut.h"
#include "verilated_vcd_sc.h"

#include "BootRom.h"
#include "Sram.h"

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

    sc_clock clk("clk", sc_time(1, SC_NS));
    sc_signal<bool> n_rst(0);

    sc_trace(tf, clk, top_name+".clk");
    sc_trace(tf, n_rst, top_name+".n_rst");

    sc_signal<uint32_t> sim_tp;
    sc_signal<bool> sim_retire;
    sc_signal<uint32_t> ic_insn;
    sc_signal<bool> ic_valid;
    sc_signal<uint32_t> ic_pc;
    sc_signal<bool> ic_en;

    sc_signal<uint32_t> sram_addr;
    sc_signal<uint32_t> sram_dq_i;
    sc_signal<uint32_t> sram_dq_o;
    sc_signal<bool> sram_ce_n;
    sc_signal<bool> sram_we_n;
    sc_signal<bool> sram_oe_n;
    sc_signal<bool> sram_ub_n;
    sc_signal<bool> sram_lb_n;

    Sram sram("sram");
    sram.trace_all(tf, top_name);
    sram.i_sram_addr(sram_addr);
    sram.i_sram_dq(sram_dq_o);
    sram.o_sram_dq(sram_dq_i);
    sram.i_sram_ce_n(sram_ce_n);
    sram.i_sram_we_n(sram_we_n);
    sram.i_sram_oe_n(sram_oe_n);
    sram.i_sram_ub_n(sram_ub_n);
    sram.i_sram_lb_n(sram_lb_n);

    BootRom bootrom("bootrom");
    bootrom.trace_all(tf, top_name);
    bootrom.i_ic_en(ic_en);
    bootrom.i_ic_pc(ic_pc);
    bootrom.o_ic_valid(ic_valid);
    bootrom.o_ic_insn(ic_insn);

    Vdut dut("dut");
    dut.clk(clk);
    dut.n_rst(n_rst);
    dut.o_sram_addr(sram_addr);
    dut.i_sram_dq(sram_dq_i);
    dut.o_sram_dq(sram_dq_o);
    dut.o_sram_ce_n(sram_ce_n);
    dut.o_sram_we_n(sram_we_n);
    dut.o_sram_oe_n(sram_oe_n);
    dut.o_sram_ub_n(sram_ub_n);
    dut.o_sram_lb_n(sram_lb_n);
    dut.o_sim_tp(sim_tp);
    dut.o_sim_retire(sim_retire);
    dut.i_ic_insn(ic_insn);
    dut.i_ic_valid(ic_valid);
    dut.o_ic_pc(ic_pc);
    dut.o_ic_en(ic_en);

    std::string rom_file(argv[1]);
    std::string suffix_str("hex");
    if (ends_with(rom_file, suffix_str)) {
        bootrom.load_hex(rom_file);
        sram.load_hex(rom_file);
    } else {
        bootrom.load_bin(rom_file);
        sram.load_bin(rom_file);
    }

    VerilatedVcdSc tfp;
    dut.trace(&tfp, 100);
    tfp.open("dut.vcd");

    uint64_t retired_insns = 0, cycles = 0;
    while (sim_tp != 0xfffffbd2 && sim_tp != 0xfffffae5 && sc_get_status() != SC_STOPPED) {
        if (sc_time_stamp() >= sc_time(1, SC_NS)) n_rst = 1;
        sc_start(1, SC_NS);
        if (sim_retire) retired_insns++;
        if (n_rst) cycles++;
    }

    std::cout << "\nINSTRUCTIONS: " << std::dec << retired_insns
        << " CYCLES: " << std::dec << cycles
        << " IPC: " << std::dec << (double)retired_insns/(double)cycles << std::endl;

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
