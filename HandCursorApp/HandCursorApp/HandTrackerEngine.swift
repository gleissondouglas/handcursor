import Foundation
import AVFoundation
import Vision
import CoreGraphics
import Cocoa

// =========================================================================
// 1. FILTROS MATEMÁTICOS (Os "Middlewares" de Suavização)
// =========================================================================

/// Filtro Passa-Baixa: Suaviza os movimentos rápidos, reduzindo o tremor natural da mão.
class LowPassFilter {
    var y: CGFloat?
    
    func aplicar(valor: CGFloat, alpha: CGFloat) -> CGFloat {
        if let yAnterior = y {
            let resultado = alpha * valor + (1.0 - alpha) * yAnterior
            y = resultado
            return resultado
        } else {
            y = valor
            return valor
        }
    }
}

/// One Euro Filter: Filtro avançado que estabiliza o cursor quando a mão está parada (minCutoff)
/// e permite movimentos rápidos e fluidos quando a mão se move (beta).
class OneEuroFilter {
    var minCutoff: CGFloat
    var beta: CGFloat
    private var dCutoff: CGFloat
    
    private var xFilter = LowPassFilter()
    private var dxFilter = LowPassFilter()
    
    init(minCutoff: CGFloat, beta: CGFloat, dCutoff: CGFloat = 1.0) {
        self.minCutoff = minCutoff
        self.beta = beta
        self.dCutoff = dCutoff
    }
    
    private func smoothingFactor(te: TimeInterval, cutoff: CGFloat) -> CGFloat {
        let r = 2.0 * CGFloat.pi * cutoff * CGFloat(te)
        return r / (r + 1.0)
    }
    
    func filtrar(valor: CGFloat, timestamp: TimeInterval) -> CGFloat {
        let te: TimeInterval = 1.0 / 60.0 // Delta fixo assumindo 60 FPS da câmera
        
        if let yAnterior = xFilter.y {
            let dx = (valor - yAnterior) / CGFloat(te)
            
            let alphaDX = smoothingFactor(te: te, cutoff: dCutoff)
            let smoothedDX = dxFilter.aplicar(valor: dx, alpha: alphaDX)
            
            let cutoff = minCutoff + beta * abs(smoothedDX)
            let alpha = smoothingFactor(te: te, cutoff: cutoff)
            let smoothedX = xFilter.aplicar(valor: valor, alpha: alpha)
            
            return smoothedX
        } else {
            let _ = xFilter.aplicar(valor: valor, alpha: 1.0)
            let _ = dxFilter.aplicar(valor: 0.0, alpha: 1.0)
            return valor
        }
    }
    
    /// Força o filtro a assumir uma posição exata (útil para o travamento de mira)
    func travarPosicao(_ novaPosicao: CGFloat) {
        xFilter.y = novaPosicao
        dxFilter.y = 0.0
    }
}

// =========================================================================
// 2. PERSISTÊNCIA E MODELO DE DADOS (Rastreamento da Mão)
// =========================================================================

/// Mantém a memória de um ponto específico da mão, tolerando oclusões rápidas (quando um dedo some rapidamente).
struct PersistentPoint {
    var point: CGPoint = .zero
    var lostFrames: Int = 0
    var isInitialized: Bool = false
    var maxLostFrames: Int = 15 // Tolerância para frames perdidos
    
    mutating func update(newPoint: CGPoint?, confidence: Float) {
        if let p = newPoint, confidence > 0.3 {
            self.point = p
            self.lostFrames = 0
            self.isInitialized = true
        } else {
            self.lostFrames += 1
        }
    }
    
    func getPoint() -> CGPoint? {
        guard isInitialized else { return nil }
        if lostFrames <= maxLostFrames {
            return point
        }
        return nil
    }
}

/// Gerencia e atualiza todos os pontos chave da mão detectados pelo Vision.
class HandTracker {
    var indexTip = PersistentPoint()
    var indexMCP = PersistentPoint()
    var thumbTip = PersistentPoint()
    var wrist = PersistentPoint()
    var pinkyMCP = PersistentPoint()
    var middleTip = PersistentPoint()
    var middleMCP = PersistentPoint()
    var ringTip = PersistentPoint()
    var ringMCP = PersistentPoint()
    var pinkyTip = PersistentPoint()
    
