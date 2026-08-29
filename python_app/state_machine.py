# =========================================================================
# MÁQUINA DE ESTADOS — ARQUITETURA GATILHO COM DEDÃO (Python)
#
# Portagem da v4.0 Swift com mesma lógica, thresholds e proteções.
#
# Fluxo:
#   Navegação (☝️ + dedão recolhido)
#       │ dedão abre em "L" (ratio > 0.26 por 4 frames)
#       ▼
#   Trava de Mira (cursor congelado)
#       │ dedão fecha (ratio < 0.20 por 2 frames)
#       ▼
#   Clique/Arraste (mouseDown ativo)
#       │ dedão abre novamente (ratio > 0.23)
#       ▼
#   Soltar → Navegação
# =========================================================================
import math
import time
from enum import IntEnum

import config
from filters import LowPassFilter, OneEuroFilter
from mouse_injector import (
    post_mouse_event, post_scroll_event, get_screen_bounds,
    MOUSE_MOVED, LEFT_MOUSE_DOWN, LEFT_MOUSE_UP, LEFT_MOUSE_DRAGGED,
)
from hand_tracker import HandData


class AppState(IntEnum):
    NAVEGACAO = 0       # Dedão recolhido, indicador ☝️. Cursor segue indexTip
    TRAVA_MIRA = 1      # Dedão aberto em "L". Cursor congelado no pixel
    CLIQUE_ARRASTE = 2  # Dedão fechou (gatilho puxado). MouseDown ativo
    SOLTAR = 3          # Transição limpa de volta à navegação
    SCROLL = 4          # Mão espalmada (5 dedos) = scroll vertical


