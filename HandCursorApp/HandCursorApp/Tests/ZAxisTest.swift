import Foundation

func distance(_ p1: CGPoint, _ p2: CGPoint) -> CGFloat {
    return hypot(p1.x - p2.x, p1.y - p2.y)
}

func isPointingForward(wrist: CGPoint, indexMCP: CGPoint, pinkyMCP: CGPoint, middleTip: CGPoint) -> Bool {
    let width = distance(indexMCP, pinkyMCP)
    let length = distance(wrist, middleTip)
    return length < width * 1.2
}

// 1. Mão Aberta normal (Para cima)
print("Aberta: ", isPointingForward(wrist: CGPoint(x:0, y:0), 
                                    indexMCP: CGPoint(x:-20, y:50), 
                                    pinkyMCP: CGPoint(x:20, y:40), 
                                    middleTip: CGPoint(x:0, y:120)))

// 2. Mão Apontando pra Câmera (Foreshortened)
print("Apontando: ", isPointingForward(wrist: CGPoint(x:0, y:0), 
                                       indexMCP: CGPoint(x:-30, y:20), 
                                       pinkyMCP: CGPoint(x:30, y:20), 
                                       middleTip: CGPoint(x:0, y:40)))

