import argparse
import json
import logging
import os
from time import time
from uuid import UUID

from redis import StrictRedis
from msgpack import unpackb, packb

from camworker.detect import detect_face
from camworker.worker import RedisWorker

_log = logging.getLogger(__name__)


def process_queue(redis, timeout=30, keep_running=True, verbose=False):
    """
    Processes all images in a redis queue and publishes any
    detected face boxes to a reqis pubsub.

    Args:
        redis (Redis): Redis client
        timeout (int): Max time in seconds to block for a message in queue
        keep_running (bool): True to run forever. False to run until queue
            is empty.
    """
    _log.info("Processing image queue")
    worker = RedisWorker(redis, queue="images", timeout=timeout, verbose=verbose)
    for item in worker.run():
        if item is None:
            if not keep_running:
                _log.info("Stopping")
                return
            else:
                _log.debug("Queue empty")
                continue

        decoded = unpackb(item, raw=False)
        client_id = UUID(bytes=decoded["clientId"]).hex
        publish_time = decoded["published"]
        start_time = time()
        rects = detect_face(decoded["image"])
        duration = time() - start_time

        for r in rects:
            box = dict(c=client_id, t="box", **r.jsonify())
            channel = "clients.faces.%s" % client_id
            redis.publish(channel, json.dumps(box))

        # All string values must be unicode for MsgPack
        detected = {
            u"c": unicode(client_id),
            u"t": u"box",
            u"ptime": int(duration * 1000),
            u"qtime": int(((time() * 1000) - publish_time)),
            u"rects": [r.jsonify() for r in rects],
            u"image": decoded["image"],
        }

        if decoded.get("resultTopic", None):
            redis.publish(
                decoded["resultTopic"], packb(detected, use_bin_type=True)
            )


def main():
    parser = argparse.ArgumentParser(description="Camworker")
    parser.add_argument("--verbose", action="store_true", default=False)

    args = parser.parse_args()

    logging.basicConfig(
        level=logging.DEBUG,
        format="%(processName)s:%(asctime)s:%(name)s: %(levelname)s %(message)s",
    )
    redis_url = os.environ.get("REDIS", None)
    if redis_url:
        redis = StrictRedis.from_url(redis_url)
    else:
        redis = StrictRedis()

    try:
        process_queue(redis, verbose=args.verbose)
    except KeyboardInterrupt:
        print("Abort.")
