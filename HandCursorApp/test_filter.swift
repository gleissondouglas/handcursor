import Foundation

// Simulação simplificada do cálculo da "Desaceleração Gravitacional" para testes
func testDynamicCutoff() {
    print("Iniciando Teste: Desaceleração Gravitacional do Cursor")
    print("======================================================")
    
    let maxRatio: Double = 0.80 // Mão aberta (movimento livre)
    let minRatio: Double = 0.40 // Quase fechando (mira travada)
    
    // Simulando o polegar e indicador se aproximando (Ratio diminuindo de 1.0 para 0.2)
    let simulateRatios: [Double] = [1.0, 0.9, 0.8, 0.7, 0.6, 0.5, 0.4, 0.3, 0.2]
    
    for ratio in simulateRatios {
        let clampedRatio = max(minRatio, min(maxRatio, ratio))
        let normalized = (clampedRatio - minRatio) / (maxRatio - minRatio)
        
        let dynamicCutoff = 0.001 + (0.50 - 0.001) * (normalized * normalized)
        
        // Formatação do log
        let status = ratio > 0.8 ? "LIVRE" : (ratio <= 0.4 ? "TRAVADO" : "DESACELERANDO")
        print(String(format: "Distância: %.2f | Cutoff: %.4f | Status: %@", ratio, dynamicCutoff, status))
    }
}

testDynamicCutoff()
