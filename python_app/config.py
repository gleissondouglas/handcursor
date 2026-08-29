# =========================================================================
# CONFIGURAÇÃO CENTRALIZADA — HandCursor v5.0 (Python + MediaPipe)
# Todos os thresholds, constantes e parâmetros ajustáveis em um só lugar.
# =========================================================================

# -------------------------------------------------------------------------
# CÂMERA
# -------------------------------------------------------------------------
CAMERA_INDEX = 0          # Índice da câmera (0 = padrão do Mac)
CAMERA_WIDTH = 1280       # 720p — sweet spot para MediaPipe
CAMERA_HEIGHT = 720

# -------------------------------------------------------------------------
# MAPEAMENTO CÂMERA → TELA
# Margem nas bordas da câmera para evitar extremos imprecisos
# -------------------------------------------------------------------------
SCREEN_MARGIN = 0.15

# -------------------------------------------------------------------------
# AÇÕES E GESTOS (Mapeamento Configurável)
# -------------------------------------------------------------------------
# Gestos disponíveis (em gestures.py): PINCH_INDEX, PINCH_MIDDLE, OPEN_HAND, RELAXED
ACTION_MAP = {
    "LEFT_CLICK_DRAG": "PINCH_INDEX",
    "RIGHT_CLICK": "PINCH_MIDDLE",
    "SCROLL": "OPEN_HAND",
}

# -------------------------------------------------------------------------
# PINÇA (PINCH) — Thresholds 3D com Hysteresis
# -------------------------------------------------------------------------
# Distância normalizada (distância ponta a ponta / escala da mão)
PINCH_ENTER = 0.20   # Distância abaixo disso ativa a pinça
PINCH_EXIT = 0.25    # Distância acima disso desativa a pinça

# -------------------------------------------------------------------------
# DEBOUNCING — Frames consecutivos mínimos para confirmar gesto
# -------------------------------------------------------------------------
GESTURE_MIN_FRAMES = 2        # Rápido o suficiente para ser responsivo, lento para não tremer

# -------------------------------------------------------------------------
# TEMPORIZAÇÃO
# -------------------------------------------------------------------------
RIGHT_CLICK_HOLD_TIME = 1.2   # Segundos — hold para clique direito
DOUBLE_CLICK_WINDOW = 0.5     # Segundos — janela para duplo clique
BOUNCE_FILTER_TIME = 0.15     # Segundos — ignora cliques muito rápidos (tremor)
MICRO_LOCK_DURATION = 0.10    # Segundos — congela o cursor ao clicar para evitar deslizes

# -------------------------------------------------------------------------
# DRAG (ARRASTE)
# -------------------------------------------------------------------------
DRAG_DISTANCE_THRESHOLD = 0.015  # Distância normalizada mínima do wrist para ativar drag
DRAG_FILTER_ALPHA = 0.18         # Suavização do filtro de arraste (0 = lento, 1 = direto)

# -------------------------------------------------------------------------
# FILTROS DE SUAVIZAÇÃO DO CURSOR
# -------------------------------------------------------------------------
PRE_FILTER_ALPHA = 0.95      # Alpha do LowPassFilter pré-processamento
EURO_MIN_CUTOFF = 1.80        # OneEuroFilter: estabilidade quando parado
EURO_BETA = 0.007             # OneEuroFilter: responsividade quando em movimento (> 0 ativa filtro adaptativo)
EURO_D_CUTOFF = 1.0           # OneEuroFilter: cutoff da derivada

# -------------------------------------------------------------------------
# SCROLL — Mão espalmada (5 dedos abertos)
# -------------------------------------------------------------------------
SCROLL_ENTER_FRAMES = 4          # Frames consecutivos para entrar no scroll
SCROLL_EXIT_FRAMES = 5           # Frames consecutivos para sair do scroll
SCROLL_HOLD_TIME = 1.0           # Segundos com postura para ativar scroll
SCROLL_DEAD_ZONE = 20            # Pixels de zona morta (evita scroll acidental)
SCROLL_MIN_INTERVAL = 0.04       # Segundos entre eventos de scroll
SCROLL_ACCELERATION = 0.003      # Fator de aceleração quadrática

# Thresholds de distância dedo→wrist para detectar mão espalmada
# Aumentados para evitar falso positivo quando os dedos estão recolhidos (mão em pé)
SCROLL_INDEX_FACTOR = 1.3
SCROLL_MIDDLE_FACTOR = 1.3
SCROLL_RING_FACTOR = 1.2
SCROLL_PINKY_FACTOR = 1.1
SCROLL_THUMB_FACTOR = 1.0

# -------------------------------------------------------------------------
# CÂMERA — RECUPERAÇÃO DE FALHA
# -------------------------------------------------------------------------
CAMERA_RETRY_DELAY = 0.5      # Segundos entre tentativas de releitura
CAMERA_MAX_RETRIES = 10       # Tentativas antes de encerrar
