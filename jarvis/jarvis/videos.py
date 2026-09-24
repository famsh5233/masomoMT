"""Existing Masomo video lessons, served from the old masomo.co.tz backend.

The old app fetched `week_videos?week=N` directly and returned a list of
{title, size, url}. We fetch it server-side so Pro rules are applied in one place
and the app does not depend on the old API's shape.
"""
from __future__ import annotations

import time
from dataclasses import dataclass, field

import httpx

from .config import Settings

CACHE_SECONDS = 600


class VideoSourceError(Exception):
    pass


@dataclass
class VideoLibrary:
    settings: Settings
    http: httpx.Client = field(default_factory=lambda: httpx.Client(timeout=15, follow_redirects=True))
    _cache: dict[int, tuple[float, list[dict]]] = field(default_factory=dict)

    def week(self, week: int) -> list[dict]:
        hit = self._cache.get(week)
        if hit and time.time() - hit[0] < CACHE_SECONDS:
            return hit[1]
        url = self.settings.legacy_videos_url.format(week=week)
        try:
            r = self.http.get(url)
            r.raise_for_status()
            raw = r.json()
        except (httpx.HTTPError, ValueError) as e:
            raise VideoSourceError(f"video source unavailable: {e}") from e
        videos = []
        for item in raw if isinstance(raw, list) else []:
            if not isinstance(item, dict):
                continue
            link = str(item.get("url") or "")
            if not link.startswith(("https://", "http://")):
                continue
            videos.append({"title": str(item.get("title") or f"Video {len(videos) + 1}")[:200],
                           "size": str(item.get("size") or ""), "url": link})
        self._cache[week] = (time.time(), videos)
        return videos
