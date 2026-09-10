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
# Aumentei significativamente a tolerância. Não precisa "esmagar" os dedos.
PINCH_ENTER = 0.35   # (Era 0.20) Basta os dedos chegarem perto para clicar
PINCH_EXIT = 0.45    # (Era 0.25) Você pode afrouxar bastante sem soltar o clique (excelente para arraste)

# -------------------------------------------------------------------------
# DEBOUNCING — Frames consecutivos mínimos para confirmar gesto
# -------------------------------------------------------------------------
GESTURE_MIN_FRAMES = 2        # (Era 1) Mínimo 2 frames para confirmar gesto (evita falsos OPEN_HAND)

# -------------------------------------------------------------------------
# TEMPORIZAÇÃO
# -------------------------------------------------------------------------
RIGHT_CLICK_HOLD_TIME = 1.2   # Segundos — hold para clique direito
DOUBLE_CLICK_WINDOW = 0.4     # (Era 0.5) Janela mais justa para duplo clique
BOUNCE_FILTER_TIME = 0.10     # (Era 0.15) Reduzido para não bloquear duplo cliques legítimos
MICRO_LOCK_DURATION = 0.12    # (Era 0.05) Congela cursor por mais tempo durante o clique para evitar tremor
TAP_MAX_DURATION = 0.25       # Duração máxima de um "tap" — cursor fica congelado durante esse período
DOUBLE_CLICK_MAX_DISTANCE = 30.0  # Distância máxima (px) entre dois cliques para contar como duplo

# -------------------------------------------------------------------------
# DRAG (ARRASTE)
# -------------------------------------------------------------------------
DRAG_DISTANCE_THRESHOLD = 0.005  # (Era 0.015) Ativa o arraste quase que instantaneamente ao mover a mão
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
SCROLL_HOLD_TIME = 0.3           # (Era 1.0) Segundos com postura para ativar — resposta muito mais rápida
SCROLL_DEAD_ZONE = 10            # (Era 20) Pixels de zona morta — menos movimento necessário
SCROLL_MIN_INTERVAL = 0.016      # (Era 0.04) ~60fps — scroll mais fluido
SCROLL_ACCELERATION = 0.015      # (Era 0.003) Fator de aceleração quadrática — 5× mais forte
SCROLL_BASE_SPEED = 0.8          # Velocidade mínima ao passar da dead zone (garante scroll perceptível)
SCROLL_ANCHOR_DRIFT = 0.03       # Taxa de atualização da âncora (0 = fixa, 1 = segue a mão) — estilo joystick
SCROLL_FILTER_ALPHA = 0.4        # Suavização do delta Y do scroll (0 = lento, 1 = direto)

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
