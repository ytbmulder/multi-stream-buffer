# multi-stream-buffer
Multi stream buffer using [akgmartin](https://github.com/akgmartin) his methodology and base cell library.

## Getting Started
The following instructions explain how to obtain the prerequisites for this project.

### Prerequisites
Download the `base` ready-valid cell library from akgmartin [here](https://github.com/akgmartin/dicells).

The simulation script present in the `tools` folder supports both Linux and macOS. For either operating system, you need to install `icarus-verilog` (Verilog compiler) and `gtkwave` to act as a wave viewer.

### Installation
Before starting a simulation, the `sim.sh` script found in the `tools` folder needs to have executable permissions.
```
chmod+x ./tools/sim.sh
```

Also make sure that the path to the base library, which was installed earlier, is set correctly in `sim.sh`. This is done with the `BASE` parameter.

## Simulation
The module to be simulated (usually a testbench) is given as an argument to the `sim.sh` script.

To start the simulation, execute the following command from your preferred shell.
```
cd tools
./sim.sh <MODULE NAME>
```
The source code is compiled and gtkwave is started with the corresponding wave configuration file.

## Acknowledgments
* Andrew Martin for his amazing design methodology.

## Citation
If this project has helped you in any way, please consider to cite it.
```text
@mastersthesis{mulder2018feeding,
  author  = {Mulder, Y.T.B.},
  title   = {Feeding High-Bandwidth Streaming-Based FPGA Accelerators},
  school  = {Delft University of Technology},
  year    = 2018,
  address = {Mekelweg 4, 2628 CD Delft, The Netherlands},
  month   = 1
}
```
A PDF is available [here](https://repository.tudelft.nl/islandora/object/uuid%3A75dd920a-0e50-49c9-9982-70ef7dab7a92).
A GitHub repository is available [here](https://github.com/ytbmulder/msc-thesis).
