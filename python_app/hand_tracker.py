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


@dataclass
class HandData:
    """Dados extraídos da mão — coordenadas normalizadas [0.0, 1.0] em x, y e profundidade em z."""
    index_tip: tuple[float, float, float]
    index_mcp: tuple[float, float, float]
    thumb_tip: tuple[float, float, float]
    wrist: tuple[float, float, float]
    pinky_mcp: tuple[float, float, float]
    middle_tip: tuple[float, float, float] | None = None
    ring_tip: tuple[float, float, float] | None = None
    pinky_tip: tuple[float, float, float] | None = None


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
        import config
        self._hands = mp.solutions.hands.Hands(
            static_image_mode=False,
            max_num_hands=max_hands,
            model_complexity=config.MODEL_COMPLEXITY,  # 0=Lite (~2ms) vs 1=Full (~8ms)
            min_detection_confidence=min_detection,
            min_tracking_confidence=min_tracking,
        )

    def process(self, frame_rgb: np.ndarray) -> HandData | None:
        """
        Processa um frame RGB e retorna os dados da mão, ou None se nenhuma mão for detectada.
        
        Args:
            frame_rgb: Frame da câmera em formato RGB (não BGR!).
            
        Returns:
            HandData com coordenadas normalizadas, ou None.
        """
        # Zero-copy: marcar como não-escrevível evita cópia interna do MediaPipe
        frame_rgb.flags.writeable = False
        results = self._hands.process(frame_rgb)
        frame_rgb.flags.writeable = True

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
            index_tip=(idx_tip.x, idx_tip.y, idx_tip.z),
            index_mcp=(idx_mcp.x, idx_mcp.y, idx_mcp.z),
            thumb_tip=(thumb_tip.x, thumb_tip.y, thumb_tip.z),
            wrist=(wrist.x, wrist.y, wrist.z),
            pinky_mcp=(pinky_mcp.x, pinky_mcp.y, pinky_mcp.z),
            middle_tip=(mid_tip.x, mid_tip.y, mid_tip.z) if mid_tip else None,
            ring_tip=(ring_tip.x, ring_tip.y, ring_tip.z) if ring_tip else None,
            pinky_tip=(pinky_tip.x, pinky_tip.y, pinky_tip.z) if pinky_tip else None,
        )


    def close(self):
        """Libera os recursos do MediaPipe."""
        self._hands.close()
