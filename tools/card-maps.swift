// Bakes the welcome aces into material maps: R,G = surface normal, B = gold coverage.
// Everything is carved from height fields, so the shader on the phone can light it live.
import Foundation
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

let OUT = CommandLine.arguments[1]
let SS = 3                       // work at twice the final size, then average down
let FW = 720, FH = 1008          // final map size (same 5:7 shape as the card)
let W = FW * SS, H = FH * SS
let U = CGFloat(W) / 100         // 1 unit = 1% of card width

func suitPath(_ name: String, cx: CGFloat, cy: CGFloat, size: CGFloat) -> CGPath {
  let p = CGMutablePath()
  func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
  switch name {
  case "spade":
    p.move(to: P(50, 2))
    p.addCurve(to: P(95, 60), control1: P(61, 22), control2: P(95, 38))
    p.addCurve(to: P(72, 83), control1: P(95, 74), control2: P(84, 83))
    p.addCurve(to: P(54, 73), control1: P(64, 83), control2: P(58, 79))
    p.addCurve(to: P(70, 98), control1: P(55, 83), control2: P(60, 93))
    p.addLine(to: P(30, 98))
    p.addCurve(to: P(46, 73), control1: P(40, 93), control2: P(45, 83))
    p.addCurve(to: P(28, 83), control1: P(42, 79), control2: P(36, 83))
    p.addCurve(to: P(5, 60), control1: P(16, 83), control2: P(5, 74))
    p.addCurve(to: P(50, 2), control1: P(5, 38), control2: P(39, 22))
  case "heart":
    p.move(to: P(50, 96))
    p.addCurve(to: P(4, 31), control1: P(46, 89), control2: P(4, 60))
    p.addCurve(to: P(30, 5), control1: P(4, 15), control2: P(16, 5))
    p.addCurve(to: P(50, 19), control1: P(39, 5), control2: P(46, 10))
    p.addCurve(to: P(70, 5), control1: P(54, 10), control2: P(61, 5))
    p.addCurve(to: P(96, 31), control1: P(84, 5), control2: P(96, 15))
    p.addCurve(to: P(50, 96), control1: P(96, 60), control2: P(54, 89))
  case "diamond":
    p.move(to: P(50, 2))
    p.addQuadCurve(to: P(88, 50), control: P(64, 31))
    p.addQuadCurve(to: P(50, 98), control: P(64, 69))
    p.addQuadCurve(to: P(12, 50), control: P(36, 69))
    p.addQuadCurve(to: P(50, 2), control: P(36, 31))
  default: // club
    p.addEllipse(in: CGRect(x: 28, y: 3, width: 44, height: 44))
    p.addEllipse(in: CGRect(x: 4, y: 37, width: 44, height: 44))
    p.addEllipse(in: CGRect(x: 52, y: 37, width: 44, height: 44))
    p.addRect(CGRect(x: 40, y: 34, width: 20, height: 24))
    p.move(to: P(46, 50))
    p.addLine(to: P(54, 50))
    p.addCurve(to: P(69, 98), control1: P(55, 72), control2: P(60, 90))
    p.addLine(to: P(31, 98))
    p.addCurve(to: P(46, 50), control1: P(40, 90), control2: P(45, 72))
  }
  var t = CGAffineTransform(translationX: cx - size / 2, y: cy - size / 2).scaledBy(x: size / 100, y: size / 100)
  return p.copy(using: &t)!
}

// y runs downward everywhere, like the design notes
func newCtx() -> (CGContext, UnsafeMutablePointer<UInt8>) {
  let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: W * H)
  buf.initialize(repeating: 0, count: W * H)
  let c = CGContext(data: buf, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W,
                    space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
  c.translateBy(x: 0, y: CGFloat(H)); c.scaleBy(x: 1, y: -1)
  c.setFillColor(gray: 1, alpha: 1); c.setStrokeColor(gray: 1, alpha: 1)
  return (c, buf)
}
func mask(_ draw: (CGContext) -> Void) -> [Float] {
  let (c, buf) = newCtx(); draw(c)
  var out = [Float](repeating: 0, count: W * H)
  for i in 0..<(W * H) { out[i] = Float(buf[i]) / 255 }
  buf.deallocate()
  return out
}

