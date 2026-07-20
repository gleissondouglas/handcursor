import Foundation
import AVFoundation
import Vision
import CoreGraphics
import Cocoa

// =========================================================================
// 1. FILTRAGEM MATEMÁTICA (One Euro Filter / Low Pass Filter)
// =========================================================================

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
        let te: TimeInterval = 1.0 / 60.0 // Delta fixo para estabilizar a velocidade de filtragem
        
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
    
    func travarPosicao(_ novaPosicao: CGFloat) {
        xFilter.y = novaPosicao
        dxFilter.y = 0.0
    }
}

// =========================================================================
// 2. PERSISTÊNCIA TEMPORAL (Rastreamento de Mão)
// =========================================================================

struct PersistentPoint {
    var point: CGPoint = .zero
    var lostFrames: Int = 0
    var isInitialized: Bool = false
    var maxLostFrames: Int = 15 // Aumentado para tolerância extra a oclusões (ex: dedos sobrepostos)
    
    mutating func update(newPoint: CGPoint?, confidence: Float) {
        // Confiança otimizada para 0.3 para evitar falsos positivos
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
        if lostFrames <= maxLostFrames { // Suaviza oclusões mais longas
            return point
        }
        return nil
    }
}

class HandTracker {
    var indexTip = PersistentPoint()
    var indexMCP = PersistentPoint()
    var thumbTip = PersistentPoint()
    var wrist = PersistentPoint()
    var pinkyMCP = PersistentPoint()
    var middleTip = PersistentPoint()
    var ringTip = PersistentPoint()
    var pinkyTip = PersistentPoint()
    
