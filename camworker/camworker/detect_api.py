import logging

import numpy as np

from . import detect_util

_log = logging.getLogger(__name__)

try:
    from .xfdnnpyapi import XFDNNPyAPI
except ImportError as e:
    print("Failed to import XFDNNPyAPI, using mock: %s" % e)
    # Mock
    class XFDNNPyAPI(object):
        def __init__(self, params):
            pass

        def forward(self, bottom):
            from ._example import example
            return {
                "pixel-conv": np.array(example["pixel-conv"]),
                "bb-output": np.array(example["bb-output"]),
            }


class Detect(object):
    def __init__(self, root, platform):
        self.root = root
        self.platform = platform

        self.expand_scale_ = 0.0
        self.force_gray_ = False
        self.input_mean_value_ = 128.0
        self.pixel_blob_name_ = "pixel-prob"
        self.bb_blob_name_ = "bb-output-tiled"

        self.res_stride_ = 4
        self.det_threshold_ = 0.7
        self.nms_threshold_ = 0.3
        self.input_channels_ = 3

        self.xfdnn_graph_ = XFDNNPyAPI(
            {
                "batch_sz": 1,
                "cutAfter": "data",
                "inproto": "deploy.prototxt",
                "input_names": ["data"],
                "netcfg": "deploy.compiler.json",
                "outproto": "xfdnn_deploy.prototxt",
                "output_names": ["pixel-conv", "bb-output"],
                "outtrainproto": None,
                "overlaycfg": {
                    "DSA_VERSION": "xilinx_u200_xdma_201820_1",
                    "SDX_VERSION": "2018.2",
                    "XDNN_BITWIDTH": "8",
                    "XDNN_CSR_BASE": "0x1800000, 0x1810000",
                    "XDNN_DDR_BANK": "0, 3",
                    "XDNN_NUM_KERNELS": "2",
                    "XDNN_SLR_IDX": "1, 1",
                    "XDNN_VERSION_MAJOR": "3",
                    "XDNN_VERSION_MINOR": "0",
                },
                "profile": False,
                "quantizecfg": "deploy.compiler_quant.json",
                "trainproto": None,
                "weights": "deploy.caffemodel_data.h5",
                "xclbin": "{}/overlaybins/{}/overlay_4.xclbin".format(
                    self.root, self.platform
                ),
                "xdnnv3": True,
            }
        )

    def detect(self, image):
        # Size is always the same size and may be stretched
        # to make square
        sz = (320, 320)
        # transpose HWC (0,1,2) to CHW (2,0,1)
        transformed_image = np.transpose(image, (2, 0, 1))

        transformed_image = (
            transformed_image - self.input_mean_value_
        )
        # Call FPGA
        output = self.xfdnn_graph_.forward([transformed_image.astype(np.float32)])

        # Put CPU layers into postprocess
        pixel_conv = output["pixel-conv"]
        pixel_conv_tiled = detect_util.GSTilingLayer_forward(pixel_conv, 8)
        prob = detect_util.SoftmaxLayer_forward(pixel_conv_tiled)
        prob = prob[0, 1, ...]

        bb = output["bb-output"]
        bb = detect_util.GSTilingLayer_forward(bb, 8)
        bb = bb[0, ...]

        ##import pdb; pdb.set_trace()
        gy = np.arange(0, sz[0], self.res_stride_)
        gx = np.arange(0, sz[1], self.res_stride_)
        gy = gy[0 : bb.shape[1]]
        gx = gx[0 : bb.shape[2]]
        [x, y] = np.meshgrid(gx, gy)

        # print bb.shape[1],len(gy),sz[0],sz[1]
        bb[0, :, :] += x
        bb[2, :, :] += x
        bb[1, :, :] += y
        bb[3, :, :] += y
        bb = np.reshape(bb, (4, -1)).T
        prob = np.reshape(prob, (-1, 1))
        bb = bb[prob.ravel() > self.det_threshold_, :]
        prob = prob[prob.ravel() > self.det_threshold_, :]
        rects = np.hstack((bb, prob))
        keep = self.nms(rects, self.nms_threshold_)
        rects = rects[keep, :]
        rects_expand = []
        for rect in rects:
            rect_expand = []
            rect_w = rect[2] - rect[0]
            rect_h = rect[3] - rect[1]
            rect_expand.append(int(max(0, rect[0] - rect_w * self.expand_scale_)))
            rect_expand.append(int(max(0, rect[1] - rect_h * self.expand_scale_)))
            rect_expand.append(int(min(sz[1], rect[2] + rect_w * self.expand_scale_)))
            rect_expand.append(int(min(sz[0], rect[3] + rect_h * self.expand_scale_)))
            rects_expand.append(rect_expand)

        return rects_expand

    def nms(self, dets, thresh):
        """Pure Python NMS baseline."""
        x1 = dets[:, 0]
        y1 = dets[:, 1]
        x2 = dets[:, 2]
        y2 = dets[:, 3]
        scores = dets[:, 4]

        areas = (x2 - x1 + 1) * (y2 - y1 + 1)
        order = scores.argsort()[::-1]

        keep = []
        while order.size > 0:
            i = order[0]
            keep.append(i)
            xx1 = np.maximum(x1[i], x1[order[1:]])
            yy1 = np.maximum(y1[i], y1[order[1:]])
            xx2 = np.minimum(x2[i], x2[order[1:]])
            yy2 = np.minimum(y2[i], y2[order[1:]])

            w = np.maximum(0.0, xx2 - xx1 + 1)
            h = np.maximum(0.0, yy2 - yy1 + 1)
            inter = w * h
            ovr = inter / (areas[i] + areas[order[1:]] - inter)

            inds = np.where(ovr <= thresh)[0]
            order = order[inds + 1]

        return keep
