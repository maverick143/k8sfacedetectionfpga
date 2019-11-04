import time

import numpy as np
from xfdnn.rt import xdnn, xdnn_io


# Our custom FPGA One-shot layer
class XFDNNPyAPI(object):

    # Called once when the network is initialized
    def __init__(self, params):
        self._args = xdnn_io.make_dict_args(params)
        self._numPE = self._args[
            "batch_sz"
        ]  # Bryan hack to detremine number of PEs in FPGA

        # Establish FPGA Communication, Load bitstream
        ret, handles = xdnn.createHandle(self._args["xclbin"], "kernelSxdnn_0")
        if ret != 0:
            raise Exception("Failed to open FPGA handle.")

        self._args["scaleB"] = 1
        self._args["PE"] = -1
        self._streamIds = [0, 1, 2, 3, 4, 5, 6, 7]  # Allow 8 streams

        # Instantiate runtime interface object
        self.fpgaRT = xdnn.XDNNFPGAOp(handles, self._args)
        self._indictnames = self._args["input_names"]
        self._outdictnames = self._args["output_names"]
        self._parser = xdnn.CompilerJsonParser(self._args["netcfg"])

    # Called for every batch
    def forward(self, bottom):
        top = [0] * len(self._outdictnames)

        indict = {}
        outdict = {}

        for i, n in enumerate(self._indictnames):
            # default to 1 batch
            indict[n] = np.ascontiguousarray(np.expand_dims(bottom[i], 0))

        for i, name in enumerate(self._outdictnames):
            dim = self._parser.getOutputs()[name]
            top[i] = np.empty(dim, dtype=np.float32)
            outdict[name] = top[i]

        # Get a free stream if available
        if self._streamIds:
            streamId = self._streamIds.pop(0)
        else:
            return None

        start_time = time.time()
        # self.fpgaRT.execute(indict, outdict, streamId)
        self.fpgaRT.exec_async(indict, outdict, streamId)
        self.fpgaRT.get_result(streamId)
        end_time = time.time()

        self._streamIds.append(streamId)  # Return stream

        return outdict
