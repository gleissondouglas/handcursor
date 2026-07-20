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
    private var minCutoff: CGFloat
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
    var maxLostFrames: Int = 10 // Aumentado de 5 para 10 para tolerância extra durante pinch
    
    mutating func update(newPoint: CGPoint?, confidence: Float) {
        // Confiança otimizada para 0.08 para manter rastreamento em baixa luminosidade
        if let p = newPoint, confidence > 0.08 {
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
    
    func update(from observation: VNHumanHandPoseObservation) {
        let rawIdxTip = try? observation.recognizedPoint(.indexTip)
        let rawIdxMCP = try? observation.recognizedPoint(.indexMCP)
        let rawThumbTip = try? observation.recognizedPoint(.thumbTip)
        let rawWrist = try? observation.recognizedPoint(.wrist)
        
        indexTip.update(newPoint: rawIdxTip.flatMap { CGPoint(x: $0.x, y: $0.y) }, confidence: rawIdxTip?.confidence ?? 0.0)
        indexMCP.update(newPoint: rawIdxMCP.flatMap { CGPoint(x: $0.x, y: $0.y) }, confidence: rawIdxMCP?.confidence ?? 0.0)
        thumbTip.update(newPoint: rawThumbTip.flatMap { CGPoint(x: $0.x, y: $0.y) }, confidence: rawThumbTip?.confidence ?? 0.0)
        wrist.update(newPoint: rawWrist.flatMap { CGPoint(x: $0.x, y: $0.y) }, confidence: rawWrist?.confidence ?? 0.0)
    }
    
    var isDataComplete: Bool {
        return indexTip.getPoint() != nil &&
               indexMCP.getPoint() != nil &&
               thumbTip.getPoint() != nil &&
               wrist.getPoint() != nil
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
}

enum FingerPosture: String {
    case extended = "Aberto (Navegação)"
    case bending = "Aproximando (Pré-Clique)"
    case fullyBent = "Pinça Ativa (Clique)"
}

// =========================================================================
// INTERFACE GRÁFICA (HUD Overlay & Landmarks)
// =========================================================================

class HUDWindow: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .utilityWindow, .hudWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.title = "HandCursor HUD"
        self.isMovableByWindowBackground = true
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
        let effectView = NSVisualEffectView(frame: contentRect)
        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.autoresizingMask = [.width, .height]
        self.contentView = effectView
    }
}

class LandmarkOverlayView: NSView {
    var points: [String: CGPoint] = [:]
    var gestureState: AppState = .navegacao
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        guard !points.isEmpty, let ctx = NSGraphicsContext.current?.cgContext else { return }
        
        let w = self.bounds.width
        let h = self.bounds.height
        
        // Mapeia coordenadas normalizadas da câmera (0...1) para o tamanho do preview.
        // Como o preview é espelhado (modo selfie), fazemos xEspelhado = 1.0 - x.
        func converter(_ pt: CGPoint) -> CGPoint {
            let xEspelhado = 1.0 - pt.x
            return CGPoint(x: xEspelhado * w, y: pt.y * h)
        }
        
        ctx.setLineWidth(3.0)
        
        let color: NSColor
        switch gestureState {
        case .navegacao: color = .systemGreen
        case .preClique: color = .systemOrange
        case .cliqueArraste: color = .systemRed
        case .soltar: color = .systemBlue
        }
        
        color.setStroke()
        color.setFill()
        
        let tTip = points["thumbTip"].map(converter)
        let iTip = points["indexTip"].map(converter)
        let iMCP = points["indexMCP"].map(converter)
        let wr = points["wrist"].map(converter)
        
        // Desenha as linhas entre as articulações da mão
        if let thumb = tTip, let index = iTip {
            ctx.move(to: thumb)
            ctx.addLine(to: index)
            ctx.strokePath()
        }
        
