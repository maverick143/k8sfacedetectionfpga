import logging
import os
from collections import namedtuple

import cv2
import numpy as np

from .detect_api import Detect

_log = logging.getLogger(__name__)

det = Detect(
    os.getenv("MLSUITE_ROOT", "/home/ubuntu/app/ml-suite"),
    os.getenv("MLSUITE_PLATFORM", "aws"),
)


class Rect(namedtuple("Rect", ("ratio", "label", "x", "y", "width", "height"))):
    """
    Coordinates and label for outlines of a detected object.
    """

    def jsonify(self):
        return {
            u"x": self.x,
            u"y": self.y * self.ratio,
            u"w": self.width,
            u"h": self.height * self.ratio,
            u"l": unicode(self.label),
        }


def detect_face(image_binary, width=320):
    """
    Detect faces in image

    Args:
        image_binary (bytes): Raw image binary
        width (int): Width in pixels to scale image to

    Returns:
        list[Rect]: List of rectangle coordinates
    """
    npimg = np.asarray(bytearray(image_binary), dtype=np.uint8)
    img = cv2.imdecode(npimg, cv2.IMREAD_COLOR)
    h, w, _ = img.shape
    ratio = float(h) / float(w)
    # Make image square. Otherwise the detect code fails. Will fix
    # ratio in detection rectangles.
    new_size = (width, width)
    if (w, h) != new_size:
        img = cv2.resize(img, new_size, interpolation=cv2.INTER_LINEAR)
    face_rects = det.detect(img)
    return [Rect(ratio, "face", *r) for r in face_rects]


