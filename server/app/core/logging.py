from __future__ import annotations

import inspect
import logging


class TraceLoggerAdapter(logging.LoggerAdapter):
    def process(self, msg, kwargs):
        trace_id = kwargs.pop("trace_id", None) or "-"
        kwargs.setdefault("extra", {})
        kwargs["extra"]["trace_id"] = trace_id
        return (msg, kwargs)


logger = logging.getLogger("app.speech")
log = TraceLoggerAdapter(logger, {})


async def _maybe_await(x):
    """Await value if it's awaitable; otherwise return it directly."""
    return await x if inspect.isawaitable(x) else x