class StateMachine:
    """
    Controla toda a lógica do mouse virtual:
    - Navegação pelo indicador
    - Trava de mira pelo dedão em "L"
    - Clique/drag/right-click pelo gatilho do dedão
    - Scroll por mão espalmada
    """

    def __init__(self):
        # Tela
        self.screen_w, self.screen_h = get_screen_bounds()

        # Estado atual
        self.state = AppState.NAVEGACAO

        # Filtros de suavização
        self.pre_filter_x = LowPassFilter()
        self.pre_filter_y = LowPassFilter()
        self.euro_x = OneEuroFilter(config.EURO_MIN_CUTOFF, config.EURO_BETA, config.EURO_D_CUTOFF)
        self.euro_y = OneEuroFilter(config.EURO_MIN_CUTOFF, config.EURO_BETA, config.EURO_D_CUTOFF)
        self.drag_filter_x = LowPassFilter()
        self.drag_filter_y = LowPassFilter()

        # Posições
        self.cursor_pos = (self.screen_w / 2.0, self.screen_h / 2.0)
        self.frozen_pos = self.cursor_pos
        self.anchor_hand_pos = (0.0, 0.0)
        self.cursor_anchor = (0.0, 0.0)
        self.drag_offset = (0.0, 0.0)

        # Estado do dedão com hysteresis
        self.is_thumb_open = False
        self.is_thumb_closed = False
        self.thumb_open_frames = 0
        self.thumb_close_frames = 0

        # Temporização
        self.time_entered_trava = 0.0
        self.time_entered_gatilho = 0.0
        self.last_click_release = 0.0
        self.click_count = 1
        self.drag_active = False
        self.is_right_click = False

        # Scroll
        self.scroll_anchor_y = 0.0
        self.last_scroll_time = 0.0
        self.time_entered_scroll = 0.0
        self.scroll_frames = 0
        self.non_scroll_frames = 0

        # Log throttle
        self._last_log_time = 0.0

        # Scroll sub-pixel accumulator (evita truncamento para 0)
        self._scroll_accumulator = 0.0

        # Flag para tracking ativo (proteção contra mouse travado)
        self._mouse_is_down = False

    # =====================================================================
    # MATEMÁTICA VETORIAL
    # =====================================================================

    @staticmethod
    def _distance(p1: tuple[float, float], p2: tuple[float, float]) -> float:
        dx = p1[0] - p2[0]
        dy = p1[1] - p2[1]
        return math.sqrt(dx * dx + dy * dy)

    def _thumb_trigger_ratio(self, thumb_tip: tuple, index_mcp: tuple, hand_scale: float) -> float:
        """Ratio normalizado thumbTip↔indexMCP. Baixo = recolhido, Alto = aberto em L."""
        if hand_scale < 0.01:
            return 0.0
        return self._distance(thumb_tip, index_mcp) / hand_scale

    def _map_to_screen(self, cam_point: tuple[float, float]) -> tuple[float, float]:
        """Mapeia coordenadas normalizadas da câmera para coordenadas absolutas da tela."""
        margin = config.SCREEN_MARGIN

        x = (cam_point[0] - margin) / (1.0 - 2.0 * margin)
        y = (cam_point[1] - margin) / (1.0 - 2.0 * margin)

        x = max(0.0, min(1.0, x))
        y = max(0.0, min(1.0, y))

        return x * self.screen_w, y * self.screen_h

    def _reset_to_navegacao(self):
        """Reset limpo dos contadores ao voltar para navegação."""
        self.state = AppState.NAVEGACAO
        self.thumb_open_frames = 0
        self.thumb_close_frames = 0
        self.pre_filter_x.y = self.cursor_pos[0]
        self.pre_filter_y.y = self.cursor_pos[1]
        self.euro_x.lock_position(self.cursor_pos[0])
        self.euro_y.lock_position(self.cursor_pos[1])

    def handle_lost_tracking(self):
        """
        Chamado quando a mão sai do campo de visão da câmera.
        Libera qualquer botão de mouse pressionado para evitar que o cursor
        fique permanentemente travado em estado de arraste/clique.
        """
        if self._mouse_is_down:
            dispatch_count = 1 if self.is_right_click else self.click_count
            post_mouse_event(
                LEFT_MOUSE_UP, self.cursor_pos,
                click_count=dispatch_count, is_right_click=self.is_right_click,
            )
            self._mouse_is_down = False
            print("⚠️ [SAFETY] Mão perdida! Mouse liberado para evitar travamento.")

        if self.state != AppState.NAVEGACAO:
            self._reset_to_navegacao()
            print("⚠️ [SAFETY] Estado resetado para NAVEGAÇÃO (mão fora do frame).")

    # =====================================================================
    # LOG
    # =====================================================================

    def _log(self, thumb_ratio: float):
        now = time.time()
        if now - self._last_log_time > 0.5:
            print(
                f"Estado: {self.state.name:15s} | ThumbRatio: {thumb_ratio:.3f} "
                f"| Open:{self.thumb_open_frames} Close:{self.thumb_close_frames} "
                f"| isOpen:{'✅' if self.is_thumb_open else '❌'} "
                f"isClosed:{'✅' if self.is_thumb_closed else '❌'}"
            )
            self._last_log_time = now

    # =====================================================================
    # INICIAR CLIQUE
    # =====================================================================

    def _iniciar_clique(self, now: float, wrist: tuple):
        intervalo = now - self.last_click_release

        if config.BOUNCE_FILTER_TIME < intervalo <= config.DOUBLE_CLICK_WINDOW and self.last_click_release > 0:
            self.click_count = 2
            self.frozen_pos = self.cursor_anchor
            print("🔥 [CLIQUE] Duplo clique")
        elif intervalo <= config.BOUNCE_FILTER_TIME and self.last_click_release > 0:
            print("⚠️ [BOUNCE] Tremor ignorado")
        else:
            self.click_count = 1
            print("👆 [CLIQUE] Clique simples")

        self.is_right_click = False

        # Offset de arraste baseado no wrist
        raw_mapped = self._map_to_screen(wrist)
        self.drag_offset = (self.frozen_pos[0] - raw_mapped[0], self.frozen_pos[1] - raw_mapped[1])

        self.drag_active = False
        self.time_entered_gatilho = now
        self.anchor_hand_pos = wrist
        self.cursor_anchor = self.frozen_pos

        # Travar todos os filtros na posição congelada
        self.drag_filter_x.y = self.frozen_pos[0]
        self.drag_filter_y.y = self.frozen_pos[1]
        self.pre_filter_x.y = self.frozen_pos[0]
        self.pre_filter_y.y = self.frozen_pos[1]
        self.euro_x.lock_position(self.frozen_pos[0])
        self.euro_y.lock_position(self.frozen_pos[1])

        post_mouse_event(LEFT_MOUSE_DOWN, self.frozen_pos, click_count=self.click_count)
        self._mouse_is_down = True

    # =====================================================================
    # PROCESSAMENTO PRINCIPAL — CHAMADO A CADA FRAME
    # =====================================================================

    def process(self, hand: HandData):
        """
        Processa os landmarks da mão e executa a máquina de estados.
        Chamado a cada frame pelo main loop.
        """
        now = time.time()

        # Escala robusta da mão (triângulo indexMCP-wrist-pinkyMCP)
        # Calculamos as distâncias entre pulso, base do indicador e base do mindinho.
        # A maior dessas distâncias é usada como uma "escala mestre" da mão.
        # Por que? Para que o limiar (threshold) do dedão funcione igual se a mão 
        # estiver perto (grande) ou longe (pequena) da câmera.
        edge1 = self._distance(hand.index_mcp, hand.wrist)
        edge2 = self._distance(hand.index_mcp, hand.pinky_mcp)
        edge3 = self._distance(hand.wrist, hand.pinky_mcp)
        hand_scale = max(edge1, edge2, edge3)

        # === CÁLCULO DO RATIO DO DEDÃO ===
        # Ratio (proporção): Distância do dedão até o dedo indicador, dividida pela escala da mão.
        # Se for baixo (dedão colado no indicador), significa recolhido/gatilho apertado.
        # Se for alto (dedão afastado), significa mão aberta em "L" (trava de mira).
        thumb_ratio = self._thumb_trigger_ratio(hand.thumb_tip, hand.index_mcp, hand_scale)

        # === HYSTERESIS DO DEDÃO ===
        # Hysteresis é um conceito para evitar "pisca-pisca" no limiar.
        # Usa um valor para "entrar" no estado e um valor diferente para "sair".
        if self.is_thumb_open:
            # Se o dedão já estava aberto, precisa baixar mais que EXIT para fechar
            self.is_thumb_open = thumb_ratio > config.THUMB_OPEN_EXIT
        else:
            # Se estava fechado, precisa subir mais que ENTER para abrir
            self.is_thumb_open = thumb_ratio > config.THUMB_OPEN_ENTER

        if self.is_thumb_closed:
            # Se já puxou o gatilho, tem que soltar bastante para desativar
            self.is_thumb_closed = thumb_ratio < config.THUMB_CLOSE_EXIT
        else:
            # Se não puxou, tem que fechar bem apertado para ativar
            self.is_thumb_closed = thumb_ratio < config.THUMB_CLOSE_ENTER

        # === DEBOUNCING: DEDÃO ABERTO ("L") ===
        if self.is_thumb_open:
            self.thumb_open_frames += 1
        else:
            self.thumb_open_frames = 0
        thumb_open_confirmed = self.thumb_open_frames >= config.THUMB_OPEN_MIN_FRAMES

        # === DEBOUNCING: DEDÃO FECHADO (GATILHO) ===
        if self.is_thumb_closed:
            self.thumb_close_frames += 1
        else:
            self.thumb_close_frames = 0
        thumb_close_confirmed = self.thumb_close_frames >= config.THUMB_CLOSE_MIN_FRAMES

        # === DETECÇÃO DE SCROLL (MÃO ESPALMADA — 5 dedos) ===
        is_scroll_raw = False
        if hand.middle_tip and hand.ring_tip and hand.pinky_tip:
            d_index = self._distance(hand.index_tip, hand.wrist)
            d_middle = self._distance(hand.middle_tip, hand.wrist)
            d_ring = self._distance(hand.ring_tip, hand.wrist)
            d_pinky = self._distance(hand.pinky_tip, hand.wrist)
            d_thumb = self._distance(hand.thumb_tip, hand.wrist)

            is_scroll_raw = (
                d_index > hand_scale * config.SCROLL_INDEX_FACTOR
                and d_middle > hand_scale * config.SCROLL_MIDDLE_FACTOR
                and d_ring > hand_scale * config.SCROLL_RING_FACTOR
                and d_pinky > hand_scale * config.SCROLL_PINKY_FACTOR
                and d_thumb > hand_scale * config.SCROLL_THUMB_FACTOR
            )

        if is_scroll_raw:
            if self.scroll_frames == 0:
                self.time_entered_scroll = now
            self.scroll_frames += 1
            self.non_scroll_frames = 0
        else:
            self.non_scroll_frames += 1
            self.scroll_frames = 0

        should_exit_scroll = self.non_scroll_frames > config.SCROLL_EXIT_FRAMES
        scroll_active = self.scroll_frames > config.SCROLL_ENTER_FRAMES and (
            now - self.time_entered_scroll >= config.SCROLL_HOLD_TIME
        )

        self._log(thumb_ratio)

        # =================================================================
        # STATE MACHINE
        # =================================================================

        if self.state == AppState.NAVEGACAO:
            self._estado_navegacao(hand, now, thumb_open_confirmed, scroll_active)

        elif self.state == AppState.TRAVA_MIRA:
            self._estado_trava_mira(hand, now, thumb_close_confirmed)

        elif self.state == AppState.CLIQUE_ARRASTE:
            self._estado_clique_arraste(hand, now)

        elif self.state == AppState.SOLTAR:
            self._estado_soltar(thumb_close_confirmed, now)

        elif self.state == AppState.SCROLL:
            self._estado_scroll(hand, now, should_exit_scroll)

    # =====================================================================
    # ESTADO 0: NAVEGAÇÃO — ☝️ indicador + dedão recolhido
    # =====================================================================

    def _estado_navegacao(self, hand: HandData, now: float, thumb_open_ok: bool, scroll_ok: bool):
        # MODO NAVEGAÇÃO: Estado padrão. O cursor segue o dedo livremente.

        # Scroll tem prioridade sobre tudo
        if scroll_ok:
            self.state = AppState.SCROLL
            # Anota a posição vertical que o dedo estava ao iniciar o scroll
            mapped = self._map_to_screen(hand.index_tip)
            self.scroll_anchor_y = mapped[1]
            print("↕️ [ESTADO 4] Entrando no Modo Scroll (mão espalmada)")
            return

        # Dedão abriu em "L" → Transição para Travar cursor
        if thumb_open_ok:
            self.state = AppState.TRAVA_MIRA
            # Congela o cursor onde ele está nesse exato instante
            self.frozen_pos = self.cursor_pos
            self.time_entered_trava = now
            print("🤙 [ESTADO 1] Mão em L! Trava de Mira ativada. Cursor congelado.")
            return

        # Navegação livre: cursor segue indexTip
        mapped = self._map_to_screen(hand.index_tip)

        pre_x = self.pre_filter_x.apply(mapped[0], config.PRE_FILTER_ALPHA)
        pre_y = self.pre_filter_y.apply(mapped[1], config.PRE_FILTER_ALPHA)
        filt_x = self.euro_x.filter(pre_x, now)
        filt_y = self.euro_y.filter(pre_y, now)

        self.cursor_pos = (filt_x, filt_y)
        self.frozen_pos = self.cursor_pos

        post_mouse_event(MOUSE_MOVED, self.cursor_pos)

    # =====================================================================
    # ESTADO 1: TRAVA DE MIRA — Dedão aberto em "L", cursor congelado
    # =====================================================================

    def _estado_trava_mira(self, hand: HandData, now: float, thumb_close_ok: bool):
        # Timeout de segurança
        if now - self.time_entered_trava > config.TRAVA_MIRA_TIMEOUT:
            self._reset_to_navegacao()
            print(f"⏰ [TIMEOUT] Trava expirou após {config.TRAVA_MIRA_TIMEOUT}s. Retornando à navegação.")
            return

        # Dedão fechou → Gatilho → CLIQUE!
        if thumb_close_ok:
            self.state = AppState.CLIQUE_ARRASTE
            self._iniciar_clique(now, hand.wrist)
            return

        # Alimentar filtros silenciosamente para evitar pulos no cursor
        mapped = self._map_to_screen(hand.index_tip)
        pre_x = self.pre_filter_x.apply(mapped[0], config.PRE_FILTER_ALPHA)
        pre_y = self.pre_filter_y.apply(mapped[1], config.PRE_FILTER_ALPHA)
        self.euro_x.filter(pre_x, now)
        self.euro_y.filter(pre_y, now)
        self.euro_x.lock_position(self.frozen_pos[0])
        self.euro_y.lock_position(self.frozen_pos[1])

        # Cursor congelado
        post_mouse_event(MOUSE_MOVED, self.frozen_pos)

    # =====================================================================
    # ESTADO 2: CLIQUE/ARRASTE — Dedão fechado (gatilho), mouseDown ativo
    # =====================================================================

    def _estado_clique_arraste(self, hand: HandData, now: float):
        if self.is_thumb_closed:
            elapsed = now - self.time_entered_gatilho

            # Clique Direito: hold por 1.2s
            if (
                self.click_count == 1
                and elapsed > config.RIGHT_CLICK_HOLD_TIME
                and not self.is_right_click
                and not self.drag_active
            ):
                print("🖱️ [CLIQUE] Hold 1.2s → Menu Direito")
                post_mouse_event(LEFT_MOUSE_UP, self.cursor_pos, click_count=1)
                post_mouse_event(LEFT_MOUSE_DOWN, self.cursor_pos, click_count=1, is_right_click=True)
                self.is_right_click = True

            # Iniciar Arraste (movimento do wrist)
            if not self.drag_active and not self.is_right_click:
                dx = hand.wrist[0] - self.anchor_hand_pos[0]
                dy = hand.wrist[1] - self.anchor_hand_pos[1]
                delta = math.sqrt(dx * dx + dy * dy)

                if self.click_count == 1 and delta > config.DRAG_DISTANCE_THRESHOLD:
                    self.drag_active = True
                    self.anchor_hand_pos = hand.wrist
                    self.cursor_anchor = self.frozen_pos
                    self.drag_filter_x.y = self.frozen_pos[0]
                    self.drag_filter_y.y = self.frozen_pos[1]
                    print("🔄 [ESTADO 2] Drag ativado — indicador reto, rastreamento estável")

            # Atualizar posição durante arraste
            if self.drag_active:
                raw_mapped = self._map_to_screen(hand.wrist)
                target_x = raw_mapped[0] + self.drag_offset[0]
                target_y = raw_mapped[1] + self.drag_offset[1]

                filt_x = self.drag_filter_x.apply(target_x, config.DRAG_FILTER_ALPHA)
                filt_y = self.drag_filter_y.apply(target_y, config.DRAG_FILTER_ALPHA)

                clamped_x = max(0, min(self.screen_w, filt_x))
                clamped_y = max(0, min(self.screen_h, filt_y))

                self.cursor_pos = (clamped_x, clamped_y)
                post_mouse_event(
                    LEFT_MOUSE_DRAGGED, self.cursor_pos,
                    click_count=self.click_count, is_right_click=self.is_right_click,
                )
        else:
            # Dedão abriu → Soltar clique
            dispatch_count = 1 if self.is_right_click else self.click_count
            post_mouse_event(LEFT_MOUSE_UP, self.cursor_pos, click_count=dispatch_count, is_right_click=self.is_right_click)
            self._mouse_is_down = False

            self.last_click_release = now
            self.state = AppState.SOLTAR
            self.thumb_open_frames = 0
            self.thumb_close_frames = 0

            if not self.drag_active:
                print("🛑 [ESTADO 3] Clique solto. Aguardando dedão fechar...")
            else:
                print("🛑 [ESTADO 3] Drag finalizado. Aguardando dedão fechar...")

    # =====================================================================
    # ESTADO 3: SOLTAR — Transição limpa
    # =====================================================================

    def _estado_soltar(self, thumb_close_ok: bool, now: float):
        # Em SOLTAR, o dedão está ABERTO (você acabou de soltar o gatilho).
        # Mantém o cursor travado (congelado) onde estava
        post_mouse_event(MOUSE_MOVED, self.frozen_pos)

        if thumb_close_ok:
            intervalo = now - self.last_click_release
            if intervalo <= config.DOUBLE_CLICK_WINDOW and not self.drag_active:
                # Fechou rápido! É um duplo clique.
                self.state = AppState.CLIQUE_ARRASTE
                self._iniciar_clique(now, self.anchor_hand_pos)
            else:
                # Fechou após o tempo de duplo clique (ou foi drag). Retorna para NAVEGACAO.
                self._reset_to_navegacao()
                print("☝️ [ESTADO 0] Gatilho recolhido. Retornando à navegação.")
        else:
            # Se mantiver o dedão aberto (solto) por muito tempo, cancela e volta
            if now - self.last_click_release > config.TRAVA_MIRA_TIMEOUT:
                self._reset_to_navegacao()
                print("⏰ [TIMEOUT] Soltar expirou. Retornando à navegação.")

    # =====================================================================
    # ESTADO 4: SCROLL — Mão espalmada (5 dedos, joystick vertical)
    # =====================================================================

    def _estado_scroll(self, hand: HandData, now: float, should_exit: bool):
        if should_exit:
            self._scroll_accumulator = 0.0
            self._reset_to_navegacao()
            print("↕️ [SCROLL] Saindo do modo scroll")
            return

        mapped = self._map_to_screen(hand.index_tip)
        delta_y = self.scroll_anchor_y - mapped[1]

        if abs(delta_y) > config.SCROLL_DEAD_ZONE and now - self.last_scroll_time > config.SCROLL_MIN_INTERVAL:
            raw_delta = delta_y - (config.SCROLL_DEAD_ZONE if delta_y > 0 else -config.SCROLL_DEAD_ZONE)
            magnitude = abs(raw_delta)
            speed = magnitude * magnitude * config.SCROLL_ACCELERATION
            scroll_speed = -speed if delta_y > 0 else speed

            # Acumular sub-pixel para não perder movimentos pequenos
            self._scroll_accumulator += scroll_speed
            int_scroll = int(self._scroll_accumulator)

            if int_scroll != 0:
                post_scroll_event(float(int_scroll))
                self._scroll_accumulator -= int_scroll
                self.last_scroll_time = now
