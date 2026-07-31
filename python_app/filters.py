# =========================================================================
# FILTROS MATEMÁTICOS DE SUAVIZAÇÃO — Portagem 1:1 do Swift
# =========================================================================
from __future__ import annotations
import math


class LowPassFilter:
    """Filtro Passa-Baixa: suaviza movimentos rápidos, reduzindo tremor natural da mão."""

    def __init__(self):
        self.y: float | None = None

    def apply(self, value: float, alpha: float) -> float:
        if self.y is not None:
            result = alpha * value + (1.0 - alpha) * self.y
            self.y = result
            return result
        else:
            self.y = value
            return value


class OneEuroFilter:
    """
    One Euro Filter: estabiliza o cursor quando a mão está parada (min_cutoff)
    e permite movimentos rápidos e fluidos quando a mão se move (beta).

    Portagem direta do Swift — mesma lógica matemática.
    """

    def __init__(self, min_cutoff: float = 1.0, beta: float = 0.0, d_cutoff: float = 1.0):
        self.min_cutoff = min_cutoff
        self.beta = beta
        self._d_cutoff = d_cutoff
        self._x_filter = LowPassFilter()
        self._dx_filter = LowPassFilter()

    def _smoothing_factor(self, te: float, cutoff: float) -> float:
        r = 2.0 * math.pi * cutoff * te
        return r / (r + 1.0)

    def filter(self, value: float, timestamp: float) -> float:
        te = 1.0 / 30.0  # Delta fixo assumindo ~30 FPS do MediaPipe

        if self._x_filter.y is not None:
            dx = (value - self._x_filter.y) / te
            alpha_dx = self._smoothing_factor(te, self._d_cutoff)
            smoothed_dx = self._dx_filter.apply(dx, alpha_dx)

            cutoff = self.min_cutoff + self.beta * abs(smoothed_dx)
            alpha = self._smoothing_factor(te, cutoff)
            smoothed_x = self._x_filter.apply(value, alpha)
            return smoothed_x
        else:
            self._x_filter.apply(value, 1.0)
            self._dx_filter.apply(0.0, 1.0)
            return value

    def lock_position(self, position: float):
        """Força o filtro a assumir uma posição exata (travamento de mira)."""
        self._x_filter.y = position
        self._dx_filter.y = 0.0