    func update(from observation: VNHumanHandPoseObservation) {
        let rawIdxTip = try? observation.recognizedPoint(.indexTip)
        let rawIdxMCP = try? observation.recognizedPoint(.indexMCP)
        let rawThumbTip = try? observation.recognizedPoint(.thumbTip)
        let rawWrist = try? observation.recognizedPoint(.wrist)
        let rawPinkyMCP = try? observation.recognizedPoint(.littleMCP)
        let rawMiddleTip = try? observation.recognizedPoint(.middleTip)
        let rawMiddleMCP = try? observation.recognizedPoint(.middleMCP)
        let rawRingTip = try? observation.recognizedPoint(.ringTip)
        let rawRingMCP = try? observation.recognizedPoint(.ringMCP)
        let rawPinkyTip = try? observation.recognizedPoint(.littleTip)
        
        indexTip.update(newPoint: rawIdxTip.flatMap { CGPoint(x: $0.x, y: $0.y) }, confidence: rawIdxTip?.confidence ?? 0.0)
        indexMCP.update(newPoint: rawIdxMCP.flatMap { CGPoint(x: $0.x, y: $0.y) }, confidence: rawIdxMCP?.confidence ?? 0.0)
        thumbTip.update(newPoint: rawThumbTip.flatMap { CGPoint(x: $0.x, y: $0.y) }, confidence: rawThumbTip?.confidence ?? 0.0)
        wrist.update(newPoint: rawWrist.flatMap { CGPoint(x: $0.x, y: $0.y) }, confidence: rawWrist?.confidence ?? 0.0)
        pinkyMCP.update(newPoint: rawPinkyMCP.flatMap { CGPoint(x: $0.x, y: $0.y) }, confidence: rawPinkyMCP?.confidence ?? 0.0)
        middleTip.update(newPoint: rawMiddleTip.flatMap { CGPoint(x: $0.x, y: $0.y) }, confidence: rawMiddleTip?.confidence ?? 0.0)
        middleMCP.update(newPoint: rawMiddleMCP.flatMap { CGPoint(x: $0.x, y: $0.y) }, confidence: rawMiddleMCP?.confidence ?? 0.0)
        ringTip.update(newPoint: rawRingTip.flatMap { CGPoint(x: $0.x, y: $0.y) }, confidence: rawRingTip?.confidence ?? 0.0)
        ringMCP.update(newPoint: rawRingMCP.flatMap { CGPoint(x: $0.x, y: $0.y) }, confidence: rawRingMCP?.confidence ?? 0.0)
        pinkyTip.update(newPoint: rawPinkyTip.flatMap { CGPoint(x: $0.x, y: $0.y) }, confidence: rawPinkyTip?.confidence ?? 0.0)
    }
    
    var isDataComplete: Bool {
        return indexTip.getPoint() != nil &&
               indexMCP.getPoint() != nil &&
               thumbTip.getPoint() != nil &&
               wrist.getPoint() != nil &&
               pinkyMCP.getPoint() != nil
    }
}

// =========================================================================
// 3. MÁQUINA DE ESTADOS E ENUMS
// =========================================================================

enum AppState: Int {
    case navegacao = 0       // Estado 0: Dedão recolhido, indicador ☝️. Cursor segue indexTip livremente
    case travaMira = 1       // Estado 1: Dedão aberto em "L". Cursor congelado no pixel
    case cliqueArraste = 2   // Estado 2: Dedão fechou novamente (gatilho). MouseDown ativo
    case soltar = 3          // Estado 3: Transição limpa de volta à navegação
    case scroll = 4          // Estado 4: Mão espalmada (5 dedos) = scroll vertical
}

// =========================================================================
// INTERFACE GRÁFICA FLUTUANTE (OVERLAY)
// =========================================================================

class OverlayController {
    static let shared = OverlayController()
    private var window: NSWindow!
    private var label: NSTextField!
    
    private init() {
        let screenRect = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        let rect = NSRect(x: screenRect.midX - 100, y: screenRect.minY + 100, width: 200, height: 40)
        
        window = NSWindow(contentRect: rect, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = NSColor.black.withAlphaComponent(0.7)
        window.level = .floating
        window.ignoresMouseEvents = true
        window.hasShadow = true
        window.isMovableByWindowBackground = false
        
        if let view = window.contentView {
            view.wantsLayer = true
            view.layer?.cornerRadius = 20
        }
        
        label = NSTextField(labelWithString: "Modo Scroll")
        label.textColor = .white
        label.font = NSFont.systemFont(ofSize: 18, weight: .bold)
        label.alignment = .center
        label.isBezeled = false
        label.drawsBackground = false
        label.isEditable = false
        label.isSelectable = false
        label.frame = NSRect(x: 0, y: 8, width: 200, height: 24)
        window.contentView?.addSubview(label)
    }
    
    func show() { DispatchQueue.main.async { self.window.orderFront(nil) } }
    func hide() { DispatchQueue.main.async { self.window.orderOut(nil) } }
}

// =========================================================================
// 4. CONTROLADOR PRINCIPAL DO APLICATIVO (O "Motor")
// =========================================================================

class AppController: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let sessaoCaptura = AVCaptureSession()
    private let sequenceHandler = VNSequenceRequestHandler()
    