    func update(from observation: VNHumanHandPoseObservation) {
        let rawIdxTip = try? observation.recognizedPoint(.indexTip)
        let rawIdxMCP = try? observation.recognizedPoint(.indexMCP)
        let rawThumbTip = try? observation.recognizedPoint(.thumbTip)
        let rawWrist = try? observation.recognizedPoint(.wrist)
        let rawPinkyMCP = try? observation.recognizedPoint(.littleMCP)
        let rawMiddleTip = try? observation.recognizedPoint(.middleTip)
        let rawRingTip = try? observation.recognizedPoint(.ringTip)
        let rawPinkyTip = try? observation.recognizedPoint(.littleTip)
        
        indexTip.update(newPoint: rawIdxTip.flatMap { CGPoint(x: $0.x, y: $0.y) }, confidence: rawIdxTip?.confidence ?? 0.0)
        indexMCP.update(newPoint: rawIdxMCP.flatMap { CGPoint(x: $0.x, y: $0.y) }, confidence: rawIdxMCP?.confidence ?? 0.0)
        thumbTip.update(newPoint: rawThumbTip.flatMap { CGPoint(x: $0.x, y: $0.y) }, confidence: rawThumbTip?.confidence ?? 0.0)
        wrist.update(newPoint: rawWrist.flatMap { CGPoint(x: $0.x, y: $0.y) }, confidence: rawWrist?.confidence ?? 0.0)
        pinkyMCP.update(newPoint: rawPinkyMCP.flatMap { CGPoint(x: $0.x, y: $0.y) }, confidence: rawPinkyMCP?.confidence ?? 0.0)
        middleTip.update(newPoint: rawMiddleTip.flatMap { CGPoint(x: $0.x, y: $0.y) }, confidence: rawMiddleTip?.confidence ?? 0.0)
        ringTip.update(newPoint: rawRingTip.flatMap { CGPoint(x: $0.x, y: $0.y) }, confidence: rawRingTip?.confidence ?? 0.0)
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
// 3. MÁQUINA DE ESTADOS E CONTROLE DO CURSOR
// =========================================================================

enum AppState: Int {
    case navegacao = 0       // Estado 0: Navegação livre (.indexMCP + Filtro Cascata)
    case preClique = 1       // Estado 1: Aproximação inicial (mira congelada no pixel atual)
    case cliqueArraste = 2   // Estado 2: Dedos tocando em pinça (MouseDown -> clique ou arraste)
    case soltar = 3          // Estado 3: Retorno à navegação (mouseUp)
    case scroll = 4          // Estado 4: Modo Joystick (Scroll com 2 dedos)
}

enum FingerPosture: String {
    case extended = "Aberto (Navegação)"
    case bending = "Aproximando (Pré-Clique)"
    case fullyBent = "Pinça Ativa (Clique)"
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
        window.level = .floating // Fica no topo de tudo
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
    
    func show() {
        DispatchQueue.main.async { self.window.orderFront(nil) }
    }
    
    func hide() {
        DispatchQueue.main.async { self.window.orderOut(nil) }
    }
}

// =========================================================================
// 4. CONTROLADOR PRINCIPAL DO APLICATIVO
// =========================================================================

class AppController: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let sessaoCaptura = AVCaptureSession()
    private let sequenceHandler = VNSequenceRequestHandler()
    
    // Parâmetros calibráveis de Pinça e Aproximação refinados
    private var limiarClique: CGFloat = 0.34        // Congela o cursor (solicitado pelo usuário)
    private var limiarDesbloqueio: CGFloat = 0.45   // Navegação normal (dedo indicador esticado)
    private var limiarToqueFisico: CGFloat = 0.10   // Exige que as pontas se toquem (solicitado pelo usuário)
    private var limiarLiberacao: CGFloat = 0.15     // Solta o clique rapidamente ao separar um pouquinho
    

    // Filtro Passa-Baixa de pré-processamento quase sem lag (alpha = 0.95 para responsividade extrema)
    private let preFiltroX = LowPassFilter()
    private let preFiltroY = LowPassFilter()
    
    // Filtro One Euro ajustado para eliminar tremores (minCutoff super baixo):
    // minCutoff = 0.05 para máxima estabilidade (mira fixa).
    // beta = 6.0 compensa para velocidade de resposta
    private let filtroX = OneEuroFilter(minCutoff: 0.05, beta: 6.0, dCutoff: 1.0)
    private let filtroY = OneEuroFilter(minCutoff: 0.05, beta: 6.0, dCutoff: 1.0)
    
    // Filtros passa-baixa rápidos para o modo Arraste (alpha = 0.55 para snappiness imediato)
    private let dragFilterX = LowPassFilter()
    private let dragFilterY = LowPassFilter()
    
    private let tracker = HandTracker()
    
    // Gerenciamento de Estado
    private var currentState: AppState = .navegacao
    private var rawPosture: FingerPosture = .extended
    private var currentPosture: FingerPosture = .extended
    
    // Ancoragem e Mira
    private var posicaoCursorAtual: CGPoint = .zero
    private var frozenPosition: CGPoint = .zero
    private var anchorHandPosition: CGPoint = .zero
    private var cursorAnchor: CGPoint = .zero
    private var pinchOffset: CGPoint = .zero
    private var isRightClickActive: Bool = false
    
    // Buffer circular de posições para compensação retroativa de drift de pinça
    private var historicoPosicoes: [CGPoint] = []
    private var rawPostureHistory: [FingerPosture] = [] // Histórico para debouncing de estado
    
    // Parâmetros de clique e arraste
    private var timeEnteredFullyBent: TimeInterval = 0.0
    private var lastClickReleaseTime: TimeInterval = 0.0
    private var clickCount: Int64 = 1
    private var dragActive: Bool = false
    private var dragSensitivity: CGFloat = 2.5
    
    // Controle do Joystick de Scroll
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
        print("📍 MOUSE VIRTUAL ESTILO APPLE VISION PRO (Pinch & Drag)")
        print("- Mira Responsiva: EMA (0.65) + One Euro Filter (beta: 6.0)")
        print("- Congelamento Ultra Precoce (ratio < 0.38) para Mira Fixa")
        print("- Arraste rápido (Drag Filter com alpha 0.55)")
        print("- Janela de Duplo Clique de 0.5s para abertura de arquivos")
        print("- Scroll Joystick: Levante os 2 dedos (indicador e médio) juntos!")
        print("========================================================\n")
        
        // Inicializa a UI na thread principal
        DispatchQueue.main.async {
            _ = OverlayController.shared
        }
        

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
            print("❌ Erro: Câmera não encontrada no Mac!")
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
                let dim = CMVideoFormatDescriptionGetDimensions(formato.formatDescription)
                print("🟢 Câmera ativa: \(dim.width)x\(dim.height) @ 60 FPS")
            }
            
