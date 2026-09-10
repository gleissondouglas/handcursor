<p align="center">
  <img src="assets/icon.jpg" width="150" height="150" style="border-radius: 20px;">
</p>

<h1 align="center">HandCursor</h1>

<p align="center">
  <b>Controle o cursor do seu Mac usando apenas gestos das mãos.</b>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Python-3.9+-3776AB?style=for-the-badge&logo=python&logoColor=white" alt="Python">
  <img src="https://img.shields.io/badge/MediaPipe-v0.10.14-00A650?style=for-the-badge" alt="MediaPipe">
  <img src="https://img.shields.io/badge/macOS-12.0+-black?style=for-the-badge&logo=apple" alt="macOS">
  <img src="https://img.shields.io/badge/Licença-MIT-blue?style=for-the-badge" alt="MIT">
</p>

---

O **HandCursor** transforma a sua webcam em um dispositivo de controle: usando **visão computacional 3D** (Google MediaPipe), o aplicativo rastreia 21 pontos da sua mão em tempo real e converte gestos naturais em ações do sistema operacional — mover o cursor, clicar, arrastar, rolar e clicar com o botão direito.

## ✨ Destaques

- 🎯 **Precisão de clique** — cursor congela automaticamente durante o tap para evitar tremor
- 🔥 **Duplo clique inteligente** — validação por tempo E distância, com posição travada
- 📜 **Scroll tipo joystick** — âncora dinâmica com suavização anti-jitter
- 🎛️ **Totalmente configurável** — todos os parâmetros ajustáveis em um único arquivo (`config.py`)
- 🔊 **Feedback sonoro** — som nativo do macOS no clique (via `NSSound`)
- 🛡️ **Safety release** — libera o mouse automaticamente se a mão sair do frame

## 🤏 Gestos

A **Arquitetura Pinça**, inspirada no Apple Vision Pro, foi projetada para ser natural e fluida. O cursor rastreia o "centro da pinça" (ponto médio entre polegar e indicador), garantindo estabilidade.

| Gesto | Ação | Como fazer |
|:---:|---|---|
| 🖐️ | **Navegação** | Mão relaxada (apontando ou neutra). O cursor segue a mão, suavizado por filtros *OneEuro* adaptativos. |
| 🤏 | **Clique** | Toque a ponta do **Indicador** com o **Polegar**. O cursor congela por 250ms para absorver o tremor natural da pinça. |
| 🤏🤏 | **Duplo Clique** | Duas pinças rápidas (intervalo < 400ms). O segundo clique é enviado na mesma posição do primeiro para garantir reconhecimento pelo macOS. |
| 🔄 | **Arrastar** | Mantenha a pinça (Indicador + Polegar) e mova a mão. O arraste inicia automaticamente após 250ms se houver movimento. |
| ✌️ | **Clique Direito** | Toque a ponta do dedo **Médio** com o **Polegar**. |
| ✋ | **Scroll** | Abra a mão completamente (5 dedos esticados) por 300ms, depois mova para cima/baixo. Funciona como um joystick virtual. |

> **💡 Configurável:** Você pode alterar o que cada gesto faz editando o `ACTION_MAP` no `config.py`.

## 📦 Instalação

### Pré-requisitos

- macOS 12.0+ (Monterey ou superior)
- Python 3.9+
- Webcam integrada ou externa

### Setup

```bash
# 1. Clone o repositório
git clone https://github.com/gleissondouglas/handcursor.git
cd handcursor/python_app

# 2. Instale as dependências
pip3 install -r requirements.txt
```

### Permissões do macOS

O HandCursor precisa de duas permissões para funcionar:

| Permissão | Por quê | Onde ativar |
|---|---|---|
| 📷 **Câmera** | Capturar a imagem da mão | Solicitada automaticamente na primeira execução |
| ♿ **Acessibilidade** | Injetar eventos de mouse no sistema | *Ajustes do Sistema → Privacidade e Segurança → Acessibilidade* |

> O aplicativo verifica automaticamente se as permissões estão concedidas e exibe um aviso no terminal caso estejam faltando.

## 🚀 Uso

```bash
# Modo padrão (sem janela visual)
python3 main.py

# Modo debug (exibe câmera com landmarks e estado em tempo real)
python3 main.py --debug

# Desativar espelhamento da câmera
python3 main.py --no-mirror

# Usar uma câmera específica (ex: webcam externa no índice 1)
python3 main.py --camera 1

# Combinando opções
python3 main.py --debug --camera 1 --no-mirror
```

Para encerrar: `Ctrl+C` no terminal ou `Q` na janela de debug.

## 🏗️ Arquitetura

```
python_app/
├── main.py              # Loop principal, CLI e ciclo de vida
├── hand_tracker.py      # Wrapper do MediaPipe Hands (21 landmarks 3D)
├── gestures.py          # Reconhecedor de gestos com hysteresis e debouncing
├── state_machine.py     # Máquina de estados: gesto → ação do macOS
├── filters.py           # OneEuroFilter (adaptativo) + LowPassFilter
├── mouse_injector.py    # Injeção de CGEvent via Quartz (PyObjC)
├── config.py            # Thresholds, timings e configurações centralizadas
└── requirements.txt     # Dependências Python
```

### Fluxo de Dados

```
Câmera (30fps) → MediaPipe (21 landmarks 3D)
    → GestureRecognizer (hysteresis + debounce)
        → StateMachine (lógica de ações)
            → MouseInjector (CGEvent no macOS)
```

