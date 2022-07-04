#include "Vcfu.h"
#include "verilated.h"

unsigned int main_time = 0;
double sc_time_stamp() { return main_time; }


int main(int argc, char** argv, char** env) {
    Verilated::commandArgs(argc, argv);
    Vcfu* top = new Vcfu;
    while (!Verilated::gotFinish()) { top->eval(); }
    delete top;
    return 0;
}
