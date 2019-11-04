#!/bin/bash

set -e

############################################################################
###############################  Hack For AWS ##############################
############################################################################

# Change permissions so Docker containers can use FPGA devices
sudo /opt/xilinx/xrt/bin/awssak query # Need to run this before changing permissions

setperm () {
  sudo chmod g=u $1
  sudo chmod a=u $1
}
setfpgaperm () {
  for f in $1/*; do setperm $f; done
}
for d in /sys/bus/pci/devices/*; do cat $d/class| grep -q "0x058000" && setfpgaperm $d;  done
setperm /sys/bus/pci/rescan
