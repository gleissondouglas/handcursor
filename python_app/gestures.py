import math
from enum import Enum
from hand_tracker import HandData
import config

class Gesture(Enum):
    PINCH_INDEX = "PINCH_INDEX"   # Index and thumb touching
    PINCH_MIDDLE = "PINCH_MIDDLE" # Middle and thumb touching
    OPEN_HAND = "OPEN_HAND"       # Hand completely open
    RELAXED = "RELAXED"           # None of the above (default navigation)

class GestureRecognizer:
    def __init__(self):
        # State tracking for hysteresis
        self.current_gesture = Gesture.RELAXED
        self.consecutive_frames = 0
        self.last_raw_gesture = Gesture.RELAXED

    @staticmethod
    def _distance_3d(p1: tuple[float, float, float], p2: tuple[float, float, float]) -> float:
        dx = p1[0] - p2[0]
        dy = p1[1] - p2[1]
        dz = p1[2] - p2[2]
        return math.sqrt(dx * dx + dy * dy + dz * dz)

    def detect(self, hand: HandData) -> Gesture:
        # Hand Scale: max distance between wrist, index_mcp, and pinky_mcp in 3D
        edge1 = self._distance_3d(hand.index_mcp, hand.wrist)
        edge2 = self._distance_3d(hand.index_mcp, hand.pinky_mcp)
        edge3 = self._distance_3d(hand.wrist, hand.pinky_mcp)
        hand_scale = max(edge1, edge2, edge3)

        if hand_scale < 0.01:
            return self.current_gesture

        # Distances from thumb tip to other fingertips
        dist_index = self._distance_3d(hand.thumb_tip, hand.index_tip) / hand_scale
        
        if hand.middle_tip:
            dist_middle = self._distance_3d(hand.thumb_tip, hand.middle_tip) / hand_scale
        else:
            dist_middle = float('inf')

        # Check for OPEN_HAND (all fingers extended)
        # Using distance from wrist to fingertips to check extension
        is_open = False
        if hand.middle_tip and hand.ring_tip and hand.pinky_tip:
            d_i = self._distance_3d(hand.index_tip, hand.wrist) / hand_scale
            d_m = self._distance_3d(hand.middle_tip, hand.wrist) / hand_scale
            d_r = self._distance_3d(hand.ring_tip, hand.wrist) / hand_scale
            d_p = self._distance_3d(hand.pinky_tip, hand.wrist) / hand_scale
            d_t = self._distance_3d(hand.thumb_tip, hand.wrist) / hand_scale
            
            if (d_i > config.SCROLL_INDEX_FACTOR and 
                d_m > config.SCROLL_MIDDLE_FACTOR and 
                d_r > config.SCROLL_RING_FACTOR and 
                d_p > config.SCROLL_PINKY_FACTOR and 
                d_t > config.SCROLL_THUMB_FACTOR):
                is_open = True

        # Determine raw gesture based on hysteresis thresholds
        raw_gesture = Gesture.RELAXED

        # Priorities: PINCH_INDEX > PINCH_MIDDLE > OPEN_HAND > RELAXED
        if self.current_gesture == Gesture.PINCH_INDEX:
            if dist_index < config.PINCH_EXIT:
                raw_gesture = Gesture.PINCH_INDEX
        else:
            if dist_index < config.PINCH_ENTER:
                raw_gesture = Gesture.PINCH_INDEX

        if raw_gesture == Gesture.RELAXED:
            if self.current_gesture == Gesture.PINCH_MIDDLE:
                if dist_middle < config.PINCH_EXIT:
                    raw_gesture = Gesture.PINCH_MIDDLE
            else:
                if dist_middle < config.PINCH_ENTER:
                    raw_gesture = Gesture.PINCH_MIDDLE

        if raw_gesture == Gesture.RELAXED and is_open:
            raw_gesture = Gesture.OPEN_HAND

        # Debouncing
        if raw_gesture == self.last_raw_gesture:
            self.consecutive_frames += 1
        else:
            self.consecutive_frames = 1
            self.last_raw_gesture = raw_gesture

        # Confirm gesture if held for enough frames
        if self.consecutive_frames >= config.GESTURE_MIN_FRAMES:
            self.current_gesture = raw_gesture
        
        return self.current_gesture
