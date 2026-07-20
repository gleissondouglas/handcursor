import SwiftUI
import AppKit // A biblioteca nativa original do Mac

@main
struct HandCursorApp: App {
    // Conecta o nosso controlador principal
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        // Cena vazia apenas para manter o app vivo nos bastidores
        Settings { EmptyView() }
    }
}

// ==========================================
// O CÉREBRO QUE CONTROLA A BARRA DE MENUS
// ==========================================
class AppDelegate: NSObject, NSApplicationDelegate {
    
    var statusItem: NSStatusItem! // O ícone lá em cima
    var tutorialWindow: NSWindow? // A nossa janela do tutorial
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        
        // 1. Força o aplicativo a rodar na Barra de Menus (Bypassa o bug do Info.plist)
        NSApp.setActivationPolicy(.accessory)
        
        // 2. Cria o ícone fixo e indestrutível na barra
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "hand.raised.fill", accessibilityDescription: "HandCursor")
        }
        
        // 3. Constrói o Menu à prova de falhas
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Ligar Câmera", action: #selector(ligarCamera), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Refazer Tutorial", action: #selector(mostrarTutorial), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Encerrar", action: #selector(encerrar), keyEquivalent: "q"))
        
        statusItem.menu = menu
        
        // 4. Verifica se precisa abrir o tutorial logo de cara
        if !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
            mostrarTutorial()
        }
    }
    
    // ==========================================
    // AÇÕES DOS BOTÕES
    // ==========================================
    
    @objc func mostrarTutorial() {
        // Zera a memória
        UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
        
        // Se a janela não existir, nós a criamos do zero
        if tutorialWindow == nil {
            let contentView = ContentView()
            tutorialWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 450, height: 500),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered, defer: false
            )
            tutorialWindow?.isReleasedWhenClosed = false
            tutorialWindow?.center()
            tutorialWindow?.titlebarAppearsTransparent = true
            tutorialWindow?.titleVisibility = .hidden
            // Coloca o nosso design do SwiftUI dentro da janela de ferro do AppKit
            tutorialWindow?.contentView = NSHostingView(rootView: contentView)
        }
        
        // FORÇA a janela a vir para frente e acordar o app!
        tutorialWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    var cursorController: AppController?
    
    @objc func ligarCamera() {
        if cursorController == nil {
            cursorController = AppController()
            cursorController?.iniciar()
            print("🟢 Câmera e motor de rastreamento ativados com sucesso!")
        } else {
            print("A câmera já está rodando.")
        }
    }
    
    @objc func encerrar() {
        NSApplication.shared.terminate(nil)
    }
}
