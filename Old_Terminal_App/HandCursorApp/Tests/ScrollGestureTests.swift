import Foundation

// --- Funções Auxiliares a serem testadas (Cópia da lógica pretendida) ---

func distance(_ p1: CGPoint, _ p2: CGPoint) -> CGFloat {
    return hypot(p1.x - p2.x, p1.y - p2.y)
}

func isScrollGesture(
    pWrist: CGPoint,
    pIndexTip: CGPoint,
    pMiddleTip: CGPoint,
    pRingTip: CGPoint,
    pPinkyTip: CGPoint,
    pThumbTip: CGPoint,
    handScale: CGFloat
) -> Bool {
    let dIndexWrist = distance(pIndexTip, pWrist)
    let dMiddleWrist = distance(pMiddleTip, pWrist)
    let dRingWrist = distance(pRingTip, pWrist)
    let dPinkyWrist = distance(pPinkyTip, pWrist)
    let dIndexMiddle = distance(pIndexTip, pMiddleTip)
    let dThumbIndex = distance(pThumbTip, pIndexTip)
    
    // Indicador e médio estendidos
    let fingersExtended = dIndexWrist > handScale * 1.0 && dMiddleWrist > handScale * 1.0
    // Anelar e mindinho dobrados
    let fingersFolded = dRingWrist < handScale * 0.9 && dPinkyWrist < handScale * 0.9
    // Indicador e médio próximos um do outro
    let fingersTogether = dIndexMiddle < handScale * 0.4
    // Polegar afastado para não confundir com pinça (opcional mas recomendado)
    let thumbAway = dThumbIndex > handScale * 0.4
    
    return fingersExtended && fingersFolded && fingersTogether && thumbAway
}


// --- Testes Unitários ---

var testsPassed = 0
var testsFailed = 0

func assertTest(name: String, result: Bool, expected: Bool) {
    if result == expected {
        print("✅ [PASS] \(name)")
        testsPassed += 1
    } else {
        print("❌ [FAIL] \(name) - Expected \(expected), got \(result)")
        testsFailed += 1
    }
}

let scale: CGFloat = 100.0 // Tamanho base da palma simulada
let wrist = CGPoint(x: 0, y: 0)

// 1. Cenário: Mão totalmente aberta (Navegação Normal)
// Todos os dedos estendidos e afastados
let open_index = CGPoint(x: -30, y: 150)
let open_middle = CGPoint(x: 0, y: 160)
let open_ring = CGPoint(x: 30, y: 140)
let open_pinky = CGPoint(x: 60, y: 110)
let open_thumb = CGPoint(x: -80, y: 80)

assertTest(name: "Mão Aberta (Navegação)", result: isScrollGesture(
    pWrist: wrist,
    pIndexTip: open_index, pMiddleTip: open_middle, pRingTip: open_ring, pPinkyTip: open_pinky, pThumbTip: open_thumb,
    handScale: scale
), expected: false)

// 2. Cenário: Mão em Pinça (Arraste / Clique)
// Indicador e polegar juntos. Médio, anelar e mindinho abertos ou relaxados.
let pinch_index = CGPoint(x: -40, y: 80)
let pinch_thumb = CGPoint(x: -40, y: 80) // Juntos
let pinch_middle = CGPoint(x: 0, y: 160)
let pinch_ring = CGPoint(x: 30, y: 140)
let pinch_pinky = CGPoint(x: 60, y: 110)

assertTest(name: "Gesto de Pinça", result: isScrollGesture(
    pWrist: wrist,
    pIndexTip: pinch_index, pMiddleTip: pinch_middle, pRingTip: pinch_ring, pPinkyTip: pinch_pinky, pThumbTip: pinch_thumb,
    handScale: scale
), expected: false)

// 3. Cenário: Mão Fechada (Punho)
// Todos os dedos dobrados perto do pulso
let fist_index = CGPoint(x: -20, y: 40)
let fist_middle = CGPoint(x: 0, y: 45)
let fist_ring = CGPoint(x: 20, y: 40)
let fist_pinky = CGPoint(x: 40, y: 30)
let fist_thumb = CGPoint(x: -40, y: 30)

assertTest(name: "Punho Fechado", result: isScrollGesture(
    pWrist: wrist,
    pIndexTip: fist_index, pMiddleTip: fist_middle, pRingTip: fist_ring, pPinkyTip: fist_pinky, pThumbTip: fist_thumb,
    handScale: scale
), expected: false)

// 4. Cenário: Sinal da Paz (V)
// Indicador e médio estendidos, porém AFASTADOS. Resto dobrado.
let v_index = CGPoint(x: -50, y: 150)
let v_middle = CGPoint(x: 50, y: 150) // Distância = 100 (scale 1.0)
let v_ring = CGPoint(x: 20, y: 40)
let v_pinky = CGPoint(x: 40, y: 30)
let v_thumb = CGPoint(x: -50, y: 40)

assertTest(name: "Sinal de V (Afastados)", result: isScrollGesture(
    pWrist: wrist,
    pIndexTip: v_index, pMiddleTip: v_middle, pRingTip: v_ring, pPinkyTip: v_pinky, pThumbTip: v_thumb,
    handScale: scale
), expected: false)

// 5. Cenário: Gesto de Scroll (Perfeito)
// Indicador e médio estendidos e JUNTOS. Anelar e mindinho dobrados. Polegar afastado.
let scroll_index = CGPoint(x: -10, y: 150)
let scroll_middle = CGPoint(x: 10, y: 150) // Distância = 20 (scale 0.2)
let scroll_ring = CGPoint(x: 20, y: 40)
let scroll_pinky = CGPoint(x: 40, y: 30)
let scroll_thumb = CGPoint(x: -80, y: 60)

assertTest(name: "Gesto de Scroll Perfeito", result: isScrollGesture(
    pWrist: wrist,
    pIndexTip: scroll_index, pMiddleTip: scroll_middle, pRingTip: scroll_ring, pPinkyTip: scroll_pinky, pThumbTip: scroll_thumb,
    handScale: scale
), expected: true)

print("\nResultados: \(testsPassed) Passaram, \(testsFailed) Falharam.")
if testsFailed > 0 { exit(1) } else { exit(0) }