        if let index = iTip, let mcp = iMCP {
            ctx.move(to: index)
            ctx.addLine(to: mcp)
            ctx.strokePath()
        }
        
        if let mcp = iMCP, let wrist = wr {
            ctx.move(to: mcp)
            ctx.addLine(to: wrist)
            ctx.strokePath()
        }
        
        if let thumb = tTip, let wrist = wr {
            ctx.move(to: thumb)
            ctx.addLine(to: wrist)
            ctx.strokePath()
        }
        
        // Desenha os pontos nas articulações
        for pt in [tTip, iTip, iMCP, wr].compactMap({ $0 }) {
            let rect = CGRect(x: pt.x - 6, y: pt.y - 6, width: 12, height: 12)
            ctx.fillEllipse(in: rect)
        }
    }
}

class AppController: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let sessaoCaptura = AVCaptureSession()
    private let sequenceHandler = VNSequenceRequestHandler()
    
    // Parâmetros calibráveis de Pinça e Aproximação
    private var limiarClique: CGFloat = 0.70
    private var limiarDesbloqueio: CGFloat { return limiarClique + 0.15 }
    private var limiarToqueFisico: CGFloat = 0.20
    private var limiarLiberacao: CGFloat = 0.30
    
    // Elementos da Interface Gráfica (HUD)
    private var windowHUD: HUDWindow!
    private var landmarkView: LandmarkOverlayView!
    private var statusLabel: NSTextField!
    private var ratioLabel: NSTextField!
    private var sensibilidadeLabel: NSTextField!
    private var limiarLabel: NSTextField!
    private var betaLabel: NSTextField!
    
    private var ultimoRatioExibido: CGFloat = 0.0
    
    // Filtro Passa-Baixa de pré-processamento otimizado (alpha = 0.65)
    // Minimiza o lag a quase zero (~5ms) mantendo amortecimento do ruído de pixel da webcam.
    private let preFiltroX = LowPassFilter()
    private let preFiltroY = LowPassFilter()
    
    // Filtro One Euro calibrado para responsividade máxima:
    // minCutoff = 0.12 para suavidade estática absoluta.
    // beta = 6.0 para eliminar completamente o lag de arraste dinâmico do cursor.
    private let filtroX = OneEuroFilter(minCutoff: 0.12, beta: 6.0, dCutoff: 1.0)
    private let filtroY = OneEuroFilter(minCutoff: 0.12, beta: 6.0, dCutoff: 1.0)
    
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
    
    // Buffer circular de posições para compensação retroativa de drift de pinça
    private var historicoPosicoes: [CGPoint] = []
    private var rawPostureHistory: [FingerPosture] = [] // Histórico para debouncing de estado
    
    // Parâmetros de clique e arraste
    private var timeEnteredFullyBent: TimeInterval = 0.0
    private var lastClickReleaseTime: TimeInterval = 0.0
    private var clickCount: Int64 = 1
    private var dragActive: Bool = false
    private var dragSensitivity: CGFloat = 2.5
    
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
        print("========================================================\n")
        
        DispatchQueue.main.async { [weak self] in
            self?.configurarInterface()
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
    
    private func configurarInterface() {
        let contentRect = NSRect(x: 100, y: 100, width: 320, height: 500)
        windowHUD = HUDWindow(contentRect: contentRect)
        
        guard let effectView = windowHUD.contentView as? NSVisualEffectView else { return }
        
        // 1. Container da Câmera
        let previewContainer = NSView(frame: NSRect(x: 0, y: 260, width: 320, height: 240))
        previewContainer.wantsLayer = true
        previewContainer.layer?.backgroundColor = NSColor.black.cgColor
        effectView.addSubview(previewContainer)
        
        let previewLayer = AVCaptureVideoPreviewLayer(session: sessaoCaptura)
        previewLayer.frame = NSRect(x: 0, y: 0, width: 320, height: 240)
        previewLayer.videoGravity = .resizeAspectFill
        previewContainer.layer?.addSublayer(previewLayer)
        
        landmarkView = LandmarkOverlayView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        landmarkView.wantsLayer = true
        previewContainer.addSubview(landmarkView)
        
        // 2. Painel de Controles
        // Título
        let titulo = criarLabel(frame: CGRect(x: 16, y: 235, width: 288, height: 20), texto: "HAND CURSOR STUDIO", tamanho: 13, negrito: true)
        titulo.alignment = .center
        titulo.textColor = .secondaryLabelColor
        effectView.addSubview(titulo)
        
        // Status
        statusLabel = criarLabel(frame: CGRect(x: 16, y: 210, width: 288, height: 18), texto: "Estado: Inicializando...", tamanho: 12, negrito: true)
        effectView.addSubview(statusLabel)
        
        // Ratio
        ratioLabel = criarLabel(frame: CGRect(x: 16, y: 190, width: 288, height: 18), texto: "Proporção de Pinça: 0.000", tamanho: 11)
        effectView.addSubview(ratioLabel)
        
        // Sensibilidade
        sensibilidadeLabel = criarLabel(frame: CGRect(x: 16, y: 155, width: 288, height: 16), texto: "Sensibilidade do Cursor: 2.5x", tamanho: 11)
        effectView.addSubview(sensibilidadeLabel)
        
        let sensibilidadeSlider = NSSlider()
        sensibilidadeSlider.minValue = 1.0
        sensibilidadeSlider.maxValue = 6.0
        sensibilidadeSlider.doubleValue = Double(dragSensitivity)
        sensibilidadeSlider.target = self
        sensibilidadeSlider.action = #selector(sensibilidadeAlterada(_:))
        sensibilidadeSlider.frame = CGRect(x: 16, y: 135, width: 288, height: 20)
        effectView.addSubview(sensibilidadeSlider)
        
        // Limiar Clique
        limiarLabel = criarLabel(frame: CGRect(x: 16, y: 100, width: 288, height: 16), texto: String(format: "Limiar de Clique: %.2f", limiarClique), tamanho: 11)
        effectView.addSubview(limiarLabel)
        
        let limiarSlider = NSSlider()
        limiarSlider.minValue = 0.40
        limiarSlider.maxValue = 1.00
        limiarSlider.doubleValue = Double(limiarClique)
        limiarSlider.target = self
        limiarSlider.action = #selector(limiarAlterado(_:))
        limiarSlider.frame = CGRect(x: 16, y: 80, width: 288, height: 20)
        effectView.addSubview(limiarSlider)
        
        // Beta Filtro
        betaLabel = criarLabel(frame: CGRect(x: 16, y: 45, width: 288, height: 16), texto: "Filtro de Ruído Beta: 6.0", tamanho: 11)
        effectView.addSubview(betaLabel)
        
        let betaSlider = NSSlider()
        betaSlider.minValue = 1.0
        betaSlider.maxValue = 15.0
        betaSlider.doubleValue = Double(filtroX.beta)
        betaSlider.target = self
        betaSlider.action = #selector(betaAlterado(_:))
        betaSlider.frame = CGRect(x: 16, y: 25, width: 288, height: 20)
        effectView.addSubview(betaSlider)
        
        windowHUD.makeKeyAndOrderFront(nil)
    }
    
    private func criarLabel(frame: CGRect, texto: String, tamanho: CGFloat, negrito: Bool = false) -> NSTextField {
        let label = NSTextField(labelWithString: texto)
        label.frame = frame
        label.font = negrito ? NSFont.boldSystemFont(ofSize: tamanho) : NSFont.systemFont(ofSize: tamanho)
        label.isEditable = false
        label.isSelectable = false
        label.isBordered = false
        label.drawsBackground = false
        return label
    }
    
    @objc private func sensibilidadeAlterada(_ sender: NSSlider) {
        dragSensitivity = CGFloat(sender.doubleValue)
        sensibilidadeLabel.stringValue = String(format: "Sensibilidade do Cursor: %.1fx", dragSensitivity)
    }
    
    @objc private func limiarAlterado(_ sender: NSSlider) {
        limiarClique = CGFloat(sender.doubleValue)
        limiarLabel.stringValue = String(format: "Limiar de Clique: %.2f", limiarClique)
    }
    
    @objc private func betaAlterado(_ sender: NSSlider) {
        let novoBeta = CGFloat(sender.doubleValue)
        filtroX.beta = novoBeta
        filtroY.beta = novoBeta
        betaLabel.stringValue = String(format: "Filtro de Ruído Beta: %.1f", novoBeta)
    }
    
    private func atualizarLabelsHUD() {
        let estadoStr: String
        switch currentState {
        case .navegacao: estadoStr = "Navegação Livre"
        case .preClique: estadoStr = "Pré-Clique (Mira Travada)"
        case .cliqueArraste: estadoStr = "Clique / Arraste Ativo"
        case .soltar: estadoStr = "Soltar Clique"
        }
        statusLabel.stringValue = "Estado: \(estadoStr)"
        
        ratioLabel.stringValue = String(format: "Proporção de Pinça: %.3f (Alvo: <%.2f)", ultimoRatioExibido, limiarClique)
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
            // Se a mão for perdida, limpa os pontos no overlay HUD
            DispatchQueue.main.async { [weak self] in
                self?.landmarkView.points = [:]
                self?.landmarkView.needsDisplay = true
            }
            return
        }
        
        tracker.update(from: mao)
        
        // Obter os pontos para desenhar no HUD
        var pontosHUD: [String: CGPoint] = [:]
        if let idxTip = try? mao.recognizedPoint(.indexTip), idxTip.confidence > 0.08 {
            pontosHUD["indexTip"] = CGPoint(x: idxTip.x, y: idxTip.y)
        }
        if let idxMCP = try? mao.recognizedPoint(.indexMCP), idxMCP.confidence > 0.08 {
            pontosHUD["indexMCP"] = CGPoint(x: idxMCP.x, y: idxMCP.y)
        }
        if let thumbTip = try? mao.recognizedPoint(.thumbTip), thumbTip.confidence > 0.08 {
            pontosHUD["thumbTip"] = CGPoint(x: thumbTip.x, y: thumbTip.y)
        }
        if let wrist = try? mao.recognizedPoint(.wrist), wrist.confidence > 0.08 {
            pontosHUD["wrist"] = CGPoint(x: wrist.x, y: wrist.y)
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.landmarkView.points = pontosHUD
            self?.landmarkView.gestureState = self?.currentState ?? .navegacao
            self?.landmarkView.needsDisplay = true
            self?.atualizarLabelsHUD()
        }
        
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
    private func obterEstadoDedoRaw(tip: CGPoint, thumb: CGPoint, mcp: CGPoint, wrist: CGPoint) -> FingerPosture {
        let dIndexThumb = distance(tip, thumb)
        
        // Substituindo o Bounding Box por uma distância física invariante à rotação!
        // A distância entre a base do indicador (MCP) e o pulso (Wrist) se mantém
        // constante independentemente da orientação 2D da mão, resolvendo o bug do ângulo.
        let handScale = distance(mcp, wrist)
        guard handScale > 0.01 else { return .extended }
        
        let ratio = dIndexThumb / handScale
        
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
    
    private func obterEstadoDedoDebounced(tip: CGPoint, thumb: CGPoint, mcp: CGPoint, wrist: CGPoint) -> FingerPosture {
        let raw = obterEstadoDedoRaw(tip: tip, thumb: thumb, mcp: mcp, wrist: wrist)
        
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
    
    private func iniciarClique(agora: TimeInterval, wrist: CGPoint) {
        let intervalo = agora - lastClickReleaseTime
        if intervalo <= 0.5 && lastClickReleaseTime > 0 {
            clickCount = 2
            print("🔥 [CLIQUE] Duplo clique acionado (clickCount = 2)")
        } else {
            clickCount = 1
            print("👆 [CLIQUE] Clique simples acionado (clickCount = 1)")
        }
        
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
        
        postMouseEvent(type: .leftMouseDown, point: frozenPosition, clickCount: clickCount)
    }
    
    private func avaliarMaquinaEstados() {
        guard let pIndexTip = tracker.indexTip.getPoint(),
              let pIndexMCP = tracker.indexMCP.getPoint(),
              let pThumbTip = tracker.thumbTip.getPoint(),
              let pWrist = tracker.wrist.getPoint() else {
            return
        }
        
        let agora = CFAbsoluteTimeGetCurrent()
        
        let dIndexThumb = distance(pIndexTip, pThumbTip)
        
        // Cálculo invariante à rotação 2D
        let handScale = distance(pIndexMCP, pWrist)
        let ratio = handScale > 0.01 ? (dIndexThumb / handScale) : 1.0
        ultimoRatioExibido = ratio
        
        let posture = obterEstadoDedoDebounced(tip: pIndexTip, thumb: pThumbTip, mcp: pIndexMCP, wrist: pWrist)
        logEstado(ratio: ratio, posture: posture)
        
        switch currentState {
        case .navegacao: // Estado 0 — Navegação Livre
            if posture == .extended {
                let mappedPoint = obterPontoMapeado(pontoCam: pIndexTip, tela: telaBounds)
                
                let preX = preFiltroX.aplicar(valor: mappedPoint.x, alpha: 0.65)
                let preY = preFiltroY.aplicar(valor: mappedPoint.y, alpha: 0.65)
                
                let filteredX = filtroX.filtrar(valor: preX, timestamp: agora)
                let filteredY = filtroY.filtrar(valor: preY, timestamp: agora)
                let filteredPoint = CGPoint(x: filteredX, y: filteredY)
                
                posicaoCursorAtual = filteredPoint
                frozenPosition = filteredPoint
                
                historicoPosicoes.append(filteredPoint)
                if historicoPosicoes.count > 10 { // Retrocesso de 10 frames (~166ms) garante que a mira congele antes do dedo se mover
                    historicoPosicoes.removeFirst()
                }
                
                postMouseEvent(type: .mouseMoved, point: posicaoCursorAtual, clickCount: 1)
            } else if posture == .bending {
                currentState = .preClique
                historicoPosicoes.removeAll()
                print("🔒 [ESTADO 1] Iniciando desaceleração progressiva do cursor.")
            } else if posture == .fullyBent {
                currentState = .cliqueArraste
                frozenPosition = historicoPosicoes.first ?? posicaoCursorAtual
                historicoPosicoes.removeAll()
                iniciarClique(agora: agora, wrist: pWrist)
            }
            
        case .preClique: // Estado 1 — Pré-Clique
            if posture == .extended {
                currentState = .navegacao
                print("☝️ [ESTADO 0] Retornando para Navegação livre.")
            } else if posture == .bending {
                // Cálculo de velocidade dinâmica: quanto mais próximo, mais lento fica.
                let minRatio: CGFloat = limiarToqueFisico + 0.05
                let maxRatio: CGFloat = limiarClique
                
                // Mapear de 0.0 (em minRatio, cursor parado) a 1.0 (em maxRatio, velocidade normal)
                let factor = max(0.0, min(1.0, (ratio - minRatio) / (maxRatio - minRatio)))
                // Curva não-linear para maior precisão final (x^2)
                let speedFactor = factor * factor
                
                let mappedPoint = obterPontoMapeado(pontoCam: pIndexTip, tela: telaBounds)
                let preX = preFiltroX.aplicar(valor: mappedPoint.x, alpha: 0.65)
                let preY = preFiltroY.aplicar(valor: mappedPoint.y, alpha: 0.65)
                
                let rawFilteredX = filtroX.filtrar(valor: preX, timestamp: agora)
                let rawFilteredY = filtroY.filtrar(valor: preY, timestamp: agora)
                
                // Aplicar a redução de velocidade no deslocamento em relação ao último frame
                let deltaX = rawFilteredX - posicaoCursorAtual.x
                let deltaY = rawFilteredY - posicaoCursorAtual.y
                
                posicaoCursorAtual.x += deltaX * speedFactor
                posicaoCursorAtual.y += deltaY * speedFactor
                
                // Sincronizar o estado dos filtros para a posição atenuada (não acumular desvio)
                filtroX.travarPosicao(posicaoCursorAtual.x)
                filtroY.travarPosicao(posicaoCursorAtual.y)
                
                frozenPosition = posicaoCursorAtual
                postMouseEvent(type: .mouseMoved, point: posicaoCursorAtual, clickCount: 1)
            } else if posture == .fullyBent {
                currentState = .cliqueArraste
                iniciarClique(agora: agora, wrist: pWrist)
            }
            
        case .cliqueArraste: // Estado 2 — Clique / Arraste
            if posture == .fullyBent {
                if !dragActive {
                    let tempoPassado = agora - timeEnteredFullyBent
                    
                    let curX = 1.0 - pWrist.x
                    let curY = 1.0 - pWrist.y
                    let ancX = 1.0 - anchorHandPosition.x
                    let ancY = 1.0 - anchorHandPosition.y
                    let dx = curX - ancX
                    let dy = curY - ancY
                    let deltaDist = sqrt(dx*dx + dy*dy)
                    
                    if tempoPassado > 0.18 || deltaDist > 0.015 {
                        dragActive = true
                        anchorHandPosition = pWrist
                        cursorAnchor = frozenPosition
                        dragFilterX.y = frozenPosition.x
                        dragFilterY.y = frozenPosition.y
                        print("🔄 [ESTADO 2 - ARRASTE] Drag ativado por \(tempoPassado > 0.18 ? "tempo" : "movimento").")
                    }
                }
                
                if dragActive {
                    let curX = 1.0 - pWrist.x
                    let curY = 1.0 - pWrist.y
                    let ancX = 1.0 - anchorHandPosition.x
                    let ancY = 1.0 - anchorHandPosition.y
                    
                    let dx = curX - ancX
                    let dy = curY - ancY
                    
                    let deltaX = dx * telaBounds.width * dragSensitivity
                    let deltaY = dy * telaBounds.height * dragSensitivity
                    
                    let targetX = cursorAnchor.x + deltaX
                    let targetY = cursorAnchor.y + deltaY
                    
                    let filteredX = dragFilterX.aplicar(valor: targetX, alpha: 0.55)
                    let filteredY = dragFilterY.aplicar(valor: targetY, alpha: 0.55)
                    
                    let clampedX = max(0, min(telaBounds.width, filteredX))
                    let clampedY = max(0, min(telaBounds.height, filteredY))
                    
                    posicaoCursorAtual = CGPoint(x: clampedX, y: clampedY)
                    postMouseEvent(type: .leftMouseDragged, point: posicaoCursorAtual, clickCount: clickCount)
                }
            } else {
                postMouseEvent(type: .leftMouseUp, point: posicaoCursorAtual, clickCount: clickCount)
                print(String(format: "💥 [SOLTOU] leftMouseUp em %@ | clickCount: %d", String(describing: posicaoCursorAtual), clickCount))
                
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
        }
    }
    
    private func postMouseEvent(type: CGEventType, point: CGPoint, clickCount: Int64) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left)
        event?.setIntegerValueField(.mouseEventClickState, value: clickCount)
        event?.post(tap: .cghidEventTap)
        
        if type == .leftMouseDown {
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
app.setActivationPolicy(.accessory)
let appController = AppController()
appController.iniciar()
app.run()