// Exact distance to the nearest outside pixel (Felzenszwalb), in pixels
func dt1d(_ f: [Float]) -> [Float] {
  let n = f.count, INF: Float = 1e12
  var v = [Int](repeating: 0, count: n), z = [Float](repeating: 0, count: n + 1), d = [Float](repeating: 0, count: n)
  var k = 0; z[0] = -INF; z[1] = INF
  for q in 1..<n {
    var s = ((f[q] + Float(q * q)) - (f[v[k]] + Float(v[k] * v[k]))) / Float(2 * (q - v[k]))
    while s <= z[k] {
      k -= 1
      s = ((f[q] + Float(q * q)) - (f[v[k]] + Float(v[k] * v[k]))) / Float(2 * (q - v[k]))
    }
    k += 1; v[k] = q; z[k] = s; z[k + 1] = INF
  }
  k = 0
  for q in 0..<n {
    while z[k + 1] < Float(q) { k += 1 }
    d[q] = Float((q - v[k]) * (q - v[k])) + f[v[k]]
  }
  return d
}
func edt(_ m: [Float]) -> [Float] {
  var g = [Float](repeating: 0, count: W * H)
  for i in 0..<(W * H) { g[i] = m[i] > 0.5 ? 1e12 : 0 }
  g.withUnsafeMutableBufferPointer { gp in
    let base = gp.baseAddress!
    DispatchQueue.concurrentPerform(iterations: W) { x in
      var col = [Float](repeating: 0, count: H)
      for y in 0..<H { col[y] = base[y * W + x] }
      let r = dt1d(col)
      for y in 0..<H { base[y * W + x] = r[y] }
    }
    DispatchQueue.concurrentPerform(iterations: H) { y in
      var row = [Float](repeating: 0, count: W)
      for x in 0..<W { row[x] = base[y * W + x] }
      let r = dt1d(row)
      for x in 0..<W { base[y * W + x] = r[x] }
    }
  }
  return g.map { $0 >= 1e11 ? 0 : $0.squareRoot() }
}

// Points along an outline with their running length, for patterns that follow the edge
func outline(_ path: CGPath, step: CGFloat) -> [(CGFloat, CGFloat, CGFloat)] {
  var pts: [(CGFloat, CGFloat, CGFloat)] = []
  var cur = CGPoint.zero, start = CGPoint.zero, len: CGFloat = 0
  func line(_ a: CGPoint, _ b: CGPoint) {
    let d = hypot(b.x - a.x, b.y - a.y); let n = max(1, Int(d / step))
    for i in 0..<n { let t = CGFloat(i) / CGFloat(n); pts.append((a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, len + d * t)) }
    len += d
  }
  path.applyWithBlock { e in
    let el = e.pointee, q = el.points
    switch el.type {
    case .moveToPoint: cur = q[0]; start = q[0]
    case .addLineToPoint: line(cur, q[0]); cur = q[0]
    case .addQuadCurveToPoint:
      var a = cur
      for i in 1...48 { let t = CGFloat(i) / 48, u = 1 - t
        let b = CGPoint(x: u*u*cur.x + 2*u*t*q[0].x + t*t*q[1].x, y: u*u*cur.y + 2*u*t*q[0].y + t*t*q[1].y); line(a, b); a = b }
      cur = q[1]
    case .addCurveToPoint:
      var a = cur
      for i in 1...64 { let t = CGFloat(i) / 64, u = 1 - t
        let b = CGPoint(x: u*u*u*cur.x + 3*u*u*t*q[0].x + 3*u*t*t*q[1].x + t*t*t*q[2].x,
                        y: u*u*u*cur.y + 3*u*u*t*q[0].y + 3*u*t*t*q[1].y + t*t*t*q[2].y); line(a, b); a = b }
      cur = q[2]
    case .closeSubpath: line(cur, start); cur = start
    @unknown default: break
    }
  }
  return pts
}

func smooth(_ e0: Float, _ e1: Float, _ x: Float) -> Float { let t = min(max((x - e0) / (e1 - e0), 0), 1); return t * t * (3 - 2 * t) }

