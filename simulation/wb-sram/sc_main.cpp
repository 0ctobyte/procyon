#include "Vdut.h"
#include "verilated_vcd_sc.h"

#include "Driver.h"
#include "Monitor.h"
#include "Sram.h"
#include "WBBusInterfaceUnit.h"

#define SRAM_DATA_WIDTH    (16)
#define SRAM_ADDR_WIDTH    (20)
#define SRAM_SIZE          (1 << (SRAM_ADDR_WIDTH+1))

#define CACHE_SIZE         (256)
#define CACHE_LINE_SIZE    (32)
#define CACHE_LINE_WIDTH   (CACHE_LINE_SIZE*8)

#define WB_DATA_WIDTH      (16)
#define WB_ADDR_WIDTH      (32)

#define DATA_WIDTH         (32)
#define ADDR_WIDTH         (32)

int sc_main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    Verilated::traceEverOn(true);

    std::string top_name("top");
    sc_trace_file *tf = sc_create_vcd_trace_file("sysc");

    sc_clock clk("clk", sc_time(10, SC_NS));
    sc_signal<bool> n_rst(0);

    sc_trace(tf, clk, top_name+".clk");
    sc_trace(tf, n_rst, top_name+".n_rst");

    sc_signal<bool> wb_rst;
    sc_signal<bool> wb_cyc;
    sc_signal<bool> wb_stb;
    sc_signal<bool> wb_we;
    sc_signal<uint32_t> wb_sel;
    sc_signal<uint32_t> wb_addr;
    sc_signal<uint32_t> wb_data_o;
    sc_signal<uint32_t> wb_data_i;
    sc_signal<bool> wb_ack;
    sc_signal<bool> wb_stall;

    sc_signal<bool> biu_en;
    sc_signal<bool> biu_we;
    sc_signal<uint32_t> biu_addr;
    sc_signal< sc_bv<CACHE_LINE_WIDTH> > biu_data_i;
    sc_signal<bool> biu_done;
    sc_signal<bool> biu_busy;
    sc_signal< sc_bv<CACHE_LINE_WIDTH> > biu_data_o;

    sc_signal<uint32_t> sram_addr;
    sc_signal<uint32_t> sram_dq_i;
    sc_signal<uint32_t> sram_dq_o;
    sc_signal<bool> sram_ce_n;
    sc_signal<bool> sram_we_n;
    sc_signal<bool> sram_oe_n;
    sc_signal<bool> sram_ub_n;
    sc_signal<bool> sram_lb_n;

    Sram<SRAM_SIZE> sram("sram");
    sram.trace_all(tf, top_name);
    sram.i_sram_addr(sram_addr);
    sram.i_sram_dq(sram_dq_o);
    sram.o_sram_dq(sram_dq_i);
    sram.i_sram_ce_n(sram_ce_n);
    sram.i_sram_we_n(sram_we_n);
    sram.i_sram_oe_n(sram_oe_n);
    sram.i_sram_ub_n(sram_ub_n);
    sram.i_sram_lb_n(sram_lb_n);

    WBBusInterfaceUnit<CACHE_LINE_WIDTH, WB_DATA_WIDTH> biu("biu");
    biu.trace_all(tf, top_name);
    biu.i_wb_clk(clk);
    biu.i_wb_rst(wb_rst);
    biu.o_wb_cyc(wb_cyc);
    biu.o_wb_stb(wb_stb);
    biu.o_wb_we(wb_we);
    biu.o_wb_sel(wb_sel);
    biu.o_wb_addr(wb_addr);
    biu.o_wb_data(wb_data_i);
    biu.i_wb_data(wb_data_o);
    biu.i_wb_ack(wb_ack);
    biu.i_wb_stall(wb_stall);
    biu.i_biu_en(biu_en);
    biu.i_biu_we(biu_we);
    biu.i_biu_addr(biu_addr);
    biu.i_biu_data(biu_data_i);
    biu.o_biu_data(biu_data_o);
    biu.o_biu_done(biu_done);
    biu.o_biu_busy(biu_busy);

    Driver<CACHE_LINE_WIDTH, SRAM_SIZE, ADDR_WIDTH> driver("wb_driver");
    driver.trace_all(tf, top_name);
    driver.clk(clk);
    driver.n_rst(n_rst);
    driver.o_biu_en(biu_en);
    driver.o_biu_we(biu_we);
    driver.o_biu_addr(biu_addr);
    driver.o_biu_data(biu_data_i);
    driver.i_biu_done(biu_done);
    driver.i_biu_busy(biu_busy);
    driver.i_biu_data(biu_data_o);

    Monitor<CACHE_LINE_WIDTH, ADDR_WIDTH> monitor("monitor");
    monitor.trace_all(tf, top_name);
    monitor.i_biu_en(biu_en);
    monitor.i_biu_we(biu_we);
    monitor.i_biu_addr(biu_addr);
    monitor.i_biu_data_i(biu_data_i);
    monitor.i_biu_done(biu_done);
    monitor.i_biu_busy(biu_busy);
    monitor.i_biu_data_o(biu_data_o);

    Vdut dut("dut");
    dut.clk(clk);
    dut.n_rst(n_rst);
    dut.o_wb_rst(wb_rst);
    dut.i_wb_cyc(wb_cyc);
    dut.i_wb_stb(wb_stb);
    dut.i_wb_we(wb_we);
    dut.i_wb_sel(wb_sel);
    dut.i_wb_addr(wb_addr);
    dut.i_wb_data(wb_data_i);
    dut.o_wb_data(wb_data_o);
    dut.o_wb_ack(wb_ack);
    dut.o_wb_stall(wb_stall);
    dut.o_sram_addr(sram_addr);
    dut.i_sram_dq(sram_dq_i);
    dut.o_sram_dq(sram_dq_o);
    dut.o_sram_ce_n(sram_ce_n);
    dut.o_sram_we_n(sram_we_n);
    dut.o_sram_oe_n(sram_oe_n);
    dut.o_sram_ub_n(sram_ub_n);
    dut.o_sram_lb_n(sram_lb_n);

    VerilatedVcdSc tfp;
    dut.trace(&tfp, 100);
    tfp.open("dut.vcd");

    while (sc_time_stamp() < sc_time(1, SC_MS) && sc_get_status() != SC_STOPPED) {
        if (sc_time_stamp() >= sc_time(10, SC_NS)) n_rst = 1;
        sc_start(1, SC_NS);
    }

    if (sc_get_status() != SC_STOPPED) {
        std::cout << "\n\n" << "*********************************    PASS    *********************************" << std::endl;
    } else {
        std::cout << "\n\n" << "*********************************    FAIL    *********************************" << std::endl;
    }

    dut.final();
    sc_close_vcd_trace_file(tf);
    tfp.close();
    return 0;
}