    // Instâncias de Filtros para suavização de movimento
    private let preFiltroX = LowPassFilter()
    private let preFiltroY = LowPassFilter()
    private let filtroX = OneEuroFilter(minCutoff: 1.80, beta: 0.0, dCutoff: 1.0)
    private let filtroY = OneEuroFilter(minCutoff: 1.80, beta: 0.0, dCutoff: 1.0)
    private let dragFilterX = LowPassFilter()
    private let dragFilterY = LowPassFilter()
    
    private let tracker = HandTracker()
    
    // Gerenciamento de Estado do App
    private var currentState: AppState = .navegacao
    
    // === ARQUITETURA DO GATILHO COM O DEDÃO ===
    // O ratio thumbTip↔indexMCP normalizado pelo tamanho da mão:
    //   - Baixo (~0.2-0.4): Dedão RECOLHIDO (encostado na lateral) → Navegação / Gatilho
    //   - Alto (~0.7-1.0+): Dedão ABERTO em "L" → Trava de Mira
    
    // Thresholds com hysteresis para transição Navegação ↔ Trava
    private let thumbOpenEnterThreshold: CGFloat = 0.75   // Ratio acima disso = dedão abriu → TRAVAR
    private let thumbOpenExitThreshold: CGFloat = 0.55    // Ratio abaixo disso = dedão fechou → sair da trava
    
    // Thresholds com hysteresis para detecção do Gatilho (dedão encostou de volta)
    private let thumbCloseEnterThreshold: CGFloat = 0.40  // Ratio abaixo disso = GATILHO (clique)
    private let thumbCloseExitThreshold: CGFloat = 0.55   // Ratio acima disso = soltou o gatilho
    
    // Estado com hysteresis
    private var isThumbOpen: Bool = false     // Dedão está aberto em "L"?
    private var isThumbClosed: Bool = false   // Dedão encostou de volta? (gatilho puxado)
    
    // Debouncing temporal: frames consecutivos confirmando "L"
    private var thumbOpenFrames: Int = 0
    private let thumbOpenMinFrames: Int = 4   // ~67ms a 60fps (rápido mas seguro)
    
    // Debouncing temporal: frames consecutivos confirmando gatilho
    private var thumbCloseFrames: Int = 0
    private let thumbCloseMinFrames: Int = 2  // ~33ms — clique precisa ser responsivo
    
    // Timeout de segurança para trava de mira
    private var timeEnteredTravaMira: TimeInterval = 0.0
    private let travaMiraTimeout: TimeInterval = 8.0  // Volta à navegação se ficar travado 8s
    
    // Ancoragem e Mira
    private var posicaoCursorAtual: CGPoint = .zero
    private var frozenPosition: CGPoint = .zero
    private var anchorHandPosition: CGPoint = .zero
    private var cursorAnchor: CGPoint = .zero
    private var dragOffset: CGPoint = .zero
    private var isRightClickActive: Bool = false
    
    private var historicoPosicoes: [CGPoint] = []
    
    // Temporizadores
    private var timeEnteredGatilho: TimeInterval = 0.0
    private var lastClickReleaseTime: TimeInterval = 0.0
    private var clickCount: Int64 = 1
    private var dragActive: Bool = false
    
    // Scroll
    private var scrollAnchorY: CGFloat = 0.0
    private var lastScrollEventTime: TimeInterval = 0.0
    private var timeEnteredScrollPosture: TimeInterval = 0.0
    private var scrollFrames: Int = 0
    private var nonScrollFrames: Int = 0
    
    private let telaBounds = CGDisplayBounds(CGMainDisplayID())
    
    private lazy var requisicao: VNDetectHumanHandPoseRequest = {
        let req = VNDetectHumanHandPoseRequest { [weak self] request, error in
            self?.processarResultado(requisicao: request, erro: error)
        }
        req.maximumHandCount = 1
        return req
    }()
    
    func iniciar() {
        print("\n========================================================")
        print("📍 MOUSE VIRTUAL v4.0 — ARQUITETURA GATILHO COM DEDÃO")
        print("- Navegação: ☝️ indicador (dedão recolhido) = cursor livre")
        print("- Trava de Mira: 🤙 Mão em L (dedão abre) = cursor congela")
        print("- Clique: 🔫 Fechar o dedão (puxar o gatilho)")
        print("- Hold 0.5s + mover = Drag | Hold 1.2s = Clique Direito")
        print("- Scroll: 🖐️ Mão espalmada (5 dedos abertos)")
        print("========================================================\n")
        
        DispatchQueue.main.async { _ = OverlayController.shared }
        
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .authorized {
            self.configurarCamera()
        } else {
            AVCaptureDevice.requestAccess(for: .video) { [weak self] concedido in
                if concedido {
                    self?.configurarCamera()
                } else {
                    print("❌ Acesso à câmera negado. Encerrando.")
                    exit(1)
                }
            }
        }
    }
    
