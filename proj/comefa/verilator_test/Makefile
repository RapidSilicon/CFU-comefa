#export VERILATOR_ROOT /home/data1/aman/verilator
#export PATH $(VERILATOR_ROOT)/bin:$(PATH)

all: compile run

compile:
	verilator -cc --exe --build sim_main.cpp ../cfu.v \
	--timescale 1ns/1ns -Wno-WIDTH 

run:
	cd obj_dir && make -f Vcfu.mk