| Módulo | Responsabilidade |
|---|---|
| **`hand_tracker`** | Recebe frames RGB, executa o modelo MediaPipe e retorna um `HandData` com coordenadas 3D normalizadas dos landmarks. |
| **`gestures`** | Detecta `PINCH_INDEX`, `PINCH_MIDDLE`, `OPEN_HAND` ou `RELAXED` usando distâncias 3D normalizadas pela escala da mão, com hysteresis (thresholds de entrada/saída) e debouncing (mínimo de 2 frames consecutivos). |
| **`state_machine`** | Converte gestos em ações do macOS: navegação livre, clique/duplo-clique com congelamento de cursor, arraste suavizado, clique direito e scroll com âncora dinâmica. |
| **`filters`** | `OneEuroFilter` adapta a suavização à velocidade do movimento (estável quando parado, responsivo quando em movimento). `LowPassFilter` usado como pré-processamento e para scroll. |
| **`mouse_injector`** | Injeta eventos nativos (`CGEventCreateMouseEvent`, `CGEventCreateScrollWheelEvent`) no macOS via `kCGHIDEventTap`. Feedback sonoro via `NSSound`. |
| **`config`** | Ponto único de ajuste de todos os parâmetros do sistema. |

## ⚙️ Configuração

Todos os parâmetros ficam em `config.py`. Aqui estão os mais importantes para ajuste fino:

### Clique e Duplo Clique

| Parâmetro | Padrão | Descrição |
|---|---|---|
| `PINCH_ENTER` | `0.35` | Distância normalizada para detectar a pinça (quanto maior, mais fácil clicar) |
| `PINCH_EXIT` | `0.45` | Distância para soltar a pinça (hysteresis — maior que `ENTER` para evitar oscilação) |
| `MICRO_LOCK_DURATION` | `0.12s` | Tempo de congelamento inicial do cursor no clique |
| `TAP_MAX_DURATION` | `0.25s` | Tempo total que o cursor fica congelado durante um tap rápido |
| `DOUBLE_CLICK_WINDOW` | `0.4s` | Janela de tempo para reconhecer duplo clique |
| `DOUBLE_CLICK_MAX_DISTANCE` | `30px` | Distância máxima entre dois cliques para contar como duplo |
| `BOUNCE_FILTER_TIME` | `0.10s` | Ignora cliques muito rápidos (tremor involuntário) |

### Scroll

| Parâmetro | Padrão | Descrição |
|---|---|---|
| `SCROLL_HOLD_TIME` | `0.3s` | Tempo com mão aberta para ativar o scroll |
| `SCROLL_DEAD_ZONE` | `10px` | Zona morta — evita scroll acidental com a mão parada |
| `SCROLL_ACCELERATION` | `0.015` | Fator de aceleração quadrática (movimentos grandes = scroll rápido) |
| `SCROLL_BASE_SPEED` | `0.8` | Velocidade mínima garantida ao ultrapassar a dead zone |
| `SCROLL_ANCHOR_DRIFT` | `0.03` | Taxa de atualização da âncora dinâmica (0 = fixa, 1 = segue a mão) |
| `SCROLL_FILTER_ALPHA` | `0.4` | Suavização do movimento de scroll (0 = muito suave, 1 = sem filtro) |

### Suavização do Cursor

| Parâmetro | Padrão | Descrição |
|---|---|---|
| `PRE_FILTER_ALPHA` | `0.95` | Alpha do LowPassFilter pré-processamento |
| `EURO_MIN_CUTOFF` | `1.80` | Estabilidade quando a mão está parada (menor = mais estável) |
| `EURO_BETA` | `0.007` | Responsividade em movimento (maior = mais rápido, porém mais jitter) |

### Gestos

| Parâmetro | Padrão | Descrição |
|---|---|---|
| `GESTURE_MIN_FRAMES` | `2` | Frames consecutivos para confirmar um gesto (evita falsos positivos) |
| `SCREEN_MARGIN` | `0.15` | Margem nas bordas da câmera (evita extremos imprecisos) |

## 🔧 Troubleshooting

| Problema | Solução |
|---|---|
| Cursor não se move | Verifique a permissão de **Acessibilidade** em Ajustes do Sistema |
| Cliques não registram | Aumente `PINCH_ENTER` (ex: `0.40`) para facilitar a detecção da pinça |
| Duplo clique não funciona | Aumente `DOUBLE_CLICK_WINDOW` (ex: `0.5`) ou `DOUBLE_CLICK_MAX_DISTANCE` (ex: `50`) |
| Scroll não ativa | Reduza `SCROLL_HOLD_TIME` (ex: `0.2`) ou verifique se todos os 5 dedos estão visíveis |
| Scroll muito lento | Aumente `SCROLL_ACCELERATION` e/ou `SCROLL_BASE_SPEED` |
| Cursor treme muito | Reduza `EURO_BETA` (ex: `0.003`) e/ou `EURO_MIN_CUTOFF` (ex: `1.0`) |
| Cliques falsos (phantom clicks) | Aumente `GESTURE_MIN_FRAMES` (ex: `3`) |
| Câmera não abre | Tente `python3 main.py --camera 1` para webcam externa |

## 🤝 Contribuições

Contribuições são bem-vindas! Abra uma _Issue_ ou _Pull Request_.

**Roadmap:**
- [ ] Empacotar como app nativo `.app` (PyInstaller / py2app)
- [ ] Menu Bar com controles de start/pause/sensibilidade
- [ ] Suporte a múltiplos monitores
- [ ] Modo para canhotos
- [ ] Detecção de duas mãos simultâneas

## 📄 Licença

Distribuído sob a licença [MIT](LICENSE).
