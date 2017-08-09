#!/bin/bash

# Script to simulate (System)Verilog sources using iverilog, vvp and gtkwave on macOS.
# This script was tested with the following application versions:
# - macOS 10.12.5
# - bash 3.2
# - iverilog 10.1.1
# - vvp 10.1.1
# - gtkwave 3.3.79

# User defined top level module name.
#export TOP=rd_ctrl_top_tb
#export TOP=bram_tile_tb
#export TOP=l2_ptr_st_tb
#export TOP=l2_stream_control_tb
#export TOP=l2_ctrl_top_tb
export TOP=apl_top_tb
#export TOP=axi_tag_tb

# Script terminates after the first non-zero exit code.
set -e
#set -euo pipefail

#TODO: set the correct path (../sim/) for .gtkw files when directly saved instead of saved as.

#TODO: test if Swith.pm is installed on host machine - invoking gtkwave from bash script needs to run perl script within gtkwave.app on OSX according to gtkwave manual. however this gave an error with perl since perl could not locate Switch.pm in @INC. run 'sudo cpan -f Switch' to install and then calling gtkwave works from command line.
#TODO: test if iverilog and gtkwave are installed
# - check which operating system is used.
# - check if iverilog, vvp and gtkwave are installed
# - set variables for GTKPATH accordingly.
# - decide on GTKPATH variable here since we already check the OS here.
#TODO: test if .sim-iverilog and .gen-todo are executable. If not, run chmod +x.

# Locations of the (System)Verilog source files.
export BASE=../../base
export SIM=../sim
export SRC=../src
#export SYNTH=../synth
export TB=../tb
export WORK=../work

# Test if directory 'work' exists. If not, create it.
if [ ! -d "$WORK" ]; then
	mkdir $WORK
fi

#TODO: make sure all .sv files compile. then you can use $SRC/*.sv and $TB/*.sv -> #iverilog -DVCD -o $WORK/$TOP.out -s $TOP $BASE/*.sv $SRC/*.sv $TB/*.sv
#TODO: add -Wall to display all warnings. timescale as well, but i dont use that.
#TODO: use lxt format which is faster
#TODO: for uram/bram sims, ifdef XILINX use their module, otherwise use behav model.
iverilog -DVCD -o $WORK/$TOP.out -s $TOP $BASE/*.sv $SRC/ptr_st.sv $SRC/rd_ctrl_top.sv $SRC/rd_port.sv $SRC/req_merge.sv $TB/rd_ctrl_top_tb.sv $SRC/l2_stream_control.sv $TB/l2_stream_control_tb.sv $SRC/l2_ctrl_top.sv $TB/l2_ctrl_top_tb.sv $SRC/apl_top.sv $TB/apl_top_tb.sv $SRC/axi_tag.sv $TB/axi_tag_tb.sv
#iverilog -DVCD -DSIM -o $WORK/$TOP.out -s $TOP $BASE/*.sv $SRC/ptr_st.sv $SRC/rd_ctrl_top.sv $SRC/rd_port.sv $SRC/req_merge.sv $SRC/bram_tile.sv $TB/bram_tile_tb.sv
vvp $WORK/$TOP.out
mv $TOP.vcd $WORK/$TOP.vcd # VCD file is dumped in same directory as this script. Move it to the work folder.

# Check if gtkwave is already running. If so, let the user press the reload butten. If not, open gtkwave.
SERVICE='gtkwave'

if ps ax | grep -v grep | grep $SERVICE > /dev/null ; then
    echo "$SERVICE service running, press the reload button."
	#TODO: if gtkwave is already open, use the reload function from the command line.
else
    echo "$SERVICE is not running, $SERVICE starts up now."

	# Check which operating system is used to decide where gtkwave is located.
	OS=$(uname -s)
	if [ "$OS" = "Darwin" ] ; then
		# Path of gtkwave for macOS is fixed.
		export GTKPATH=/Applications/gtkwave.app/Contents/Resources/bin/gtkwave
	elif [ "$OS" = "Linux" ] ; then
		# Find the path of gtkwave using the whereis utility.
		export GTKPATH=$SERVICE
	else
		# Terminate the script if the operating system is neither Darwin or Linux.
		echo "Operating system could not be determined."
		exit 1
	fi

	#TODO: Test if the vcd and gtkw files exist before starting gtkwave.
	#if [ ! test -f $WORK/$TOP.vcd ] && [ ! test -f $SIM/$TOP.gtkw ] ; then
		# Start gtkwave with the vcd and gtkw files.
		$GTKPATH $WORK/$TOP.vcd $SIM/$TOP.gtkw &
	#else
	#	echo "$SERVICE input files are not found."
	#	exit 1
	#fi
fi

# TODO: make a clean script to delete the 'work' folder

# Update to-do list.
#./gen-todo.sh
