#!/usr/bin/env python3
# =========================================================================
# HANDCURSOR v5.0 — PYTHON + MEDIAPIPE
# Mouse virtual controlado pela câmera usando a Arquitetura Gatilho com Dedão.
#
# Uso:
#   python main.py                → Modo normal (sem janela de câmera)
#   python main.py --debug        → Modo debug (exibe câmera com landmarks)
#   python main.py --no-mirror    → Desativa espelhamento da câmera
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


def _check_accessibility() -> bool:
    """
    Verifica se o processo tem permissão de Acessibilidade no macOS.
    Sem ela, os eventos de mouse (CGEvent) são silenciosamente descartados.
    """
    try:
        from ApplicationServices import AXIsProcessTrustedWithOptions
        from CoreFoundation import kCFBooleanTrue
        options = {
            "AXTrustedCheckOptionPrompt": kCFBooleanTrue,
        }
        trusted = AXIsProcessTrustedWithOptions(options)
        return trusted
    except ImportError:
        # Se não conseguir importar, assume que está OK (fallback)
        return True


def parse_args():
    # Define os argumentos de linha de comando que o usuário pode passar ao rodar o script
    parser = argparse.ArgumentParser(description="HandCursor v5.0 — Mouse virtual por câmera")
    parser.add_argument("--debug", action="store_true", help="Exibe janela com câmera e landmarks")
    # Permite escolher qual câmera usar (útil se tiver mais de uma, ex: webcam externa)
    parser.add_argument("--camera", type=int, default=config.CAMERA_INDEX, help="Índice da câmera")
    # Controle de espelhamento da imagem
    parser.add_argument("--mirror", action="store_true", default=True, dest="mirror",
                        help="Espelha a câmera horizontalmente (padrão: ativado)")
    parser.add_argument("--no-mirror", action="store_false", dest="mirror",
                        help="Desativa espelhamento da câmera")
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
    print(f"Câmera: {args.camera} | Debug: {'ON' if args.debug else 'OFF'} | Espelhamento: {'ON' if args.mirror else 'OFF'}")
    print("Pressione Ctrl+C para encerrar.\n")

    # Verificar permissão de Acessibilidade (necessária para CGEvent)
    if not _check_accessibility():
        print("⚠️  ATENÇÃO: Permissão de Acessibilidade NÃO concedida!")
        print("   O cursor virtual não vai funcionar sem ela.")
        print("   Vá em: Ajustes do Sistema → Privacidade e Segurança → Acessibilidade")
        print("   Adicione o Terminal (ou o app Python) à lista.\n")

    # Inicializar câmera usando OpenCV
    cap = cv2.VideoCapture(args.camera)
    # Configura a resolução para bater com o esperado pelo MediaPipe (idealmente 720p)
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, config.CAMERA_WIDTH)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, config.CAMERA_HEIGHT)
    # Tenta fixar a taxa de quadros (FPS) da câmera em 30 quadros por segundo
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

    # Ctrl+C handler: Prepara o script para desligar graciosamente se o usuário cancelar
    running = True
    def signal_handler(sig, frame):
        nonlocal running
        running = False # Interrompe o loop principal
        print("\n🛑 Encerrando...")
    signal.signal(signal.SIGINT, signal_handler)

    # FPS counter
    frame_count = 0
    fps_start = time.time()
    fps_display = 0

    # Camera retry counter (proteção contra desconexão)
    camera_retries = 0

    print("✅ Rastreamento iniciado!\n")

    # =========================================================================
    # LOOP PRINCIPAL (Roda 30 vezes por segundo enquanto o app estiver aberto)
    # =========================================================================
    while running and cap.isOpened():
        # Lê um único quadro (foto) da webcam
        ret, frame = cap.read()
        if not ret:
            # Câmera falhou — retry com backoff ao invés de loop infinito sem throttle
            camera_retries += 1
            if camera_retries >= config.CAMERA_MAX_RETRIES:
                print(f"❌ Câmera falhou {camera_retries} vezes consecutivas. Encerrando.")
                break
            print(f"⚠️ Falha na leitura da câmera ({camera_retries}/{config.CAMERA_MAX_RETRIES}). Retentando...")
            time.sleep(config.CAMERA_RETRY_DELAY)
            continue
        camera_retries = 0  # Reset counter on successful read

        # Espelhar frame horizontalmente para agir como um espelho natural
        # (se não fizer isso, quando você for para a direita, a mão na tela vai pra esquerda)
        if args.mirror:
            frame = cv2.flip(frame, 1)

        # O OpenCV trabalha com cores no formato BGR (Blue-Green-Red),
        # mas o MediaPipe exige formato RGB (Red-Green-Blue), então fazemos a conversão.
        rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)

        # Processar a imagem RGB para encontrar a mão e extrair as coordenadas (landmarks)
        hand = tracker.process(rgb)

        # Se encontrou uma mão, envia as coordenadas para a Máquina de Estados
        # que vai decidir se é pra mover o mouse, travar, clicar, etc.
        if hand:
            machine.process(hand)
        else:
            # Mão não detectada → liberar qualquer botão pressionado (safety release)
            machine.handle_lost_tracking()

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

                # Linha indicador → polegar (a métrica do PINCH)
                p1 = (int(hand.thumb_tip[0] * w_frame), int(hand.thumb_tip[1] * h_frame))
                p2 = (int(hand.index_tip[0] * w_frame), int(hand.index_tip[1] * h_frame))
                
                # Cor verde quando pinçado, vermelho quando aberto
                is_pinched = machine.recognizer.current_gesture.name in ("PINCH_INDEX", "PINCH_MIDDLE")
                line_color = (0, 255, 0) if is_pinched else (0, 0, 255)
                cv2.line(frame, p1, p2, line_color, 2)

            # Info overlay
            gesture_name = machine.recognizer.current_gesture.value if hand else "LOST"
            cv2.putText(frame, f"Gesto: {gesture_name}", (10, 30), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 255, 0), 2)
            cv2.putText(frame, f"FPS: {fps_display:.0f}", (10, 60), cv2.FONT_HERSHEY_SIMPLEX, 0.6, (255, 255, 255), 1)

            cv2.imshow("HandCursor Debug", frame)
            if cv2.waitKey(1) & 0xFF == ord("q"):
                running = False

    # Cleanup — garantir que o mouse seja liberado ao sair
    machine.handle_lost_tracking()
    cap.release()
    tracker.close()
    if args.debug:
        cv2.destroyAllWindows()
    print("👋 HandCursor encerrado.")


if __name__ == "__main__":
    main()