            // --- DESATIVAÇÃO DO CENTER STAGE ---
            // Impede que a câmera dê zoom ou siga o rosto do usuário, garantindo que as proporções
            // da mão fiquem estáticas em relação à tela e o cursor não dê "saltos".
            if #available(macOS 12.0, *) {
                if AVCaptureDevice.isCenterStageEnabled {
                    AVCaptureDevice.centerStageControlMode = .cooperative
                    AVCaptureDevice.isCenterStageEnabled = false
                    print("🚫 Center Stage desativado para garantir precisão do cursor.")
                }
            }
            // -----------------------------------
            
            dispositivo.unlockForConfiguration()
        } catch {
            print("❌ Erro ao configurar formato da câmera.")
        }
        
        sessaoCaptura.commitConfiguration()
        sessaoCaptura.startRunning()
        
        posicaoCursorAtual = CGPoint(x: telaBounds.width / 2.0, y: telaBounds.height / 2.0)
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        try? sequenceHandler.perform([requisicao], on: sampleBuffer, orientation: .up)
    }
    
    private func processarResultado(requisicao: VNRequest, erro: Error?) {
        guard let resultados = requisicao.results as? [VNHumanHandPoseObservation],
              let mao = resultados.first else {
            // Se a mão for perdida, apenas retorna
            return
        }
        
        tracker.update(from: mao)
        

        guard tracker.isDataComplete else { return }
        
        self.avaliarMaquinaEstados()
    }
    
    private func distance(_ p1: CGPoint, _ p2: CGPoint) -> CGFloat {
        let dx = p1.x - p2.x
        let dy = p1.y - p2.y
        return sqrt(dx*dx + dy*dy)
    }
    
    // Configuração de Limiares Otimizada:
    // - extended -> bending (bloqueio de mira): < 0.38 (bloqueia super cedo para garantir precisão no pixel exato)
    // - bending -> fullyBent (mouseDown): < 0.17 (detecta o toque físico de forma extremamente robusta)
    // - fullyBent -> bending (mouseUp): > 0.22 (permite liberação rápida sem emperrar)
    // - bending -> extended (desbloqueio): > 0.44 (destrava a mira assim que a mão abre)
    private func obterEstadoDedoRaw(ratio: CGFloat) -> FingerPosture {
        
        switch rawPosture {
        case .extended:
            if ratio < limiarClique {
                rawPosture = .bending
            }
        case .bending:
            if ratio > limiarDesbloqueio {
                rawPosture = .extended
            } else if ratio < limiarToqueFisico {
                rawPosture = .fullyBent
            }
        case .fullyBent:
            if ratio > limiarLiberacao {
                rawPosture = .bending
            }
        }
        return rawPosture
    }
    
    private func obterEstadoDedoDebounced(ratio: CGFloat) -> FingerPosture {
        let raw = obterEstadoDedoRaw(ratio: ratio)
        
        rawPostureHistory.append(raw)
        if rawPostureHistory.count > 2 {
            rawPostureHistory.removeFirst()
        }
        
        if rawPostureHistory.count == 2 && rawPostureHistory[0] == rawPostureHistory[1] {
            currentPosture = rawPostureHistory[0]
        }
        
        return currentPosture
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
    private func logEstado(ratio: CGFloat, posture: FingerPosture) {
        let agora = CFAbsoluteTimeGetCurrent()
        if agora - ultimoLogTempo > 0.5 {
            print(String(format: "Estado: %@ | Ratio: %.3f | Postura: %@", String(describing: currentState), ratio, posture.rawValue))
            ultimoLogTempo = agora
        }
    }
    
    private func iniciarClique(agora: TimeInterval, wrist: CGPoint, indexTip: CGPoint, thumbTip: CGPoint, indexMCP: CGPoint) {
        let finalIsRightClick = false
        
        let intervalo = agora - lastClickReleaseTime
        
        // Tempo limite do duplo clique ajustado para 0.6s (confortável, mas sem travar cliques futuros)
        if intervalo > 0.15 && intervalo <= 0.6 && lastClickReleaseTime > 0 {
            // Segundo clique -> Duplo Clique Esquerdo
            clickCount = 2
            frozenPosition = cursorAnchor
            print("🔥 [CLIQUE] Duplo clique acionado")
        } else if intervalo <= 0.15 && lastClickReleaseTime > 0 {
            // BOUNCE PROTECTION: Foi rápido demais (< 150ms), impossível ser humano. É tremor da câmera!
            // Não incrementa o contador para evitar menu acidental no primeiro toque.
            print("⚠️ [BOUNCE] Tremor ignorado, mantendo clickCount = \(clickCount)")
        } else {
            // Primeiro clique
            clickCount = 1
            print("👆 [CLIQUE] Clique simples acionado")
        }
        
        self.isRightClickActive = finalIsRightClick
        // ANCORAGEM PELO OSSO DO INDICADOR:
        // A ponta dos dedos (pinchCenter) se move quando você abre a mão para soltar o clique.
        // A base do indicador (indexMCP) fica praticamente imobilizada, garantindo que o cursor não pule no final!
        let rawMapped = obterPontoMapeado(pontoCam: indexMCP, tela: telaBounds)
        pinchOffset = CGPoint(x: frozenPosition.x - rawMapped.x, y: frozenPosition.y - rawMapped.y)
        
        dragActive = false
        timeEnteredFullyBent = agora
        anchorHandPosition = wrist
        cursorAnchor = frozenPosition
        
        dragFilterX.y = frozenPosition.x
        dragFilterY.y = frozenPosition.y
        preFiltroX.y = frozenPosition.x
        preFiltroY.y = frozenPosition.y
        filtroX.travarPosicao(frozenPosition.x)
        filtroY.travarPosicao(frozenPosition.y)
        
        // Hack para Duplo Clique Lento:
        // O macOS nativamente só aceita duplo-clique se o intervalo for < 0.5s.
        // Como o usuário pode levar até 0.9s (para maior conforto), o macOS ignoraria nosso clickCount=2.
        // A mágica: Injetamos um clique 1 "fantasma" no exato milissegundo antes do clique 2!
        if clickCount == 2 {
            postMouseEvent(type: .leftMouseDown, point: frozenPosition, clickCount: 1, isRightClick: false)
            postMouseEvent(type: .leftMouseUp, point: frozenPosition, clickCount: 1, isRightClick: false)
        }
        
        let dispatchClickCount: Int64 = finalIsRightClick ? 1 : clickCount
        postMouseEvent(type: .leftMouseDown, point: frozenPosition, clickCount: dispatchClickCount, isRightClick: finalIsRightClick)
    }
    
    private func avaliarMaquinaEstados() {
        guard let pIndexTip = tracker.indexTip.getPoint(),
              let pIndexMCP = tracker.indexMCP.getPoint(),
              let pThumbTip = tracker.thumbTip.getPoint(),
              let pWrist = tracker.wrist.getPoint(),
              let pPinkyMCP = tracker.pinkyMCP.getPoint() else {
            return
        }
        
        let agora = CFAbsoluteTimeGetCurrent()
        
        let dIndexThumb = distance(pIndexTip, pThumbTip)
        
        // Cálculo Ultra-Robusto (Invariante à Rotação 3D):
        // Formamos um triângulo com o Pulso, a Base do Indicador (IndexMCP) e a Base do Mindinho (PinkyMCP).
        // Pegamos a MAIOR aresta visível desse triângulo. Assim, não importa se você vira a mão
        // pra cima, pro lado ou pra você: a escala sempre será baseada no lado que sofreu menos distorção 2D!
        let edge1 = distance(pIndexMCP, pWrist)
        let edge2 = distance(pIndexMCP, pPinkyMCP)
        let edge3 = distance(pWrist, pPinkyMCP)
        let handScale = max(edge1, max(edge2, edge3))
        
        let ratio = handScale > 0.01 ? (dIndexThumb / handScale) : 1.0
        
        var isScrollGestureRaw = false
        if let pMiddleTip = tracker.middleTip.getPoint(),
           let pRingTip = tracker.ringTip.getPoint(),
           let pPinkyTip = tracker.pinkyTip.getPoint() {
            let dIndexWrist = distance(pIndexTip, pWrist)
            let dMiddleWrist = distance(pMiddleTip, pWrist)
            let dRingWrist = distance(pRingTip, pWrist)
            let dPinkyWrist = distance(pPinkyTip, pWrist)
            let dThumbWrist = distance(pThumbTip, pWrist)
            
            // Heurística de "Mão de PARE" (Palma aberta de frente para a câmera).
            // A Inteligência Artificial mapeia perfeitamente as juntas nessa posição.
            // Todos os dedos devem estar esticados (distância grande do pulso)
            let isStopSign = dIndexWrist > handScale * 1.0 &&
                             dMiddleWrist > handScale * 1.0 &&
                             dRingWrist > handScale * 0.9 &&
                             dPinkyWrist > handScale * 0.8 &&
                             dThumbWrist > handScale * 0.9
            
            isScrollGestureRaw = isStopSign
            
            if isScrollGestureRaw {
                if scrollFrames == 0 {
                    timeEnteredScrollPosture = agora
                }
                scrollFrames += 1
                nonScrollFrames = 0
            } else {
                nonScrollFrames += 1
                scrollFrames = 0
            }
        }
        
        let isScrollPosture = scrollFrames > 3
        let shouldExitScroll = nonScrollFrames > 5
        let isScrollGestureActive = isScrollPosture && (agora - timeEnteredScrollPosture >= 1.0)
        
        let posture = obterEstadoDedoDebounced(ratio: ratio)
        logEstado(ratio: ratio, posture: posture)
        
        switch currentState {
        case .navegacao: // Estado 0 — Navegação Livre
            if isScrollGestureActive {
                currentState = .scroll
                let mappedPoint = obterPontoMapeado(pontoCam: pIndexTip, tela: telaBounds)
                scrollAnchorY = mappedPoint.y
                OverlayController.shared.show()
                print("↕️ [ESTADO 4] Entrando no Modo Scroll (Joystick)")
                return
            }
            
            if posture == .extended {
                // Reduzido para 0.35s! Libera a mira super rápido após soltar o clique, dando agilidade.
                if agora - lastClickReleaseTime <= 0.35 && lastClickReleaseTime > 0 {
                    // JANELA DE CLIQUE MULTIPLO: A mira fica ancorada na frozenPosition.
                    // Permite abrir a mão o quanto quiser para preparar o duplo/triplo clique sem arrastar o cursor.
                    posicaoCursorAtual = frozenPosition
                    
                    // Alimenta os filtros para evitar pulos quando a janela de tempo acabar
                    let _ = preFiltroX.aplicar(valor: frozenPosition.x, alpha: 0.95)
                    let _ = preFiltroY.aplicar(valor: frozenPosition.y, alpha: 0.95)
                    filtroX.travarPosicao(frozenPosition.x)
                    filtroY.travarPosicao(frozenPosition.y)
                    
                    historicoPosicoes.append(frozenPosition)
                    if historicoPosicoes.count > 10 { historicoPosicoes.removeFirst() }
                    
                    postMouseEvent(type: .mouseMoved, point: frozenPosition, clickCount: 1, isRightClick: false)
                } else {
                    // MIRA PELO CENTRO DA PINÇA (Elimina o desvio de mira quando o dedo dobra)
                    let pinchCenter = CGPoint(x: (pIndexTip.x + pThumbTip.x) / 2.0, y: (pIndexTip.y + pThumbTip.y) / 2.0)
                    let mappedPoint = obterPontoMapeado(pontoCam: pinchCenter, tela: telaBounds)
                    
                    // --- LÓGICA DE DESACELERAÇÃO GRAVITACIONAL ---
                    // Começa a frear aos 0.45 (indicador apontando), e freia quase totalmente quando chega perto de 0.34 (pausa antecipada)
                    let maxRatio: CGFloat = 0.45
                    let minRatio: CGFloat = 0.34
                    let clampedRatio = max(minRatio, min(maxRatio, ratio))
                    let normalized = (clampedRatio - minRatio) / (maxRatio - minRatio) // 0.0 (perto) a 1.0 (longe)
                    
                    // Usando uma curva não-linear (potência) para que fique pesado mais rápido no final
                    let dynamicCutoff = 0.001 + (1.80 - 0.001) * (normalized * normalized) // 1.80 para agilidade extrema com a mão aberta!
                    let dynamicBeta = 0.0 + (6.0 - 0.0) * normalized // Zera o momentum quando próximo do clique
                    filtroX.minCutoff = dynamicCutoff
                    filtroY.minCutoff = dynamicCutoff
                    filtroX.beta = dynamicBeta
                    filtroY.beta = dynamicBeta
                    
                    let preX = preFiltroX.aplicar(valor: mappedPoint.x, alpha: 0.95)
                    let preY = preFiltroY.aplicar(valor: mappedPoint.y, alpha: 0.95)
                    
                    let filteredX = filtroX.filtrar(valor: preX, timestamp: agora)
                    let filteredY = filtroY.filtrar(valor: preY, timestamp: agora)
                    let filteredPoint = CGPoint(x: filteredX, y: filteredY)
                    
                    posicaoCursorAtual = filteredPoint
                    frozenPosition = filteredPoint
                    
                    historicoPosicoes.append(filteredPoint)
                    if historicoPosicoes.count > 10 { // Retrocesso de 10 frames (~166ms) garante que a mira congele antes do dedo se mover
                        historicoPosicoes.removeFirst()
                    }
                    
                    postMouseEvent(type: .mouseMoved, point: posicaoCursorAtual, clickCount: 1, isRightClick: false)
                }
            } else if posture == .bending {
                currentState = .preClique
                // FIM DO "PULINHO": Congela exatamente onde o cursor está agora, sem voltar no tempo!
                frozenPosition = posicaoCursorAtual
                historicoPosicoes.removeAll()
                print("🔒 [ESTADO 1] Cursor totalmente congelado para o clique.")
            } else if posture == .fullyBent {
                currentState = .cliqueArraste
                frozenPosition = posicaoCursorAtual
                historicoPosicoes.removeAll()
                iniciarClique(agora: agora, wrist: pWrist, indexTip: pIndexTip, thumbTip: pThumbTip, indexMCP: pIndexMCP)
            }
            
        case .preClique: // Estado 1 — Pré-Clique
            if posture == .extended {
                currentState = .navegacao
                print("☝️ [ESTADO 0] Retornando para Navegação livre.")
            } else if posture == .bending {
                // Congelamento total: o cursor não se move enquanto o dedo estiver dobrando para clicar.
                // Isso garante que o clique aconteça no lugar exato onde o movimento de pinça começou.
                posicaoCursorAtual = frozenPosition
                
                // Atualizar rastreamento interno, mas sem mover o cursor visível.
                let mappedPoint = obterPontoMapeado(pontoCam: pIndexTip, tela: telaBounds)
                let preX = preFiltroX.aplicar(valor: mappedPoint.x, alpha: 0.95)
                let preY = preFiltroY.aplicar(valor: mappedPoint.y, alpha: 0.95)
                _ = filtroX.filtrar(valor: preX, timestamp: agora)
                _ = filtroY.filtrar(valor: preY, timestamp: agora)
                
                // Travar os filtros na posição congelada para evitar saltos ou desvios ao retomar.
                filtroX.travarPosicao(frozenPosition.x)
                filtroY.travarPosicao(frozenPosition.y)
                
                postMouseEvent(type: .mouseMoved, point: frozenPosition, clickCount: 1, isRightClick: false)
            } else if posture == .fullyBent {
                currentState = .cliqueArraste
                iniciarClique(agora: agora, wrist: pWrist, indexTip: pIndexTip, thumbTip: pThumbTip, indexMCP: pIndexMCP)
            }
            
        case .cliqueArraste: // Estado 2 — Clique / Arraste
            if posture == .fullyBent {
                let tempoPassado = agora - timeEnteredFullyBent
                
                // --- MENU DIREITO (LONG PRESS) ---
                // Se for o 1º clique, segurar por 0.8s e não tiver movido a mão (arrastado), abre o menu!
                if clickCount == 1 && tempoPassado > 0.8 && !isRightClickActive && !dragActive {
                    print("⚡️ [CLIQUE] Segurou parado -> Menu (Clique Direito)")
                    postMouseEvent(type: .leftMouseUp, point: posicaoCursorAtual, clickCount: 1, isRightClick: false)
                    postMouseEvent(type: .leftMouseDown, point: posicaoCursorAtual, clickCount: 1, isRightClick: true)
                    self.isRightClickActive = true
                }
                
                // --- ARRASTAR (POR MOVIMENTO) ---
                // Só arrasta se for o 1º clique e o menu direito ainda não tiver aberto
                if !dragActive && !isRightClickActive {
                    let curX = 1.0 - pWrist.x
                    let curY = 1.0 - pWrist.y
                    let ancX = 1.0 - anchorHandPosition.x
                    let ancY = 1.0 - anchorHandPosition.y
                    let dx = curX - ancX
                    let dy = curY - ancY
                    let deltaDist = sqrt(dx*dx + dy*dy)
                    
                    // O arraste é puramente por movimento. Moveu a mão um pouquinho (0.015), gruda!
                    if clickCount == 1 && deltaDist > 0.015 {
                        dragActive = true
                        anchorHandPosition = pWrist
                        cursorAnchor = frozenPosition
                        dragFilterX.y = frozenPosition.x
                        dragFilterY.y = frozenPosition.y
                        print("🔄 [ESTADO 2 - ARRASTE] Drag ativado instantaneamente por movimento.")
                    }
                }
                
                if dragActive {
                    // A base do indicador não abre e fecha durante o soltar, evitando aquele salto no final do arraste
                    let rawMapped = obterPontoMapeado(pontoCam: pIndexMCP, tela: telaBounds)
                    let targetX = rawMapped.x + pinchOffset.x
                    let targetY = rawMapped.y + pinchOffset.y
                    
                    // Alpha mega reduzido (de 0.55 para 0.18) para a mira ser pesada e exata enquanto seleciona texto!
                    let filteredX = dragFilterX.aplicar(valor: targetX, alpha: 0.18)
                    let filteredY = dragFilterY.aplicar(valor: targetY, alpha: 0.18)
                    
                    let clampedX = max(0, min(telaBounds.width, filteredX))
                    let clampedY = max(0, min(telaBounds.height, filteredY))
                    
                    posicaoCursorAtual = CGPoint(x: clampedX, y: clampedY)
                    postMouseEvent(type: .leftMouseDragged, point: posicaoCursorAtual, clickCount: clickCount, isRightClick: isRightClickActive)
                }
            } else {
                let dispatchClickCount: Int64 = isRightClickActive ? 1 : clickCount
                postMouseEvent(type: .leftMouseUp, point: posicaoCursorAtual, clickCount: dispatchClickCount, isRightClick: isRightClickActive)
                print(String(format: "💥 [SOLTOU] leftMouseUp em %@ | clickCount: %d | RightClick: %@", String(describing: posicaoCursorAtual), dispatchClickCount, isRightClickActive ? "SIM" : "NAO"))
                
                if !dragActive {
                    lastClickReleaseTime = agora
                    if posture == .extended {
                        currentState = .navegacao
                        preFiltroX.y = posicaoCursorAtual.x
                        preFiltroY.y = posicaoCursorAtual.y
                        filtroX.travarPosicao(posicaoCursorAtual.x)
                        filtroY.travarPosicao(posicaoCursorAtual.y)
                        print("☝️ [ESTADO 0] Retornando para Navegação.")
                    } else if posture == .bending {
                        currentState = .preClique
                        frozenPosition = posicaoCursorAtual
                        print("🔒 [ESTADO 1] Retornando para Pré-Clique (Manter mira congelada).")
                    }
                } else {
                    // O arraste acabou. Como solicitado, vamos emitir um clique direito automático
                    // para abrir o menu de contexto (útil para copiar texto após selecionar).
                    postMouseEvent(type: .rightMouseDown, point: posicaoCursorAtual, clickCount: 1, isRightClick: true)
                    postMouseEvent(type: .rightMouseUp, point: posicaoCursorAtual, clickCount: 1, isRightClick: true)
                    print("⚡️ [AUTO MENU] Clique direito disparado automaticamente após o arraste!")
                    
                    currentState = .soltar
                    print("🛑 [ESTADO 3] Finalizando Drag.")
                }
            }
            
        case .soltar: // Estado 3 — Soltar
            currentState = .navegacao
            preFiltroX.y = posicaoCursorAtual.x
            preFiltroY.y = posicaoCursorAtual.y
            filtroX.travarPosicao(posicaoCursorAtual.x)
            filtroY.travarPosicao(posicaoCursorAtual.y)
            print("☝️ [ESTADO 0] Retornando para Navegação após Soltar.")
            
        case .scroll: // Estado 4 — Modo Scroll
            if shouldExitScroll {
                currentState = .navegacao
                OverlayController.shared.hide()
                print("☝️ [ESTADO 0] Saindo do Modo Scroll")
            } else {
                let mappedPoint = obterPontoMapeado(pontoCam: pIndexTip, tela: telaBounds)
                let deltaY = scrollAnchorY - mappedPoint.y // Positivo = Mão subiu = Scroll UP
                
                // Zona morta de 20 pixels para não rolar se a mão estiver parada
                if abs(deltaY) > 20 {
                    if agora - lastScrollEventTime > 0.04 { // 25 Hz (suavidade extrema)
                        let rawDelta = deltaY - (deltaY > 0 ? 20 : -20)
                        let magnitude = abs(rawDelta)
                        
                        // Curva Quadrática: Controle microscópico perto do centro, velocidade hiper-rápida nas pontas!
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
    }
    
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
            DispatchQueue.main.async {
                NSSound(named: "Pop")?.play()
            }
        }
    }
}

// =========================================================================
// 4. PONTO DE ENTRADA DO APLICATIVO
// =========================================================================

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let appController = AppController()
appController.iniciar()
app.run()
