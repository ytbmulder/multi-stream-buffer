# stream-cache
OpenCAPI stream cache using akmartin his methodology and base cell library.

## Getting Started
The following instructions explain how to obtain the prerequisites for this project.

### Prerequisites
Download the `base` ready-valid cell library from Andrew Martin.
[link](https://github.ibm.com/akmartin/base)

The simulation script present in the `tools` folder supports both Linux and macOS. For either operating system, you need to install `icarus-verilog` (Verilog compiler) and `gtkwave` to act as a wave viewer.

### Installation
Before starting a simulation, the `sim.sh` script found in the `tools` folder needs to have executable permissions.
```
chmod+x ./tools/sim.sh
```

Also make sure that the path to the base library, which was installed earlier, is set correctly in `sim.sh`. This is done with the `BASE` parameter.

## Simulation
First decide which module you want to simulate and change the `TOP` variable in the `sim.sh` script accordingly.

To start the simulation, execute the following command from your preferred shell.
```
cd tools
./sim.sh
```
The source code is compiled and gtkwave is started with the corresponding wave configuration file.

## Acknowledgments
* Andrew Martin for his amazing design methodology.
