public struct ProximityConfig {
    public var near: Double = -65
    public var far: Double = -78
    public var farGrace: Double = 8
    public var stale: Double = 20
    public var nearStable: Double = 3
    public var cooldown: Double = 30
    public var wakeGrace: Double = 10
    public var alpha: Double = 0.25
    public var maximumEvidenceGap: Double = 3
    public init() {}
}
public struct ProximityEngine {
    public let config: ProximityConfig
    public private(set) var active = false
    public private(set) var armed = false
    public private(set) var smooth: Double?
    private var lastSample: Double?
    private var nearSince: Double?
    private var farSince: Double?
    private var allowedAfter: Double = 0
    private var lastTime: Double = 0
    public init(config: ProximityConfig = .init()) {
        var c = config
        func bounded(_ x: Double, _ lo: Double, _ hi: Double, _ fallback: Double) -> Double {
            x.isFinite ? min(hi, max(lo, x)) : fallback
        }
        c.near = bounded(c.near, -100, -30, -65)
        c.far = bounded(c.far, -120, c.near - 3, min(-78, c.near - 3))
        c.alpha = bounded(c.alpha, 0.01, 1, 0.25)
        c.farGrace = bounded(c.farGrace, 1, 120, 8)
        c.stale = bounded(c.stale, 5, 180, 20)
        c.nearStable = bounded(c.nearStable, 1, 30, 3)
        c.cooldown = bounded(c.cooldown, 10, 300, 30)
        c.wakeGrace = bounded(c.wakeGrace, 5, 120, 10)
        c.maximumEvidenceGap = bounded(c.maximumEvidenceGap, 1, min(10, c.stale), 3)
        self.config = c
    }
    public mutating func start(now: Double) {
        stop(); active = true; lastTime = now; allowedAfter = now
    }
    public mutating func stop() {
        active = false; armed = false; smooth = nil; lastSample = nil; nearSince = nil; farSince = nil
    }
    public mutating func sample(rssi: Double, now: Double) {
        guard active, now.isFinite, now >= lastTime, rssi.isFinite, rssi >= -127, rssi < 0 else { return }
        lastTime = now
        // Configured maximum evidence gap is independent of the longer
        // loss timeout. Sparse samples must not qualify as continuous proximity.
        if let lastSample, now - lastSample > config.maximumEvidenceGap { nearSince = nil; smooth = nil; farSince = nil }
        smooth = smooth.map { $0 + config.alpha * (rssi - $0) } ?? rssi; lastSample = now
        if smooth! >= config.near && now >= allowedAfter {
            if nearSince == nil { nearSince = now }
            if now - nearSince! >= config.nearStable { armed = true }
        } else { nearSince = nil }
        if armed && smooth! <= config.far {
            if farSince == nil { farSince = now }
        } else { farSince = nil }
    }
    public mutating func tick(now: Double) -> Bool {
        guard active, now.isFinite, now >= lastTime else { return false }
        lastTime = now
        guard armed else { return false }
        // Lack of samples is handled solely by stale timeout, never by far grace.
        if let lastSample, now - lastSample > config.maximumEvidenceGap { farSince = nil; nearSince = nil }
        let isFar = farSince.map { now - $0 >= config.farGrace } ?? false
        let isStale = lastSample.map { now - $0 >= config.stale } ?? false
        guard isFar || isStale else { return false }
        armed = false; self.farSince = nil; nearSince = nil; allowedAfter = now + config.cooldown
        return true
    }
    public mutating func suspend() { stop() }
    public mutating func manualReturn(now: Double) {
        stop(); start(now: now); allowedAfter = now + config.cooldown
    }
    public mutating func wake(now: Double) {
        stop(); start(now: now); allowedAfter = now + config.wakeGrace
    }
}
