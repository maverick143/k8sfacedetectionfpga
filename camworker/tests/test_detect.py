import json
import os
import uuid

import numpy
import fakeredis
import pytest

from camworker.detect import detect_face, Rect
from camworker.main import process_queue


@pytest.fixture
def example_image():
    with open(os.path.join(os.path.dirname(__file__), "test.jpg"), "rb") as f:
        return f.read()


@pytest.fixture
def mock_face_detected(monkeypatch):
    with open(os.path.join(os.path.dirname(__file__), "example_detect.json")) as f:
        example_detection = json.loads(f.read())

    mock_data = {
        "pixel-conv": numpy.array(example_detection["pixel-conv"]),
        "bb-output": numpy.array(example_detection["bb-output"]),
    }

    def mock_XFDNNPyAPI_forward(self, bottom):
        return mock_data

    monkeypatch.setattr(
        "camworker.detect_api.XFDNNPyAPI.forward", mock_XFDNNPyAPI_forward
    )
    return mock_data


def test_detect_face(mock_face_detected, example_image):
    """
    Verify face detector returns coordinates and label
    for a face.
    """
    assert mock_face_detected
    results = detect_face(example_image)
    assert results == [Rect(label="face", x=125, y=112, width=260, height=273)]
    assert (
        json.dumps(results[0].jsonify())
        == '{"y": 112, "x": 125, "l": "face", "w": 260, "h": 273}'
    )


def test_process_queue_redis(mock_face_detected, example_image):
    """
    Verify process_queue will process images in Redis and
    publish face detection boxes to a pubsub channel.
    """
    assert mock_face_detected
    redis = fakeredis.FakeStrictRedis()
    pubsub = redis.pubsub()
    pubsub.psubscribe("clients.faces.*")
    assert pubsub.get_message(timeout=1)["type"] == "psubscribe"
    queue = "images"
    client1_id = uuid.uuid4()
    client2_id = uuid.uuid4()

    redis.rpush(queue, client1_id.bytes + example_image)
    redis.rpush(queue, client2_id.bytes + example_image)

    process_queue(redis, timeout=1, keep_running=False)

    message = pubsub.get_message(timeout=1)
    assert message["pattern"] == "clients.faces.*"
    assert message["channel"] == "clients.faces.%s" % client1_id.hex
    assert json.loads(message["data"]) == {
        "c": client1_id.hex,
        "w": 260,
        "x": 125,
        "y": 112,
        "h": 273,
        "l": "face",
    }

    message = pubsub.get_message(timeout=1)
    assert message["pattern"] == "clients.faces.*"
    assert message["channel"] == "clients.faces.%s" % client2_id.hex
    assert json.loads(message["data"]) == {
        "c": client2_id.hex,
        "w": 260,
        "x": 125,
        "y": 112,
        "h": 273,
        "l": "face",
    }
