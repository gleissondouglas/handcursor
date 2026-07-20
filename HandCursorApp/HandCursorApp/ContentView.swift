// ==========================================
// TELA PRINCIPAL (GERENCIADORA DO CARROSSEL)
// ==========================================
import SwiftUI
struct ContentView: View {
    @State private var currentPage = 0
    
    // 🧠 Trazemos a antena da memória pra cá também
    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding: Bool = false
    
    var body: some View {
        ZStack {
            Color.clear.background(.ultraThinMaterial)
            
            VStack {
                if currentPage == 0 {
                    WelcomeView(currentPage: $currentPage).transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                } else if currentPage == 1 {
                    BasicsTutorialView(currentPage: $currentPage).transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                } else if currentPage == 2 {
                    ScrollTutorialView(currentPage: $currentPage).transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                } else if currentPage == 3 {
                    DragTutorialView(currentPage: $currentPage).transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                } else if currentPage == 4 {
                    PermissionsView(currentPage: $currentPage).transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                }
            }
            .animation(.spring(response: 0.6, dampingFraction: 0.9), value: currentPage)
        }
        .frame(width: 450, height: 500)
        
        // 👇 A MÁGICA DE TELETRANSPORTE ACONTECE AQUI 👇
        .onChange(of: hasCompletedOnboarding) { oldValue, newValue in
            if newValue == true {
                // Manda o Mac fechar esta janela imediatamente
                NSApplication.shared.windows.forEach { $0.close() }
            }
        }
        .onAppear {
            // Se o app ligar e o tutorial já tiver sido feito, fecha a janela antes de alguém ver
            if hasCompletedOnboarding == true {
                NSApplication.shared.windows.forEach { $0.close() }
            }
        }
    }
}

// ==========================================
// PÁGINA 0: BOAS-VINDAS
// ==========================================
struct WelcomeView: View {
    @Binding var currentPage: Int
    var body: some View {
        VStack(spacing: 30) {
            Image(systemName: "hand.point.up.left.fill")
                .font(.system(size: 75))
                .foregroundStyle(LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
                .shadow(color: .blue.opacity(0.4), radius: 15, x: 0, y: 8)
            
            VStack(spacing: 6) {
                Text("HandCursor").font(.system(size: 32, weight: .bold, design: .rounded))
                Text("Seu Mac, controlado pelas suas mãos.").font(.system(size: 15, weight: .medium, design: .rounded)).foregroundColor(.secondary)
            }
            
            Button(action: { currentPage = 1 }) {
                Text("Começar").font(.system(size: 15, weight: .bold, design: .rounded)).foregroundColor(.white).frame(width: 200, height: 44).background(LinearGradient(colors: [.blue, .blue.opacity(0.8)], startPoint: .top, endPoint: .bottom)).clipShape(Capsule()).shadow(color: .blue.opacity(0.3), radius: 8, x: 0, y: 4)
            }.buttonStyle(.plain)
        }.padding(50)
    }
}

// ==========================================
// PÁGINA 1: TUTORIAL DE CLIQUE (PINÇA)
// ==========================================
struct BasicsTutorialView: View {
    @Binding var currentPage: Int
    @State private var handOffset = CGSize(width: 60, height: 60)
    @State private var isClicking = false
    @State private var folderScale = 1.0
    
    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text("O Clique").font(.system(size: 24, weight: .bold, design: .rounded))
                Text("Mova a mão para guiar o cursor.\nJunte o indicador e o polegar (pinça) para clicar.").font(.system(size: 14, weight: .medium, design: .rounded)).foregroundColor(.secondary).multilineTextAlignment(.center)
            }
            
