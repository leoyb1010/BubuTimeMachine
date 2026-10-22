"""Minimal FSRS-4.5 scheduler (default weights), two ratings: Again=1, Good=3.

Reviews are folded per local day: a day with any failure counts as Again.
"""
from __future__ import annotations

from datetime import date as Date, timedelta
import math

W = (0.4872, 1.4003, 3.7145, 13.8206, 5.1618, 1.2298, 0.8975, 0.031, 1.6474, 0.1367,
     1.0461, 2.1072, 0.0793, 0.3246, 1.587, 0.2272, 2.8755)
DECAY, FACTOR = -0.5, 19 / 81
AGAIN, GOOD = 1, 3
RETENTION = 0.85


def retrievability(elapsed_days: float, stability: float) -> float:
    return (1 + FACTOR * max(0.0, elapsed_days) / stability) ** DECAY


def interval(stability: float, retention: float = RETENTION) -> int:
    days = stability / FACTOR * (retention ** (1 / DECAY) - 1)
    return max(1, min(36500, round(days)))


def _init_difficulty(rating: int) -> float:
    return W[4] - (rating - 3) * W[5]


def _clamp(value: float) -> float:
    return min(10.0, max(1.0, value))


def schedule(reviews: list[tuple[Date, int]]):
    """reviews: (day, rating) in any order. Returns (stability, difficulty, last_day) or None."""
    days: dict[Date, int] = {}
    for day, rating in reviews:
        days[day] = min(days.get(day, GOOD), rating)
    stability = difficulty = last = None
    for day in sorted(days):
        rating = days[day]
        if stability is None:
            stability, difficulty = W[rating - 1], _clamp(_init_difficulty(rating))
        else:
            r = retrievability((day - last).days, stability)
            difficulty = _clamp(W[7] * _init_difficulty(3) + (1 - W[7]) * (difficulty - W[6] * (rating - 3)))
            if rating == AGAIN:
                stability = min(stability, W[11] * difficulty ** -W[12] * ((stability + 1) ** W[13] - 1)
                                * math.exp(W[14] * (1 - r)))
            else:
                stability = stability * (1 + math.exp(W[8]) * (11 - difficulty) * stability ** -W[9]
                                         * (math.exp(W[10] * (1 - r)) - 1))
        last = day
    return (stability, difficulty, last) if last else None


def due(reviews: list[tuple[Date, int]], today: Date):
    """(is_due, retrievability_today, last_rating) for a card with history; None if new."""
    state = schedule(reviews)
    if state is None:
        return None
    stability, _, last = state
    last_rating = min(r for d, r in reviews if d == last)
    return last + timedelta(days=interval(stability)) <= today, retrievability((today - last).days, stability), last_rating
