# =========================================================================
# HAND TRACKER — Wrapper MediaPipe Hands
# Substitui o Vision Framework + HandTracker + PersistentPoint do Swift.
# MediaPipe já faz interpolação interna — PersistentPoint não é necessário.
# =========================================================================
from __future__ import annotations
import mediapipe as mp
import numpy as np
from dataclasses import dataclass


# Atalhos para landmarks do MediaPipe
_HL = mp.solutions.hands.HandLandmark

# Mapeamento dos landmarks que usamos (nomes → índices MediaPipe)
LANDMARKS = {
    "index_tip": _HL.INDEX_FINGER_TIP,       # 8
    "index_mcp": _HL.INDEX_FINGER_MCP,       # 5
    "thumb_tip": _HL.THUMB_TIP,              # 4
    "wrist": _HL.WRIST,                      # 0
    "pinky_mcp": _HL.PINKY_MCP,              # 17
    "middle_tip": _HL.MIDDLE_FINGER_TIP,     # 12
    "ring_tip": _HL.RING_FINGER_TIP,         # 16
    "pinky_tip": _HL.PINKY_TIP,              # 20
}


@dataclass
class HandData:
    """Dados extraídos da mão — coordenadas normalizadas [0.0, 1.0]."""
    index_tip: tuple[float, float]
    index_mcp: tuple[float, float]
    thumb_tip: tuple[float, float]
    wrist: tuple[float, float]
    pinky_mcp: tuple[float, float]
    middle_tip: tuple[float, float] | None = None
    ring_tip: tuple[float, float] | None = None
    pinky_tip: tuple[float, float] | None = None


class HandTracker:
    """
    Wrapper do MediaPipe Hands.
    
    Uso:
        tracker = HandTracker()
        hand = tracker.process(frame)
        if hand:
            print(hand.index_tip)  # (x, y) normalizado
    """

    def __init__(self, max_hands: int = 1, min_detection: float = 0.7, min_tracking: float = 0.6):
        self._hands = mp.solutions.hands.Hands(
            static_image_mode=False,
            max_num_hands=max_hands,
            min_detection_confidence=min_detection,
            min_tracking_confidence=min_tracking,
        )
        self.mp_draw = mp.solutions.drawing_utils
        self.mp_hands = mp.solutions.hands

    def process(self, frame_rgb: np.ndarray) -> HandData | None:
        """
        Processa um frame RGB e retorna os dados da mão, ou None se nenhuma mão for detectada.
        
        Args:
            frame_rgb: Frame da câmera em formato RGB (não BGR!).
            
        Returns:
            HandData com coordenadas normalizadas, ou None.
        """
        results = self._hands.process(frame_rgb)

        if not results.multi_hand_landmarks:
            return None

        landmarks = results.multi_hand_landmarks[0]

        # Extrair landmarks obrigatórios
        try:
            idx_tip = landmarks.landmark[_HL.INDEX_FINGER_TIP]
            idx_mcp = landmarks.landmark[_HL.INDEX_FINGER_MCP]
            thumb_tip = landmarks.landmark[_HL.THUMB_TIP]
            wrist = landmarks.landmark[_HL.WRIST]
            pinky_mcp = landmarks.landmark[_HL.PINKY_MCP]
        except (IndexError, AttributeError):
            return None

        # Landmarks opcionais (para scroll)
        mid_tip = landmarks.landmark[_HL.MIDDLE_FINGER_TIP]
        ring_tip = landmarks.landmark[_HL.RING_FINGER_TIP]
        pinky_tip = landmarks.landmark[_HL.PINKY_TIP]

        return HandData(
            index_tip=(idx_tip.x, idx_tip.y),
            index_mcp=(idx_mcp.x, idx_mcp.y),
            thumb_tip=(thumb_tip.x, thumb_tip.y),
            wrist=(wrist.x, wrist.y),
            pinky_mcp=(pinky_mcp.x, pinky_mcp.y),
            middle_tip=(mid_tip.x, mid_tip.y) if mid_tip else None,
            ring_tip=(ring_tip.x, ring_tip.y) if ring_tip else None,
            pinky_tip=(pinky_tip.x, pinky_tip.y) if pinky_tip else None,
        )

    def draw_landmarks(self, frame, results=None):
        """Desenha os landmarks na imagem (para debug visual)."""
        if results and results.multi_hand_landmarks:
            for hand_lm in results.multi_hand_landmarks:
                self.mp_draw.draw_landmarks(
                    frame, hand_lm, self.mp_hands.HAND_CONNECTIONS
                )

    def close(self):
        """Libera os recursos do MediaPipe."""
        self._hands.close()