            ZStack {
                RoundedRectangle(cornerRadius: 16).fill(Color.black.opacity(0.05)).frame(width: 260, height: 160).overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.gray.opacity(0.2), lineWidth: 1))
                
                VStack(spacing: 4) {
                    Image(systemName: "folder.fill").font(.system(size: 36)).foregroundColor(isClicking ? .blue.opacity(0.8) : .blue)
                    Text("Projetos").font(.system(size: 10, weight: .medium)).foregroundColor(.primary.opacity(0.8))
                }.scaleEffect(folderScale).offset(x: -40, y: -20)
                
                ZStack {
                    Image(systemName: isClicking ? "hand.tap.fill" : "hand.point.up.left.fill").font(.system(size: 40)).foregroundColor(.primary).shadow(color: .black.opacity(isClicking ? 0.1 : 0.3), radius: isClicking ? 2 : 5, x: 0, y: isClicking ? 2 : 5)
                    Circle().stroke(Color.gray.opacity(isClicking ? 0.0 : 0.6), lineWidth: 2).frame(width: isClicking ? 4 : 35, height: isClicking ? 4 : 35).offset(x: -18, y: -22)
                }.scaleEffect(isClicking ? 0.9 : 1.0).offset(handOffset)
            }.padding(.vertical, 10)
            
            HStack(spacing: 16) {
                Button(action: { currentPage = 0 }) { Text("Voltar").font(.system(size: 14, weight: .semibold)).foregroundColor(.secondary).frame(width: 100, height: 36).background(Color.gray.opacity(0.1)).clipShape(Capsule()) }.buttonStyle(.plain)
                Button(action: { currentPage = 2 }) { Text("Próximo").font(.system(size: 14, weight: .bold)).foregroundColor(.white).frame(width: 100, height: 36).background(Color.blue).clipShape(Capsule()) }.buttonStyle(.plain)
            }
        }.padding(40).onAppear { iniciarAnimacaoEmLoop() }
    }
    
    func iniciarAnimacaoEmLoop() {
        withAnimation(.easeInOut(duration: 1.0)) { handOffset = CGSize(width: -20, height: -5) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { isClicking = true; folderScale = 0.85 } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { isClicking = false; folderScale = 1.0 } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { withAnimation(.easeInOut(duration: 1.0)) { handOffset = CGSize(width: 60, height: 60) } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { iniciarAnimacaoEmLoop() }
    }
}

// ==========================================
// PÁGINA 2: TUTORIAL DE ROLAGEM (SCROLL 3D)
// ==========================================
struct ScrollTutorialView: View {
    @Binding var currentPage: Int
    @State private var handScale = 1.0
    @State private var handPitch = 0.0
    @State private var isLocked = false
    @State private var contentOffsetY = 0.0
    
    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text("Navegação").font(.system(size: 24, weight: .bold, design: .rounded))
                Text("Mostre a palma da mão para a tela,\naguarde 1 segundo e mova para rolar.").font(.system(size: 14, weight: .medium, design: .rounded)).foregroundColor(.secondary).multilineTextAlignment(.center)
            }
            
            ZStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 16).fill(Color.black.opacity(0.05))
                    VStack(spacing: 12) { ForEach(0..<6, id: \.self) { _ in RoundedRectangle(cornerRadius: 8).fill(Color.blue.opacity(0.2)).frame(width: 200, height: 35) } }.offset(y: contentOffsetY)
                }.frame(width: 260, height: 160).clipShape(RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.gray.opacity(0.2), lineWidth: 1))
                
                Image(systemName: "hand.raised.fill").font(.system(size: 40)).foregroundColor(isLocked ? .blue : .primary).scaleEffect(isLocked ? handScale * 1.05 : handScale).rotation3DEffect(.degrees(handPitch), axis: (x: 1, y: 0, z: 0)).shadow(color: isLocked ? .blue.opacity(0.4) : .black.opacity(0.2), radius: handScale * 5, x: 0, y: handScale * 5).offset(x: 60, y: 15)
            }.padding(.vertical, 10)
            
            HStack(spacing: 16) {
                Button(action: { currentPage = 1 }) { Text("Voltar").font(.system(size: 14, weight: .semibold)).foregroundColor(.secondary).frame(width: 100, height: 36).background(Color.gray.opacity(0.1)).clipShape(Capsule()) }.buttonStyle(.plain)
                Button(action: { currentPage = 3 }) { Text("Próximo").font(.system(size: 14, weight: .bold)).foregroundColor(.white).frame(width: 100, height: 36).background(Color.blue).clipShape(Capsule()) }.buttonStyle(.plain)
            }
        }.padding(40).onAppear { iniciarAnimacaoScroll() }
    }
    
    func iniciarAnimacaoScroll() {
        withAnimation(.easeInOut(duration: 0.5)) { handScale = 1.0; handPitch = 0.0; isLocked = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { isLocked = true } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { withAnimation(.easeInOut(duration: 1.0)) { handScale = 0.75; handPitch = 30; contentOffsetY = -50 } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { withAnimation(.easeInOut(duration: 0.5)) { handScale = 1.0; handPitch = 0.0; isLocked = false } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { isLocked = true } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) { withAnimation(.easeInOut(duration: 1.0)) { handScale = 1.15; handPitch = -15; contentOffsetY = 0 } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.5) { iniciarAnimacaoScroll() }
    }
}

// ==========================================
// PÁGINA 3: TUTORIAL DE ARRASTAR (NOVA)
// ==========================================
struct DragTutorialView: View {
    @Binding var currentPage: Int
    
    // Coreografia da Mão e da Janela Virtual
    @State private var handOffset = CGSize(width: 60, height: 60)
    @State private var windowOffset = CGSize(width: -40, height: 0)
    @State private var isGrabbing = false
    
    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text("Segurar e Arrastar")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text("Faça a pinça sobre um item, mantenha\nos dedos juntos e mova a mão.")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            // Monitor Virtual
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.black.opacity(0.05))
                    .frame(width: 260, height: 160)
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.gray.opacity(0.2), lineWidth: 1))
                
                // Janela Virtual que será arrastada
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.blue.opacity(0.2))
                    .frame(width: 80, height: 60)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isGrabbing ? Color.blue : Color.gray.opacity(0.3), lineWidth: isGrabbing ? 2 : 1)
                    )
                    .scaleEffect(isGrabbing ? 0.95 : 1.0)
                    .offset(windowOffset)
                
                // Cursor e Anel de Pinça (Halo)
                ZStack {
                    Image(systemName: isGrabbing ? "hand.tap.fill" : "hand.point.up.left.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.primary)
                        .shadow(color: .black.opacity(isGrabbing ? 0.1 : 0.3), radius: isGrabbing ? 2 : 5, x: 0, y: isGrabbing ? 2 : 5)
                    
                    Circle()
                        .stroke(Color.gray.opacity(isGrabbing ? 0.0 : 0.6), lineWidth: 2)
                        .frame(width: isGrabbing ? 4 : 35, height: isGrabbing ? 4 : 35)
                        .offset(x: -18, y: -22)
                }
                .scaleEffect(isGrabbing ? 0.9 : 1.0)
                .offset(handOffset)
            }
            .padding(.vertical, 10)
            
            HStack(spacing: 16) {
                Button(action: { currentPage = 2 }) { Text("Voltar").font(.system(size: 14, weight: .semibold)).foregroundColor(.secondary).frame(width: 100, height: 36).background(Color.gray.opacity(0.1)).clipShape(Capsule()) }.buttonStyle(.plain)
                Button(action: { currentPage = 4 }) { Text("Próximo").font(.system(size: 14, weight: .bold)).foregroundColor(.white).frame(width: 100, height: 36).background(Color.blue).clipShape(Capsule()) }.buttonStyle(.plain)
            }
        }.padding(40).onAppear { iniciarAnimacaoArrastar() }
    }
    
    func iniciarAnimacaoArrastar() {
        // 1. Mão vai até a janela
        withAnimation(.easeInOut(duration: 1.0)) { handOffset = CGSize(width: -20, height: 15) }
        
        // 2. Faz a pinça e segura
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { isGrabbing = true }
        }
        
        // 3. Arrasta a janela para a direita
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeInOut(duration: 1.0)) {
                handOffset = CGSize(width: 60, height: 15)
                windowOffset = CGSize(width: 40, height: 0)
            }
        }
        
        // 4. Solta a pinça
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { isGrabbing = false }
        }
        
        // 5. Mão e janela voltam ao início para recomeçar
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            withAnimation(.easeInOut(duration: 1.0)) {
                handOffset = CGSize(width: 60, height: 60)
                windowOffset = CGSize(width: -40, height: 0)
            }
        }
        
        // Loop
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) { iniciarAnimacaoArrastar() }
    }
}

