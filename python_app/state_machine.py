# =========================================================================
# MÁQUINA DE ESTADOS — ARQUITETURA PINCH (Python)
#
# Inspirada no Apple Vision Pro:
# - Mão relaxada / apontando = Move o cursor
# - Pinça (Polegar + Indicador) = Clique e Arraste
# - Pinça (Polegar + Médio) = Clique Direito
# - Mão Aberta (5 dedos) = Scroll
# =========================================================================
import math
import time
from enum import IntEnum

import config
from filters import LowPassFilter, OneEuroFilter
from mouse_injector import (
    post_mouse_event, post_scroll_event, get_screen_bounds,
    MOUSE_MOVED, LEFT_MOUSE_DOWN, LEFT_MOUSE_UP, LEFT_MOUSE_DRAGGED,
    RIGHT_MOUSE_DOWN, RIGHT_MOUSE_UP
)
from hand_tracker import HandData
from gestures import GestureRecognizer, Gesture


class StateMachine:
    """
    Controla toda a lógica do mouse virtual mapeando gestos para ações do macOS.
    """

    def __init__(self):
        # Tela
        self.screen_w, self.screen_h = get_screen_bounds()

        # Reconhecedor de gestos
        self.recognizer = GestureRecognizer()

        # Filtros de suavização
        self.pre_filter_x = LowPassFilter()
        self.pre_filter_y = LowPassFilter()
        self.euro_x = OneEuroFilter(config.EURO_MIN_CUTOFF, config.EURO_BETA, config.EURO_D_CUTOFF)
        self.euro_y = OneEuroFilter(config.EURO_MIN_CUTOFF, config.EURO_BETA, config.EURO_D_CUTOFF)
        
        self.drag_filter_x = LowPassFilter()
        self.drag_filter_y = LowPassFilter()

        # Estado do Cursor
        self.cursor_pos = (self.screen_w / 2.0, self.screen_h / 2.0)
        
        # Micro-lock (congelamento temporário no clique para evitar tremor)
        self.lock_until = 0.0

        # Estado do Arraste
        self.drag_active = False
        self.anchor_hand_pos = (0.0, 0.0)
        self.cursor_anchor = (0.0, 0.0)
        self.drag_offset = (0.0, 0.0)

        # Temporização de cliques
        self.last_click_release = 0.0
        self.time_entered_click = 0.0
        self.click_count = 1
        self._mouse_is_down = False
        self.current_click_type = None  # Pode ser LEFT ou RIGHT

        # Scroll
        self.scroll_anchor_y = 0.0
        self.last_scroll_time = 0.0
        self.time_entered_scroll = 0.0
        self._scroll_accumulator = 0.0
        self.is_scrolling = False

        self._last_log_time = 0.0

    def _map_to_screen(self, cam_point: tuple[float, float, float]) -> tuple[float, float]:
        """Mapeia coordenadas normalizadas da câmera para coordenadas absolutas da tela."""
        margin = config.SCREEN_MARGIN
        x = (cam_point[0] - margin) / (1.0 - 2.0 * margin)
        y = (cam_point[1] - margin) / (1.0 - 2.0 * margin)
        x = max(0.0, min(1.0, x))
        y = max(0.0, min(1.0, y))
        return x * self.screen_w, y * self.screen_h

    def handle_lost_tracking(self):
        """Libera os botões caso a mão saia do frame."""
        if self._mouse_is_down:
            event_up = LEFT_MOUSE_UP if self.current_click_type == "LEFT" else RIGHT_MOUSE_UP
            post_mouse_event(event_up, self.cursor_pos, click_count=self.click_count, is_right_click=(self.current_click_type == "RIGHT"))
            self._mouse_is_down = False
            self.drag_active = False
            self.current_click_type = None
            print("⚠️ [SAFETY] Mão perdida! Mouse liberado para evitar travamento.")
            
        if self.is_scrolling:
            self.is_scrolling = False
            self._scroll_accumulator = 0.0
            print("⚠️ [SAFETY] Mão perdida! Saindo do modo scroll.")

    def _log(self, gesture: Gesture):
        now = time.time()
        if now - self._last_log_time > 0.5:
            print(f"Gesto atual: {gesture.value}")
            self._last_log_time = now

    def process(self, hand: HandData):
        now = time.time()
        
        # Detecta o gesto atual
        gesto_atual = self.recognizer.detect(hand)
        self._log(gesto_atual)

        # Ponto de rastreamento: usamos o "Pinch Center" (ponto médio entre indicador e polegar)
        # Isso dá mais estabilidade quando os dedos se fecham
        track_point = ((hand.index_tip[0] + hand.thumb_tip[0]) / 2,
                       (hand.index_tip[1] + hand.thumb_tip[1]) / 2,
                       (hand.index_tip[2] + hand.thumb_tip[2]) / 2)
        
        raw_mapped = self._map_to_screen(track_point)

        # Resolução do mapeamento via config.py
        action_left = config.ACTION_MAP.get("LEFT_CLICK_DRAG")
        action_right = config.ACTION_MAP.get("RIGHT_CLICK")
        action_scroll = config.ACTION_MAP.get("SCROLL")

        # Prioridade de Ações: Scroll > Clique Direito > Clique Esquerdo > Navegação
        
        # --- SCROLL ---
        if gesto_atual.value == action_scroll:
            if not self.is_scrolling:
                self.is_scrolling = True
                self.scroll_anchor_y = raw_mapped[1]
                self.time_entered_scroll = now
                self._scroll_accumulator = 0.0
                print("↕️ [SCROLL] Entrando no modo scroll")
            
            if now - self.time_entered_scroll >= config.SCROLL_HOLD_TIME:
                delta_y = self.scroll_anchor_y - raw_mapped[1]
                
                if abs(delta_y) > config.SCROLL_DEAD_ZONE and now - self.last_scroll_time > config.SCROLL_MIN_INTERVAL:
                    raw_delta = delta_y - (config.SCROLL_DEAD_ZONE if delta_y > 0 else -config.SCROLL_DEAD_ZONE)
                    magnitude = abs(raw_delta)
                    speed = magnitude * magnitude * config.SCROLL_ACCELERATION
                    scroll_speed = -speed if delta_y > 0 else speed

                    self._scroll_accumulator += scroll_speed
                    int_scroll = int(self._scroll_accumulator)

                    if int_scroll != 0:
                        post_scroll_event(float(int_scroll))
                        self._scroll_accumulator -= int_scroll
                        self.last_scroll_time = now
            return
        elif self.is_scrolling:
            self.is_scrolling = False
            self._scroll_accumulator = 0.0
            print("↕️ [SCROLL] Saindo do modo scroll")

        # --- CLIQUE DIREITO ---
        if gesto_atual.value == action_right:
            if not self._mouse_is_down:
                self._mouse_is_down = True
                self.current_click_type = "RIGHT"
                self.lock_until = now + config.MICRO_LOCK_DURATION
                post_mouse_event(RIGHT_MOUSE_DOWN, self.cursor_pos, is_right_click=True)
                print("🖱️ [CLIQUE DIREITO] Pressionado")
            
            if now < self.lock_until:
                # Congelado para absorver o tremor do clique
                pass
            else:
                self._update_cursor(raw_mapped, now)
            return

        # --- CLIQUE ESQUERDO / ARRASTE ---
        if gesto_atual.value == action_left:
            if not self._mouse_is_down:
                # Inicia o clique
                interval = now - self.last_click_release
                if config.BOUNCE_FILTER_TIME < interval <= config.DOUBLE_CLICK_WINDOW and self.last_click_release > 0:
                    self.click_count = 2
                    print("🔥 [CLIQUE DUPLO] Ativado")
                elif interval <= config.BOUNCE_FILTER_TIME and self.last_click_release > 0:
                    print("⚠️ [BOUNCE] Tremor ignorado")
                    return
                else:
                    self.click_count = 1
                    print("👆 [CLIQUE SIMPLES] Pressionado")
                
                self._mouse_is_down = True
                self.current_click_type = "LEFT"
                self.time_entered_click = now
                self.drag_active = False
                self.anchor_hand_pos = raw_mapped
                self.cursor_anchor = self.cursor_pos
                
                # Micro-lock evita que o cursor ande sozinho quando o dedo e o polegar se chocam
                self.lock_until = now + config.MICRO_LOCK_DURATION
                
                post_mouse_event(LEFT_MOUSE_DOWN, self.cursor_pos, click_count=self.click_count)
            
            else:
                # Já está pressionado - Trata arraste
                if now >= self.lock_until:
                    # Inicia drag se mover mais que o threshold
                    if not self.drag_active:
                        dx = raw_mapped[0] - self.anchor_hand_pos[0]
                        dy = raw_mapped[1] - self.anchor_hand_pos[1]
                        dist = math.sqrt(dx*dx + dy*dy)
                        
                        # Converter drag threshold de normalizado para pixels de tela
                        # Usando uma estimativa simples baseada na largura da tela
                        threshold_px = self.screen_w * config.DRAG_DISTANCE_THRESHOLD
                        
                        if dist > threshold_px:
                            self.drag_active = True
                            self.drag_filter_x.y = self.cursor_pos[0]
                            self.drag_filter_y.y = self.cursor_pos[1]
                            self.drag_offset = (self.cursor_pos[0] - raw_mapped[0], 
                                                self.cursor_pos[1] - raw_mapped[1])
                            print("🔄 [ARRASTE] Iniciado")

                    if self.drag_active:
                        target_x = raw_mapped[0] + self.drag_offset[0]
                        target_y = raw_mapped[1] + self.drag_offset[1]
                        
                        filt_x = self.drag_filter_x.apply(target_x, config.DRAG_FILTER_ALPHA)
                        filt_y = self.drag_filter_y.apply(target_y, config.DRAG_FILTER_ALPHA)
                        
                        self.cursor_pos = (max(0, min(self.screen_w, filt_x)), 
                                           max(0, min(self.screen_h, filt_y)))
                        
                        post_mouse_event(LEFT_MOUSE_DRAGGED, self.cursor_pos, click_count=self.click_count)
            return

        # --- NAVEGAÇÃO LIVRE (RELAXED) ---
        if self._mouse_is_down:
            # Soltou o clique
            event_up = LEFT_MOUSE_UP if self.current_click_type == "LEFT" else RIGHT_MOUSE_UP
            post_mouse_event(event_up, self.cursor_pos, click_count=self.click_count, is_right_click=(self.current_click_type == "RIGHT"))
            self._mouse_is_down = False
            self.drag_active = False
            self.last_click_release = now
            self.current_click_type = None
            print("🛑 [SOLTAR] Clique finalizado")

        self._update_cursor(raw_mapped, now)

    def _update_cursor(self, raw_mapped: tuple[float, float], now: float):
        """Aplica os filtros de suavização e move o cursor."""
        pre_x = self.pre_filter_x.apply(raw_mapped[0], config.PRE_FILTER_ALPHA)
        pre_y = self.pre_filter_y.apply(raw_mapped[1], config.PRE_FILTER_ALPHA)
        filt_x = self.euro_x.filter(pre_x, now)
        filt_y = self.euro_y.filter(pre_y, now)

        self.cursor_pos = (filt_x, filt_y)
        post_mouse_event(MOUSE_MOVED, self.cursor_pos)
