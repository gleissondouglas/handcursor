#!/usr/bin/env python3
# =========================================================================
# HANDCURSOR v5.0 — PYTHON + MEDIAPIPE
# Mouse virtual controlado pela câmera usando a Arquitetura Gatilho com Dedão.
#
# Uso:
#   python main.py            → Modo normal (sem janela de câmera)
#   python main.py --debug    → Modo debug (exibe câmera com landmarks)
#   python main.py --mirror   → Inverte a câmera horizontalmente
#
# Para encerrar: Ctrl+C no terminal (ou 'q' na janela de debug)
# =========================================================================
import sys
import signal
import argparse
import time

import cv2

import config
from hand_tracker import HandTracker
from state_machine import StateMachine


def parse_args():
    parser = argparse.ArgumentParser(description="HandCursor v5.0 — Mouse virtual por câmera")
    parser.add_argument("--debug", action="store_true", help="Exibe janela com câmera e landmarks")
    parser.add_argument("--camera", type=int, default=config.CAMERA_INDEX, help="Índice da câmera")
    return parser.parse_args()


def main():
    args = parse_args()

    print("\n========================================================")
    print("📍 HANDCURSOR v5.0 — PYTHON + MEDIAPIPE")
    print("- Navegação: ☝️ indicador (dedão recolhido) = cursor livre")
    print("- Trava de Mira: 🤙 Mão em L (dedão abre) = cursor congela")
    print("- Clique: 🔫 Fechar o dedão (puxar o gatilho)")
    print("- Hold 0.5s + mover = Drag | Hold 1.2s = Clique Direito")
    print("- Scroll: 🖐️ Mão espalmada (5 dedos abertos)")
    print("========================================================")
    print(f"Câmera: {args.camera} | Debug: {'ON' if args.debug else 'OFF'} | Imagem Espelhada: ON")
    print("Pressione Ctrl+C para encerrar.\n")

    # Inicializar câmera
    cap = cv2.VideoCapture(args.camera)
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, config.CAMERA_WIDTH)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, config.CAMERA_HEIGHT)
    cap.set(cv2.CAP_PROP_FPS, 30)

    if not cap.isOpened():
        print("❌ Erro: Não foi possível abrir a câmera.")
        sys.exit(1)

    actual_w = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    actual_h = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    print(f"📷 Câmera aberta: {actual_w}x{actual_h}")

    # Inicializar componentes
    tracker = HandTracker()
    machine = StateMachine()

    # Ctrl+C handler
    running = True
    def signal_handler(sig, frame):
        nonlocal running
        running = False
        print("\n🛑 Encerrando...")
    signal.signal(signal.SIGINT, signal_handler)

    # FPS counter
    frame_count = 0
    fps_start = time.time()
    fps_display = 0

    print("✅ Rastreamento iniciado!\n")

    # =========================================================================
    # LOOP PRINCIPAL
    # =========================================================================
    while running and cap.isOpened():
        ret, frame = cap.read()
        if not ret:
            continue

        # Espelhar frame para agir como um espelho natural
        frame = cv2.flip(frame, 1)

        # Converter BGR → RGB para MediaPipe
        rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)

        # Processar mão
        hand = tracker.process(rgb)

        if hand:
            machine.process(hand)

        # FPS
        frame_count += 1
        elapsed = time.time() - fps_start
        if elapsed >= 2.0:
            fps_display = frame_count / elapsed
            frame_count = 0
            fps_start = time.time()

        # Debug visual
        if args.debug:
            # Redesenhar landmarks manualmente (mais leve que usar draw_landmarks)
            if hand:
                h_frame, w_frame = frame.shape[:2]
                # Desenhar pontos principais
                for name, pt in [
                    ("IDX", hand.index_tip),
                    ("THB", hand.thumb_tip),
                    ("WRS", hand.wrist),
                    ("MCP", hand.index_mcp),
                ]:
                    px = int(pt[0] * w_frame)
                    py = int(pt[1] * h_frame)
                    color = (0, 255, 0) if name == "IDX" else (0, 255, 255)
                    cv2.circle(frame, (px, py), 6, color, -1)
                    cv2.putText(frame, name, (px + 8, py - 8), cv2.FONT_HERSHEY_SIMPLEX, 0.4, color, 1)

                # Linha dedão → indexMCP (a métrica do gatilho)
                p1 = (int(hand.thumb_tip[0] * w_frame), int(hand.thumb_tip[1] * h_frame))
                p2 = (int(hand.index_mcp[0] * w_frame), int(hand.index_mcp[1] * h_frame))
                line_color = (0, 0, 255) if machine.is_thumb_open else (100, 100, 100)
                cv2.line(frame, p1, p2, line_color, 2)

            # Info overlay
            state_name = machine.state.name
            cv2.putText(frame, f"Estado: {state_name}", (10, 30), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 255, 0), 2)
            cv2.putText(frame, f"FPS: {fps_display:.0f}", (10, 60), cv2.FONT_HERSHEY_SIMPLEX, 0.6, (255, 255, 255), 1)

            cv2.imshow("HandCursor Debug", frame)
            if cv2.waitKey(1) & 0xFF == ord("q"):
                running = False

    # Cleanup
    cap.release()
    tracker.close()
    if args.debug:
        cv2.destroyAllWindows()
    print("👋 HandCursor encerrado.")


if __name__ == "__main__":
    main()