func blur(_ a: inout [Float], r: Int) {
  guard r > 0 else { return }
  for _ in 0..<2 {
    a.withUnsafeMutableBufferPointer { p in
      let b = p.baseAddress!
      DispatchQueue.concurrentPerform(iterations: H) { y in
        var row = [Float](repeating: 0, count: W); var s: Float = 0
        for x in -r...r { s += b[y * W + min(max(x, 0), W - 1)] }
        for x in 0..<W { row[x] = s / Float(2 * r + 1); s += b[y * W + min(x + r + 1, W - 1)] - b[y * W + max(x - r, 0)] }
        for x in 0..<W { b[y * W + x] = row[x] }
      }
      DispatchQueue.concurrentPerform(iterations: W) { x in
        var col = [Float](repeating: 0, count: H); var s: Float = 0
        for y in -r...r { s += b[min(max(y, 0), H - 1) * W + x] }
        for y in 0..<H { col[y] = s / Float(2 * r + 1); s += b[min(y + r + 1, H - 1) * W + x] - b[max(y - r, 0) * W + x] }
        for y in 0..<H { b[y * W + x] = col[y] }
      }
    }
  }
}

func text(_ c: CGContext, _ s: String, font: String, size: CGFloat, x: CGFloat, y: CGFloat, tracking: CGFloat = 0) {
  let f = CTFontCreateWithName(font as CFString, size, nil)
  let attr: [NSAttributedString.Key: Any] = [.init(kCTFontAttributeName as String): f, .init(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 1), .init(kCTKernAttributeName as String): tracking]
  let line = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: attr))
  let w = CTLineGetTypographicBounds(line, nil, nil, nil)
  c.saveGState(); c.translateBy(x: x - CGFloat(w) / 2 + tracking / 2, y: y); c.scaleBy(x: 1, y: -1)
  c.textPosition = .zero; CTLineDraw(line, c); c.restoreGState()
}
func roundRect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> CGPath {
  CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerWidth: r, cornerHeight: r, transform: nil)
}

// A raised foil layer: bevelled edge, flat top
func foil(_ m: [Float], bevel: Float, height: Float, into h: inout [Float], cov: inout [Float]) {
  let d = edt(m)
  for i in 0..<(W * H) where m[i] > 0 {
    let p = min(d[i] / bevel, 1)
    h[i] = max(h[i], height * Float((1 - pow(Double(1 - p), 2.4))))
    cov[i] = max(cov[i], m[i])
  }
}

