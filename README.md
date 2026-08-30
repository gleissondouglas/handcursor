<p align="center">
  <img src="assets/icon.jpg" width="150" height="150" style="border-radius: 20px;">
</p>

<h1 align="center">HandCursor 🖐️</h1>

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

O **HandCursor** transforma a sua webcam em um dispositivo de controle: usando **visão computacional 3D** (Google MediaPipe), o aplicativo rastreia 21 pontos da sua mão em tempo real e converte gestos naturais em ações do sistema operacional — mover o cursor, clicar, arrastar e rolar.

## Gestos

A **Arquitetura Pinça (Vision Pro)** foi projetada para ser natural e fluida. O cursor rastreia o "centro da pinça", garantindo estabilidade e precisão.

| Gesto | Ação | Como fazer |
|:---:|---|---|
| 🖐️ | **Navegação** | Mão relaxada (apontando ou neutra). O cursor segue a mão, estabilizado por filtros *OneEuro*. |
| 🤏 | **Clique (Pinch)** | Toque a ponta do **Indicador** com o **Polegar**. Um micro-congelamento de 100ms absorve o tremor do clique. |
| 🔄 | **Arrastar** | Feche a pinça (Indicador + Polegar) e continue movendo a mão. |
| ✌️ | **Clique Direito** | Toque a ponta do dedo **Médio** com o **Polegar**. |
| ✋ | **Scroll** | Abra a mão completamente (5 dedos esticados) e mova para cima ou para baixo. |

> **Configurável:** Você pode alterar o que cada gesto faz editando o `ACTION_MAP` no `config.py`.

## Instalação

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
├── state_machine.py     # Máquina de estados com debouncing e hysteresis
├── filters.py           # OneEuroFilter (adaptativo) + LowPassFilter
├── mouse_injector.py    # Injeção de CGEvent via Quartz (PyObjC)
└── config.py            # Thresholds, timings e configurações centralizadas
```

| Módulo | Responsabilidade |
|---|---|
| **`hand_tracker`** | Recebe frames RGB, executa o modelo MediaPipe e retorna um `HandData` com coordenadas normalizadas dos landmarks. |
| **`state_machine`** | Converte poses da mão em ações do macOS através de 5 estados: Navegação → Trava de Mira → Clique/Arraste → Soltar → Scroll. Usa hysteresis para evitar oscilação e debouncing para confirmar gestos. |
| **`filters`** | `OneEuroFilter` adapta a suavização à velocidade do movimento: estável quando parado, responsivo quando em movimento rápido. |
| **`mouse_injector`** | Injeta eventos nativos (`CGEventCreateMouseEvent`, `CGEventCreateScrollWheelEvent`) no macOS via `kCGHIDEventTap`. Feedback sonoro nativo via `NSSound`. |
| **`config`** | Ponto único de ajuste de todos os parâmetros: thresholds do gatilho, tempos de debounce, fatores de scroll, alphas dos filtros. |

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
