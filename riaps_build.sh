#!/bin/bash -e
# Build RIAPS BBB Kernel image and associated files with the desired kconfig changes
# Provide back the .deb package

rm -rf deploy/      # Remove any existing builds

# Copy config file or a patch 
# TBD

# Build debian package
./build_deb.sh
