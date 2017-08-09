#!/bin/bash

# Script to generate a Markdown file with all TODOs from all source files.

set -e

# Set variables
SRC=../src
SYNTH=../synth
TB=../tb
TOOLS=../tools
FILEPATH=../TODO.md

# For finding all TODOs, use grep. -n shows line numbers. -r recursively.
# The awk utility is used to add a new empty line after every pattern match after which it is written to a file.
# TODO: improve output formatting.
# TODO: after both have been resolved, remove this file from the search path.
grep -n -r "TODO" $SRC $SYNTH $TB $TOOLS | awk '{print $0,"\n"}' > $FILEPATH
