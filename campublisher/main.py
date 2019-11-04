import argparse
import json
import logging
import os
import asyncio
from glob import glob
from time import time
from uuid import uuid4

import aioredis
from msgpack import unpackb, packb

_log = logging.getLogger("campublisher")
_image_dir = os.path.join(os.path.dirname(__file__), "images")


MAX_IMAGE_QUEUE_SIZE = 10000


async def main(fps=8):
    """
    Args:
        fps (int): Number of frames to publish per second
    """

    images = []
    for root, dirnames, _ in os.walk(_image_dir):
        for dir in dirnames:
            for image in glob(os.path.join(root, dir, "*.jpg")):
                with open(image, "rb") as f:
                    images.append((dir, os.path.basename(image), f.read()))

    images.sort()
    _log.debug("%s images loaded to publish" % (len(images),))

    redis = await aioredis.create_redis_pool(os.environ.get("REDIS", None))

    control_channels = await redis.subscribe("campublisher.control")
    config = {"desired_clients": 0}
    publish_tasks = []

    async def trim():
        while True:
            await redis.ltrim("images", 0, MAX_IMAGE_QUEUE_SIZE)
            await asyncio.sleep(1)

    async def publish(show_in_admin=False):
        client_id = uuid4()
        if show_in_admin:
            _log.debug("New show in admin client %s" % client_id.hex)
        else:
            _log.debug("New client %s" % client_id.hex)
        while True:
            if show_in_admin:
                _log.debug(
                    "%s: Publish %s images at %s FPS"
                    % (client_id.hex, len(images), fps)
                )

            for dir, name, image in images:
                message = packb(
                    {
                        "image": image,
                        "published": int(time() * 1000),
                        "clientId": client_id.bytes,
                        "resultTopic": "campublisher.detected.%s" % client_id.hex
                        if show_in_admin
                        else None,
                    },
                    use_bin_type=True,
                )
                await redis.rpush("images", message)
                await asyncio.sleep(1 / fps)

    async def control_reader(channel):
        async for message in channel.iter():
            message = unpackb(message, raw=False)
            _log.debug("Got control message: %s" % message)
            if message["type"] == "desired_clients":
                value = max(0, min(message["value"], 500))
                if config["desired_clients"] != value:
                    _log.info(
                        "Set desired clients from %s to %s"
                        % (config["desired_clients"], value)
                    )
                    config["desired_clients"] = value

    async def update_desired_clients():
        current = config["desired_clients"]
        while True:
            value = config["desired_clients"]
            if current != value:
                _log.info("Scale from %s to %s clients" % (current, value))
                current = value

                # Empty redis queue
                await redis.delete("images")

                # Scale down
                while len(publish_tasks) > current:
                    publish_tasks.pop().cancel()

                # Scale up
                while len(publish_tasks) < current:
                    publish_tasks.append(
                        asyncio.create_task(publish(len(publish_tasks) == 0))
                    )

            await redis.publish(
                "campublisher.control_changed",
                json.dumps({"t": "desired_clients", "v": current}),
            )

            await asyncio.sleep(1)

    control_task = asyncio.create_task(control_reader(control_channels[0]))
    trim_task = asyncio.create_task(trim())
    update_desired_clients_task = asyncio.create_task(update_desired_clients())
    tasks = [control_task, trim_task, update_desired_clients_task]

    await asyncio.gather(*tasks)

    redis.close()
    await redis.wait_closed()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Campublisher")
    parser.add_argument("--verbose", action="store_true", default=False)

    args = parser.parse_args()

    logging.basicConfig(
        level=logging.DEBUG,
        format="%(processName)s:%(asctime)s:%(name)s: %(levelname)s %(message)s",
    )

    asyncio.run(main())
