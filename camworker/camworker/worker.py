import logging

_log = logging.getLogger(__name__)


class RedisWorker(object):
    """
    A worker that will pull images out of a Redis queue
    and run the detect method on them.
    """

    def __init__(self, redis, queue, timeout=None, verbose=False):
        self.redis = redis
        self.queue = queue
        self.timeout = timeout
        self.verbose = verbose
        self.items = 0
        self.bytes = 0
        self._run = True

    def next(self):
        """
        Pull the next item out of the queue and process it
        """
        if self.verbose:
            _log.debug(
                "Waiting for item in queue '%s' with timeout %ds"
                % (self.queue, self.timeout)
            )
        item = self.redis.blpop([self.queue], timeout=self.timeout)
        if item:
            self.items += 1
            self.bytes += len(item[1])
            if self.verbose:
                _log.debug(
                    "Processing item from '%s' that is %d bytes"
                    % (item[0], len(item[1]))
                )
            elif not (self.items % 100):
                _log.debug(
                    "Processed %d items with average %d bytes per item"
                    % (self.items, int(float(self.bytes) / self.items))
                )
            return item[1]

    def run(self):
        _log.info("Running queue worker for '%s'" % self.queue)
        while self._run:
            yield self.next()