    private func configurarCamera() {
        guard let dispositivo = AVCaptureDevice.default(for: .video),
              let entrada = try? AVCaptureDeviceInput(device: dispositivo) else {
            return
        }
        
        sessaoCaptura.beginConfiguration()
        if sessaoCaptura.canAddInput(entrada) { sessaoCaptura.addInput(entrada) }
        
        let saidaVideo = AVCaptureVideoDataOutput()
        saidaVideo.setSampleBufferDelegate(self, queue: DispatchQueue(label: "FilaDeVideo"))
        if sessaoCaptura.canAddOutput(saidaVideo) { sessaoCaptura.addOutput(saidaVideo) }
        
        var melhorFormato: AVCaptureDevice.Format? = nil
        var melhorPixels: Int32 = 0
        
        for formato in dispositivo.formats {
            let dimensoes = CMVideoFormatDescriptionGetDimensions(formato.formatDescription)
            guard dimensoes.height <= 1080 else { continue }
            let suporta60fps = formato.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= 60 }
            guard suporta60fps else { continue }
            
            let pixels = dimensoes.width * dimensoes.height
            if pixels > melhorPixels {
                melhorPixels = pixels
                melhorFormato = formato
            }
        }
        
        do {
            try dispositivo.lockForConfiguration()
            if dispositivo.isExposureModeSupported(.continuousAutoExposure) {
                dispositivo.exposureMode = .continuousAutoExposure
            }
            if let formato = melhorFormato {
                dispositivo.activeFormat = formato
                let frameDuration = CMTime(value: 1, timescale: 60)
                dispositivo.activeVideoMinFrameDuration = frameDuration
                dispositivo.activeVideoMaxFrameDuration = frameDuration
            }
            
            if #available(macOS 12.0, *) {
                if AVCaptureDevice.isCenterStageEnabled {
                    AVCaptureDevice.centerStageControlMode = .cooperative
                    AVCaptureDevice.isCenterStageEnabled = false
                }
            }
            dispositivo.unlockForConfiguration()
        } catch {}
        
        sessaoCaptura.commitConfiguration()
        sessaoCaptura.startRunning()
        
        posicaoCursorAtual = CGPoint(x: telaBounds.width / 2.0, y: telaBounds.height / 2.0)
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        try? sequenceHandler.perform([requisicao], on: sampleBuffer, orientation: .up)
    }
    
    private func processarResultado(requisicao: VNRequest, erro: Error?) {
        guard let resultados = requisicao.results as? [VNHumanHandPoseObservation],
              let mao = resultados.first else { return }
        
        tracker.update(from: mao)
        guard tracker.isDataComplete else { return }
        
        self.avaliarMaquinaEstados()
    }
    
    // =========================================================================
    // MATEMÁTICA VETORIAL DA MÃO
    // =========================================================================
    
    private func distance(_ p1: CGPoint, _ p2: CGPoint) -> CGFloat {
        let dx = p1.x - p2.x
        let dy = p1.y - p2.y
        return sqrt(dx*dx + dy*dy)
    }
    
    /// Calcula o ratio normalizado entre thumbTip e indexMCP.
    /// Valores baixos (~0.2-0.4) = dedão recolhido (encostado na lateral da mão).
    /// Valores altos (~0.7-1.0+) = dedão aberto em "L" (esticado para o lado).
    /// A normalização por handScale garante invariância de distância à câmera.
    private func thumbTriggerRatio(thumbTip: CGPoint, indexMCP: CGPoint, handScale: CGFloat) -> CGFloat {
        guard handScale > 0.01 else { return 0.0 }
        return distance(thumbTip, indexMCP) / handScale
    }
    
    /// Retorna o ratio normalizado Tip→MCP de um dedo (para scroll)
    private func fingerExtensionRatio(tip: CGPoint, mcp: CGPoint, handScale: CGFloat) -> CGFloat {
        guard handScale > 0.01 else { return 0.0 }
        return distance(tip, mcp) / handScale
    }
    
    private func obterPontoMapeado(pontoCam: CGPoint, tela: CGRect) -> CGPoint {
        let xCamNormal = 1.0 - pontoCam.x
        let yCamNormal = 1.0 - pontoCam.y
        let margin: CGFloat = 0.15
        
        var xMapeado = (xCamNormal - margin) / (1.0 - 2.0 * margin)
        var yMapeado = (yCamNormal - margin) / (1.0 - 2.0 * margin)
        
        xMapeado = max(0.0, min(1.0, xMapeado))
        yMapeado = max(0.0, min(1.0, yMapeado))
        
        return CGPoint(x: xMapeado * tela.width, y: yMapeado * tela.height)
    }
    
    private var ultimoLogTempo: TimeInterval = 0
    private func logEstado(thumbRatio: CGFloat) {
        let agora = CFAbsoluteTimeGetCurrent()
        if agora - ultimoLogTempo > 0.5 {
            print(String(format: "Estado: %@ | ThumbRatio: %.3f | Open:%d Close:%d | isOpen:%@ isClosed:%@",
                         String(describing: currentState), thumbRatio,
                         thumbOpenFrames, thumbCloseFrames,
                         isThumbOpen ? "✅" : "❌", isThumbClosed ? "✅" : "❌"))
            ultimoLogTempo = agora
        }
    }
    
    // =========================================================================
    // NÚCLEO DA LÓGICA DE AÇÕES DO MOUSE
    // =========================================================================
    
    /// Chamada quando o dedão fecha (gatilho puxado) durante a trava de mira.
    private func iniciarClique(agora: TimeInterval, wrist: CGPoint) {
        let intervalo = agora - lastClickReleaseTime
        
        if intervalo > 0.15 && intervalo <= 0.5 && lastClickReleaseTime > 0 {
            clickCount = 2
            frozenPosition = cursorAnchor
            print("🔥 [CLIQUE] Duplo clique")
        } else if intervalo <= 0.15 && lastClickReleaseTime > 0 {
            print("⚠️ [BOUNCE] Tremor ignorado")
        } else {
            clickCount = 1
            print("👆 [CLIQUE] Clique simples")
        }
        
        self.isRightClickActive = false
        
        // Usar wrist como referência para offset de arraste (estável durante movimento do dedão)
        let rawMapped = obterPontoMapeado(pontoCam: wrist, tela: telaBounds)
        dragOffset = CGPoint(x: frozenPosition.x - rawMapped.x, y: frozenPosition.y - rawMapped.y)
        
        dragActive = false
        timeEnteredGatilho = agora
        anchorHandPosition = wrist
        cursorAnchor = frozenPosition
        
        dragFilterX.y = frozenPosition.x
        dragFilterY.y = frozenPosition.y
        preFiltroX.y = frozenPosition.x
        preFiltroY.y = frozenPosition.y
        filtroX.travarPosicao(frozenPosition.x)
        filtroY.travarPosicao(frozenPosition.y)
        
        if clickCount == 2 {
            postMouseEvent(type: .leftMouseDown, point: frozenPosition, clickCount: 1, isRightClick: false)
            postMouseEvent(type: .leftMouseUp, point: frozenPosition, clickCount: 1, isRightClick: false)
        }
        
        postMouseEvent(type: .leftMouseDown, point: frozenPosition, clickCount: clickCount, isRightClick: false)
    }
    
    // =========================================================================
    // MÁQUINA DE ESTADOS — ARQUITETURA GATILHO COM DEDÃO
    //
    // Navegação (☝️ + dedão recolhido)
    //     │
    //     │ dedão abre em "L" (thumbRatio sobe > 0.75 por 4 frames)
    //     ▼
    // Trava de Mira (cursor congelado)
    //     │
    //     │ dedão fecha (thumbRatio cai < 0.40 por 2 frames)
    //     ▼
    // Clique/Arraste (mouseDown ativo)
    //     │
    //     │ dedão abre novamente (thumbRatio sobe > 0.55)
    //     ▼
    // Soltar → Navegação
    //
    // =========================================================================
    
    private func avaliarMaquinaEstados() {
        guard let pIndexTip = tracker.indexTip.getPoint(),
              let pIndexMCP = tracker.indexMCP.getPoint(),
              let pThumbTip = tracker.thumbTip.getPoint(),
              let pWrist = tracker.wrist.getPoint(),
              let pPinkyMCP = tracker.pinkyMCP.getPoint() else { return }
        
        let agora = CFAbsoluteTimeGetCurrent()
        
        // Escala robusta da mão para invariância de distância (triângulo MCP-Wrist-PinkyMCP)
        let edge1 = distance(pIndexMCP, pWrist)
        let edge2 = distance(pIndexMCP, pPinkyMCP)
        let edge3 = distance(pWrist, pPinkyMCP)
        let handScale = max(edge1, max(edge2, edge3))
        
        // === CÁLCULO DO RATIO DO DEDÃO (a métrica principal) ===
        let thumbRatio = thumbTriggerRatio(thumbTip: pThumbTip, indexMCP: pIndexMCP, handScale: handScale)
        
        // === ATUALIZAR ESTADOS DO DEDÃO COM HYSTERESIS ===
        // Dedão aberto em "L"?
        if isThumbOpen {
            isThumbOpen = thumbRatio > thumbOpenExitThreshold
        } else {
            isThumbOpen = thumbRatio > thumbOpenEnterThreshold
        }
        
        // Dedão fechado (gatilho puxado)?
        if isThumbClosed {
            isThumbClosed = thumbRatio < thumbCloseExitThreshold
        } else {
            isThumbClosed = thumbRatio < thumbCloseEnterThreshold
        }
        
        // === DEBOUNCING TEMPORAL: DEDÃO ABERTO ("L") ===
        if isThumbOpen {
            thumbOpenFrames += 1
        } else {
            thumbOpenFrames = 0
        }
        let isThumbOpenConfirmed = thumbOpenFrames >= thumbOpenMinFrames
        
        // === DEBOUNCING TEMPORAL: DEDÃO FECHADO (GATILHO) ===
        if isThumbClosed {
            thumbCloseFrames += 1
        } else {
            thumbCloseFrames = 0
        }
        let isThumbCloseConfirmed = thumbCloseFrames >= thumbCloseMinFrames
        
        // === DETECÇÃO DE SCROLL (MÃO ESPALMADA — 5 dedos abertos) ===
        var isScrollGestureRaw = false
        if let pMiddleTip = tracker.middleTip.getPoint(),
           let pRingTip = tracker.ringTip.getPoint(),
           let pPinkyTip = tracker.pinkyTip.getPoint() {
            let dIndexWrist = distance(pIndexTip, pWrist)
            let dMiddleWrist = distance(pMiddleTip, pWrist)
            let dRingWrist = distance(pRingTip, pWrist)
            let dPinkyWrist = distance(pPinkyTip, pWrist)
            let dThumbWrist = distance(pThumbTip, pWrist)
            
            // Todos os 5 dedos devem estar afastados do pulso
            let isStopSign = dIndexWrist > handScale * 1.0 &&
                             dMiddleWrist > handScale * 1.0 &&
                             dRingWrist > handScale * 0.9 &&
                             dPinkyWrist > handScale * 0.8 &&
                             dThumbWrist > handScale * 0.9
            
            isScrollGestureRaw = isStopSign
        }
        
        // Debouncing do scroll (frames consecutivos)
        if isScrollGestureRaw {
            if scrollFrames == 0 { timeEnteredScrollPosture = agora }
            scrollFrames += 1
            nonScrollFrames = 0
        } else {
            nonScrollFrames += 1
            scrollFrames = 0
        }
        let shouldExitScroll = nonScrollFrames > 5
        let isScrollGestureActive = scrollFrames > 3 && (agora - timeEnteredScrollPosture >= 1.0)
        
        logEstado(thumbRatio: thumbRatio)
        
        // =====================================================================
        // CONTROLE DE ESTADOS (STATE MACHINE)
        // =====================================================================
        switch currentState {
            
        // =================================================================
        // ESTADO 0: NAVEGAÇÃO — ☝️ indicador + dedão recolhido
        // O cursor segue a ponta do indicador livremente.
        // Quando o dedão abre em "L", transita para Trava de Mira.
        // =================================================================
        case .navegacao:
            // Scroll tem prioridade (mão espalmada, 5 dedos)
            if isScrollGestureActive {
                currentState = .scroll
                let mappedPoint = obterPontoMapeado(pontoCam: pIndexTip, tela: telaBounds)
                scrollAnchorY = mappedPoint.y
                OverlayController.shared.show()
                print("↕️ [ESTADO 4] Entrando no Modo Scroll (mão espalmada)")
                return
            }
            
            // Dedão abriu em "L"? → Travar cursor!
            if isThumbOpenConfirmed {
                currentState = .travaMira
                frozenPosition = posicaoCursorAtual
                timeEnteredTravaMira = agora
                historicoPosicoes.removeAll()
                print("🤙 [ESTADO 1] Mão em L! Trava de Mira ativada. Cursor congelado.")
                return
            }
            
            // Navegação livre: cursor segue a ponta do indicador
            let mappedPoint = obterPontoMapeado(pontoCam: pIndexTip, tela: telaBounds)
            
            let preX = preFiltroX.aplicar(valor: mappedPoint.x, alpha: 0.95)
            let preY = preFiltroY.aplicar(valor: mappedPoint.y, alpha: 0.95)
            let filteredX = filtroX.filtrar(valor: preX, timestamp: agora)
            let filteredY = filtroY.filtrar(valor: preY, timestamp: agora)
            let filteredPoint = CGPoint(x: filteredX, y: filteredY)
            
            posicaoCursorAtual = filteredPoint
            frozenPosition = filteredPoint // Mantém atualizado caso congele repentinamente
            
            historicoPosicoes.append(filteredPoint)
            if historicoPosicoes.count > 10 { historicoPosicoes.removeFirst() }
            
            postMouseEvent(type: .mouseMoved, point: posicaoCursorAtual, clickCount: 1, isRightClick: false)
            
        // =================================================================
        // ESTADO 1: TRAVA DE MIRA — Dedão aberto em "L", cursor congelado
        // Aguarda o dedão fechar (puxar o gatilho) para clicar.
        // Se o dedão recolher sem chegar ao gatilho, volta para navegação.
        // =================================================================
        case .travaMira:
            // Timeout de segurança
            if agora - timeEnteredTravaMira > travaMiraTimeout {
                currentState = .navegacao
                thumbOpenFrames = 0
                thumbCloseFrames = 0
                preFiltroX.y = frozenPosition.x
                preFiltroY.y = frozenPosition.y
                filtroX.travarPosicao(frozenPosition.x)
                filtroY.travarPosicao(frozenPosition.y)
                print("⏰ [TIMEOUT] Trava expirou após \(travaMiraTimeout)s. Retornando à navegação.")
                return
            }
            
            // Dedão FECHOU completamente? → Puxou o gatilho → CLIQUE!
            if isThumbCloseConfirmed {
                currentState = .cliqueArraste
                iniciarClique(agora: agora, wrist: pWrist)
                return
            }
            
            // Dedão RECOLHEU (sem chegar a fechar completamente)? → Desistiu
            // Isso acontece quando o ratio volta para a zona neutra (nem aberto nem fechado)
            if !isThumbOpen && !isThumbClosed {
                thumbOpenFrames = 0
                thumbCloseFrames = 0
                currentState = .navegacao
                preFiltroX.y = frozenPosition.x
                preFiltroY.y = frozenPosition.y
                filtroX.travarPosicao(frozenPosition.x)
                filtroY.travarPosicao(frozenPosition.y)
                print("☝️ [ESTADO 0] Dedão recolheu sem clicar. Voltou à navegação.")
                return
            }
            
            // Alimentar filtros silenciosamente para evitar salto ao retornar
            let mappedPoint = obterPontoMapeado(pontoCam: pIndexTip, tela: telaBounds)
            let preX = preFiltroX.aplicar(valor: mappedPoint.x, alpha: 0.95)
            let preY = preFiltroY.aplicar(valor: mappedPoint.y, alpha: 0.95)
            _ = filtroX.filtrar(valor: preX, timestamp: agora)
            _ = filtroY.filtrar(valor: preY, timestamp: agora)
            filtroX.travarPosicao(frozenPosition.x)
            filtroY.travarPosicao(frozenPosition.y)
            
            // Manter cursor congelado no OS
            postMouseEvent(type: .mouseMoved, point: frozenPosition, clickCount: 1, isRightClick: false)
            
        // =================================================================
        // ESTADO 2: CLIQUE/ARRASTE — Dedão fechado (gatilho puxado), mouseDown ativo
        // Detecta: hold para right-click, movimento para drag.
        // Quando o dedão abre novamente, solta o clique.
        // =================================================================
        case .cliqueArraste:
            if isThumbClosed {
                // Dedão ainda fechado — avaliar hold/drag
                let tempoPassado = agora - timeEnteredGatilho
                
                // Clique Direito: hold por 1.2 segundos
                if clickCount == 1 && tempoPassado > 1.2 && !isRightClickActive && !dragActive {
                    print("🖱️ [CLIQUE] Hold 1.2s → Menu Direito")
                    postMouseEvent(type: .leftMouseUp, point: posicaoCursorAtual, clickCount: 1, isRightClick: false)
                    postMouseEvent(type: .leftMouseDown, point: posicaoCursorAtual, clickCount: 1, isRightClick: true)
                    self.isRightClickActive = true
                }
                
                // Iniciar Arraste (detectar movimento do braço via wrist)
                // O indicador continua reto e visível → rastreamento 100% estável
                if !dragActive && !isRightClickActive {
                    let curX = 1.0 - pWrist.x
                    let curY = 1.0 - pWrist.y
                    let ancX = 1.0 - anchorHandPosition.x
                    let ancY = 1.0 - anchorHandPosition.y
                    let deltaDist = sqrt(pow(curX - ancX, 2) + pow(curY - ancY, 2))
                    
                    if clickCount == 1 && deltaDist > 0.015 {
                        dragActive = true
                        anchorHandPosition = pWrist
                        cursorAnchor = frozenPosition
                        dragFilterX.y = frozenPosition.x
                        dragFilterY.y = frozenPosition.y
                        print("🔄 [ESTADO 2] Drag ativado — indicador reto, rastreamento estável")
                    }
                }
                
                // Atualizar posição durante arraste (usando wrist — estável com dedão fechado)
                if dragActive {
                    let rawMapped = obterPontoMapeado(pontoCam: pWrist, tela: telaBounds)
                    let targetX = rawMapped.x + dragOffset.x
                    let targetY = rawMapped.y + dragOffset.y
                    
                    let filteredX = dragFilterX.aplicar(valor: targetX, alpha: 0.18)
                    let filteredY = dragFilterY.aplicar(valor: targetY, alpha: 0.18)
                    
                    let clampedX = max(0, min(telaBounds.width, filteredX))
                    let clampedY = max(0, min(telaBounds.height, filteredY))
                    
                    posicaoCursorAtual = CGPoint(x: clampedX, y: clampedY)
                    postMouseEvent(type: .leftMouseDragged, point: posicaoCursorAtual, clickCount: clickCount, isRightClick: isRightClickActive)
                }
            } else {
                // Dedão abriu novamente → Soltar clique (mouseUp)
                let dispatchClickCount: Int64 = isRightClickActive ? 1 : clickCount
                postMouseEvent(type: .leftMouseUp, point: posicaoCursorAtual, clickCount: dispatchClickCount, isRightClick: isRightClickActive)
                
                lastClickReleaseTime = agora
                thumbOpenFrames = 0
                thumbCloseFrames = 0
                
                if !dragActive {
                    currentState = .navegacao
                    preFiltroX.y = posicaoCursorAtual.x
                    preFiltroY.y = posicaoCursorAtual.y
                    filtroX.travarPosicao(posicaoCursorAtual.x)
                    filtroY.travarPosicao(posicaoCursorAtual.y)
                    print("☝️ [ESTADO 0] Gatilho solto. Retornando à navegação.")
                } else {
                    currentState = .soltar
                    print("🛑 [ESTADO 3] Drag finalizado.")
                }
            }
            
        // =================================================================
        // ESTADO 3: SOLTAR — Transição limpa de volta à navegação
        // =================================================================
        case .soltar:
            currentState = .navegacao
            thumbOpenFrames = 0
            thumbCloseFrames = 0
            preFiltroX.y = posicaoCursorAtual.x
            preFiltroY.y = posicaoCursorAtual.y
            filtroX.travarPosicao(posicaoCursorAtual.x)
            filtroY.travarPosicao(posicaoCursorAtual.y)
            
        // =================================================================
        // ESTADO 4: SCROLL — Mão espalmada (5 dedos abertos, joystick vertical)
        // =================================================================
        case .scroll:
            if shouldExitScroll {
                currentState = .navegacao
                thumbOpenFrames = 0
                thumbCloseFrames = 0
                OverlayController.shared.hide()
                print("↕️ [SCROLL] Saindo do modo scroll")
            } else {
                let mappedPoint = obterPontoMapeado(pontoCam: pIndexTip, tela: telaBounds)
                let deltaY = scrollAnchorY - mappedPoint.y
                
                if abs(deltaY) > 20 && agora - lastScrollEventTime > 0.04 {
                    let rawDelta = deltaY - (deltaY > 0 ? 20 : -20)
                    let magnitude = abs(rawDelta)
                    let speed = (magnitude * magnitude) * 0.003
                    let scrollSpeed = deltaY > 0 ? -speed : speed
                    
                    if let scrollEvent = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: Int32(scrollSpeed), wheel2: 0, wheel3: 0) {
                        scrollEvent.post(tap: CGEventTapLocation.cghidEventTap)
                    }
                    lastScrollEventTime = agora
                }
            }
        }
    }
    
    // =========================================================================
    // INJEÇÃO DE EVENTOS NO MACOS
    // =========================================================================
    
    private func postMouseEvent(type: CGEventType, point: CGPoint, clickCount: Int64, isRightClick: Bool) {
        var finalType = type
        var finalButton: CGMouseButton = .left
        
        if isRightClick {
            finalButton = .right
            if type == .leftMouseDown { finalType = .rightMouseDown }
            else if type == .leftMouseUp { finalType = .rightMouseUp }
            else if type == .leftMouseDragged { finalType = .rightMouseDragged }
        }
        
        let source = CGEventSource(stateID: .hidSystemState)
        let event = CGEvent(mouseEventSource: source, mouseType: finalType, mouseCursorPosition: point, mouseButton: finalButton)
        
        event?.setIntegerValueField(.mouseEventClickState, value: clickCount)
        event?.post(tap: .cghidEventTap)
        
        if finalType == .leftMouseDown || finalType == .rightMouseDown {
            DispatchQueue.main.async { NSSound(named: "Pop")?.play() }
        }
    }
}