// ==========================================
// PÁGINA 4: TELA DE PERMISSÕES (SOFT PROMPT)
// ==========================================
struct PermissionsView: View {
    @Binding var currentPage: Int
    
    // Conectando com a mesma memória lá do arquivo principal!
    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding: Bool = false
    
    @StateObject private var permissionManager = PermissionManager()
    
    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text("Quase lá!").font(.system(size: 24, weight: .bold, design: .rounded))
                Text("Para que a mágica aconteça, precisamos\nconectar o seu Mac aos seus movimentos.").font(.system(size: 14, weight: .medium, design: .rounded)).foregroundColor(.secondary).multilineTextAlignment(.center)
            }
            
            VStack(spacing: 12) {
                PermissionCard(icon: "camera.fill", title: "Acesso à Câmera", description: "Usado apenas localmente para rastrear suas mãos. Nenhuma imagem sai do seu Mac.", isGranted: $permissionManager.isCameraGranted, action: { permissionManager.requestCameraAccess() })
                
                PermissionCard(icon: "cursorarrow", title: "Controle do Cursor", description: "Permite que o aplicativo mova o mouse e clique na tela por você.", isGranted: $permissionManager.isAccessibilityGranted, action: { permissionManager.requestAccessibilityAccess() })
            }.padding(.top, 10)
            
            Spacer()
            
            Button(action: {
                // A MÁGICA DO TELETRANSPORTE ACONTECE AQUI!
                withAnimation {
                    hasCompletedOnboarding = true
                }
            }) {
                Text("Concluir e Iniciar")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(width: 250, height: 44)
                    .background((permissionManager.isCameraGranted && permissionManager.isAccessibilityGranted) ? LinearGradient(colors: [.blue, .blue.opacity(0.8)], startPoint: .top, endPoint: .bottom) : LinearGradient(colors: [.gray.opacity(0.3), .gray.opacity(0.2)], startPoint: .top, endPoint: .bottom))
                    .clipShape(Capsule())
                    .shadow(color: (permissionManager.isCameraGranted && permissionManager.isAccessibilityGranted) ? .blue.opacity(0.3) : .clear, radius: 8, x: 0, y: 4)
            }
            .buttonStyle(.plain)
            .disabled(!(permissionManager.isCameraGranted && permissionManager.isAccessibilityGranted))
        }.padding(40)
    }
}

// ==========================================
// COMPONENTE: CARD DE PERMISSÃO REUTILIZÁVEL
// ==========================================
struct PermissionCard: View {
    var icon: String
    var title: String
    var description: String
    @Binding var isGranted: Bool
    var action: () -> Void // 👈 Adicionamos a capacidade de receber uma ação externa
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon).font(.system(size: 24)).foregroundColor(isGranted ? .green : .blue).frame(width: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 14, weight: .bold, design: .rounded))
                Text(description).font(.system(size: 11, weight: .medium, design: .rounded)).foregroundColor(.secondary).lineLimit(2)
            }
            
            Spacer()
            
            Button(action: {
                action() // 👈 Quando clicado, executa a ação real do Mac!
            }) {
                if isGranted {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 22)).foregroundColor(.green)
                } else {
                    Text("Permitir").font(.system(size: 12, weight: .bold)).foregroundColor(.white).padding(.horizontal, 12).padding(.vertical, 6).background(Color.blue).clipShape(Capsule())
                }
            }
            .buttonStyle(.plain)
            .disabled(isGranted)
        }
        .padding(16)
        .background(Color.black.opacity(0.04))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(isGranted ? Color.green.opacity(0.5) : Color.gray.opacity(0.2), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    ContentView()
}