// The big centre emblem: rolled rim, twisted rope, an engraved band, a second
// rim, and a raised leaf motif in a sunken field
func emblem(_ name: String, cx: CGFloat, cy: CGFloat, size: CGFloat, into h: inout [Float], cov: inout [Float]) {
  let path = suitPath(name, cx: cx, cy: cy, size: size)
  let mk = mask { $0.addPath(path); $0.fillPath(using: .winding) }
  let d = edt(mk)
  let pts = outline(path, step: 3)
  let u = Float(size) / 72
  let rim1 = 1.15 * u, rope0 = 1.35 * u, rope1 = 3.1 * u, band1 = 5.5 * u, rim2 = 6.5 * u

  // nearest outline point, for the patterns that run along the edge
  var along = [Float](repeating: 0, count: W * H)
  let total = Float(pts.last!.2)
  along.withUnsafeMutableBufferPointer { ap in
    let a = ap.baseAddress!
    DispatchQueue.concurrentPerform(iterations: H) { y in
      for x in 0..<W {
        let i = y * W + x
        if d[i] <= 0 || d[i] > band1 + 2 { continue }
        var best = CGFloat.greatestFiniteMagnitude, s: CGFloat = 0
        var k = 0
        while k < pts.count {
          let dx = pts[k].0 - CGFloat(x), dy = pts[k].1 - CGFloat(y), q = dx * dx + dy * dy
          if q < best { best = q; s = pts[k].2 }
          k += 2
        }
        a[i] = Float(s)
      }
    }
  }
  // make the repeats land evenly around the closed outline
  let ropeN = (total / (1.25 * u)).rounded(), hatchN = (total / (0.62 * u)).rounded()

  // a small domed suit, centred in a sunburst
  let mcy = cy + size * (name == "heart" ? -0.05 : (name == "spade" ? 0.035 : 0))
  let motifPath = suitPath(name, cx: cx, cy: mcy, size: size * (name == "diamond" ? 0.3 : 0.36))
  let motif = mask { $0.addPath(motifPath); $0.fillPath(using: .winding) }
  let dm = edt(motif)
  let domeR = 3.0 * u

  for i in 0..<(W * H) where mk[i] > 0 {
    let dd = d[i], s = along[i]
    var z: Float = 0, shade: Float = 1
    if dd < rim1 {                                  // rolled outer rim
      let t = dd / rim1
      z = 1.0 * Float(sin(Double(t) * .pi / 2 + 0.25))
    } else if dd < rope0 {                          // groove
      z = 0.38; shade = 0.5
    } else if dd < rope1 {                          // twisted rope
      let t = (dd - rope0) / (rope1 - rope0)
      let tw = s / total * ropeN + t * 0.9
      let f = tw - tw.rounded(.down)
      let bead = Float(sin(Double(f) * .pi))
      let across = Float(sin(Double(t) * .pi))
      z = 0.42 + 0.62 * pow(bead, 0.8) * pow(across, 0.6)
      shade = 0.62 + 0.38 * smooth(0.05, 0.45, bead)
    } else if dd < band1 {                          // engraved hatch band
      let f = s / total * hatchN
      let g = abs(f - f.rounded()) * 2
      let t = (dd - rope1) / (band1 - rope1)
      let edge = smooth(0, 0.12, t) * smooth(1, 0.88, t)
      z = 0.28 + 0.12 * smooth(0.35, 0.8, g) * edge
      shade = 0.42 + 0.5 * smooth(0.3, 0.75, g) * edge + (1 - edge) * 0.1
    } else if dd < rim2 {                           // inner rim
      let t = (dd - band1) / (rim2 - band1)
      z = 0.34 + 0.5 * Float(sin(Double(t) * .pi))
    } else {                                        // sunken field with a brushed look
      let ang = atan2(Float(i / W) - Float(mcy), Float(i % W) - Float(cx))
      let f = (ang / (2 * .pi) + 0.5) * 72
      let g = abs(f - f.rounded()) * 2
      z = 0.14 + 0.09 * smooth(0.25, 0.75, g); shade = 0.5 + 0.34 * smooth(0.25, 0.75, g)
    }
    // raised leaves
    if motif[i] > 0 && dd >= rim2 - u * 0.3 {
      let p = min(dm[i] / domeR, 1)
      let dome = Float((1 - pow(Double(1 - p), 2.0)))
      z = 0.2 + 0.95 * dome
      shade = 0.88 + 0.12 * smooth(0, 0.2, p)
    }
    h[i] = max(h[i], z * 1.05 * u)
    cov[i] = max(cov[i], mk[i] * shade)
  }
}

func corner(_ c: CGContext, _ suit: String, _ w: CGFloat) {
  text(c, "A", font: "Georgia-Bold", size: w * 0.178, x: w * 0.137, y: w * 0.2)
  c.addPath(suitPath(suit, cx: w * 0.137, cy: w * 0.28, size: w * 0.125)); c.fillPath(using: .winding)
}

