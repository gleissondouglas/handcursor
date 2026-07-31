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
# GATILHO COM DEDÃO — Thresholds com Hysteresis
#
# thumbTriggerRatio = distance(thumbTip, indexMCP) / handScale
# Com a mão em pé, o handScale (pulso-MCP) é grande.
#   - Baixo (~0.12-0.18): Dedão RECOLHIDO → Navegação / Gatilho puxado
#   - Alto  (~0.28-0.35+): Dedão ABERTO em "L" → Trava de Mira
# -------------------------------------------------------------------------

# Transição Navegação → Trava de Mira (dedão abrindo em "L")
THUMB_OPEN_ENTER = 0.26   # Ratio acima disso = dedão abriu → TRAVAR
THUMB_OPEN_EXIT = 0.22    # Ratio abaixo disso = saiu da trava

# Detecção do Gatilho (dedão fechando de volta)
THUMB_CLOSE_ENTER = 0.20  # Ratio abaixo disso = GATILHO (clique!)
THUMB_CLOSE_EXIT = 0.23   # Ratio acima disso = soltou o gatilho

# -------------------------------------------------------------------------
# DEBOUNCING — Frames consecutivos mínimos para confirmar gesto
# -------------------------------------------------------------------------
THUMB_OPEN_MIN_FRAMES = 4     # ~133ms a 30fps (dedão abriu em L)
THUMB_CLOSE_MIN_FRAMES = 2    # ~67ms a 30fps (gatilho puxado — responsivo)

# -------------------------------------------------------------------------
# TEMPORIZAÇÃO
# -------------------------------------------------------------------------
TRAVA_MIRA_TIMEOUT = 8.0      # Segundos — volta à navegação se ficar travado
RIGHT_CLICK_HOLD_TIME = 1.2   # Segundos — hold para clique direito
DOUBLE_CLICK_WINDOW = 0.5     # Segundos — janela para duplo clique
BOUNCE_FILTER_TIME = 0.15     # Segundos — ignora cliques muito rápidos (tremor)

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
EURO_BETA = 0.0               # OneEuroFilter: responsividade quando em movimento
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
# HISTÓRICO DE POSIÇÕES (para média se necessário)
# -------------------------------------------------------------------------
MAX_POSITION_HISTORY = 10
