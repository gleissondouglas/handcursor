import SwiftUI
import Combine
import AVFoundation // Para a Câmera
import ApplicationServices // Para a Acessibilidade (Mouse)

class PermissionManager: ObservableObject {
    
    // Propriedades que avisam a tela sobre mudanças de estado
    @Published var isCameraGranted: Bool = false
    @Published var isAccessibilityGranted: Bool = false
    
    // Inicializador que verifica o estado atual ao carregar
    init() {
        checkCameraAuthorizationStatus()
        checkAccessibilityAuthorizationStatus()
    }
    
    // Função para verificar o status da Câmera
    func checkCameraAuthorizationStatus() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        DispatchQueue.main.async {
            self.isCameraGranted = (status == .authorized)
        }
    }
    
    // Função para verificar o status de Acessibilidade
    func checkAccessibilityAuthorizationStatus() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString: false]
        let isTrusted = AXIsProcessTrustedWithOptions(options)
        DispatchQueue.main.async {
            self.isAccessibilityGranted = isTrusted
        }
    }
    
    // Função para SOLICITAR acesso à Câmera
    func requestCameraAccess() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            // Volta para a Thread Principal para atualizar a interface
            DispatchQueue.main.async {
                self.isCameraGranted = granted
            }
        }
    }
    
    // Função para SOLICITAR acesso à Acessibilidade (Mouse)
    func requestAccessibilityAccess() {
        // Opções para forçar o pop-up nativo
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString: true]
        
        // Esta função tenta verificar a permissão e aciona o pedido se necessário
        let isTrusted = AXIsProcessTrustedWithOptions(options)
        
        // Se já estiver tudo certo, atualiza. Se não, o pop-up nativo deve aparecer.
        DispatchQueue.main.async {
            self.isAccessibilityGranted = isTrusted
        }
    }
}