func bake(_ name: String, _ build: (inout [Float], inout [Float]) -> Void) {
  var h = [Float](repeating: 0, count: W * H), cov = [Float](repeating: 0, count: W * H)
  build(&h, &cov)
  blur(&h, r: SS)
  // normals from the height field, then average down to the final size
  var data = [UInt8](repeating: 0, count: FW * FH * 3)
  data.withUnsafeMutableBufferPointer { dp in
    let out = dp.baseAddress!
    DispatchQueue.concurrentPerform(iterations: FH) { fy in
      for fx in 0..<FW {
        var nx: Float = 0, ny: Float = 0, cv: Float = 0
        for sy in 0..<SS { for sx in 0..<SS {
          let x = min(max(fx * SS + sx, 1), W - 2), y = min(max(fy * SS + sy, 1), H - 2), i = y * W + x
          nx += (h[i - 1] - h[i + 1]) * 0.5; ny += (h[i - W] - h[i + W]) * 0.5; cv += cov[i]
        } }
        let k = Float(SS * SS); nx /= k; ny /= k; cv /= k
        let l = (nx * nx + ny * ny + 1).squareRoot()
        let o = (fy * FW + fx) * 3
        out[o] = UInt8(min(max((nx / l * 0.5 + 0.5) * 255, 0), 255))
        out[o + 1] = UInt8(min(max((ny / l * 0.5 + 0.5) * 255, 0), 255))
        out[o + 2] = UInt8(min(max(cv * 255, 0), 255))
      }
    }
  }
  let provider = CGDataProvider(data: Data(data) as CFData)!
  let img = CGImage(width: FW, height: FH, bitsPerComponent: 8, bitsPerPixel: 24, bytesPerRow: FW * 3,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                    provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
  let url = URL(fileURLWithPath: OUT + "/" + name + ".png") as CFURL
  let dst = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil)!
  CGImageDestinationAddImage(dst, img, nil); CGImageDestinationFinalize(dst)
  for q in [0.85] {
    let ju = URL(fileURLWithPath: OUT + "/" + name + "-q\(Int(q * 100)).jpg") as CFURL
    let jd = CGImageDestinationCreateWithURL(ju, UTType.jpeg.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(jd, img, [kCGImageDestinationLossyCompressionQuality: q] as CFDictionary); CGImageDestinationFinalize(jd)
  }
  print("baked", name)
}

let cw = CGFloat(W), ch = CGFloat(H)
func frameMask() -> [Float] {
  mask { c in
    c.setLineWidth(cw * 0.0085); c.addPath(roundRect(cw * 0.036, cw * 0.036, cw * 0.928, ch - cw * 0.072, cw * 0.06)); c.strokePath()
    c.setLineWidth(cw * 0.0036); c.addPath(roundRect(cw * 0.052, cw * 0.052, cw * 0.896, ch - cw * 0.104, cw * 0.046)); c.strokePath()
  }
}
func face(_ suit: String, _ label: String) -> (inout [Float], inout [Float]) -> Void {
  return { h, cov in
    foil(frameMask(), bevel: Float(U) * 0.12, height: Float(U) * 0.1, into: &h, cov: &cov)
    let marks = mask { c in
      corner(c, suit, cw)
      c.saveGState(); c.translateBy(x: cw, y: ch); c.rotate(by: .pi); corner(c, suit, cw); c.restoreGState()
    }
    foil(marks, bevel: Float(U) * 0.22, height: Float(U) * 0.22, into: &h, cov: &cov)
    let word = mask { c in text(c, label, font: "AvenirNext-DemiBold", size: cw * 0.088, x: cw * 0.5, y: ch * 0.8, tracking: cw * 0.016) }
    foil(word, bevel: Float(U) * 0.16, height: Float(U) * 0.16, into: &h, cov: &cov)
    emblem(suit, cx: cw * 0.5, cy: ch * 0.44, size: cw * 0.76, into: &h, cov: &cov)
  }
}
try? FileManager.default.createDirectory(atPath: OUT, withIntermediateDirectories: true)
bake("card-en", face("spade", "ENGLISH"))
bake("card-es", face("heart", "ESPAÑOL"))
bake("card-back") { h, cov in
  foil(frameMask(), bevel: Float(U) * 0.35, height: Float(U) * 0.55, into: &h, cov: &cov)
  // diamond lattice, clipped inside the frame
  let lat = mask { c in
    c.addPath(roundRect(cw * 0.075, cw * 0.075, cw * 0.85, ch - cw * 0.15, cw * 0.03)); c.clip()
    c.setLineWidth(cw * 0.0042)
    let st = cw * 0.075
    var x = -ch
    while x < cw + ch { c.move(to: CGPoint(x: x, y: 0)); c.addLine(to: CGPoint(x: x + ch, y: ch)); c.move(to: CGPoint(x: x + ch, y: 0)); c.addLine(to: CGPoint(x: x, y: ch)); x += st }
    c.strokePath()
  }
  // keep the lattice clear of the centre emblem
  let hole = mask { $0.addEllipse(in: CGRect(x: cw * 0.13, y: ch * 0.5 - cw * 0.37, width: cw * 0.74, height: cw * 0.74)); $0.fillPath() }
  var lat2 = lat
  for i in 0..<(W * H) { lat2[i] = lat[i] * (1 - hole[i]) }
  foil(lat2, bevel: Float(U) * 0.2, height: Float(U) * 0.3, into: &h, cov: &cov)
  let ring = mask { c in c.setLineWidth(cw * 0.008); c.addEllipse(in: CGRect(x: cw * 0.14, y: ch * 0.5 - cw * 0.36, width: cw * 0.72, height: cw * 0.72)); c.strokePath() }
  foil(ring, bevel: Float(U) * 0.35, height: Float(U) * 0.6, into: &h, cov: &cov)
  emblem("spade", cx: cw * 0.5, cy: ch * 0.5, size: cw * 0.52, into: &h, cov: &cov)
}
