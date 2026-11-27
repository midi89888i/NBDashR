import Foundation
import CoreLocation
import CoreMotion
import Combine

/// GPS + IMU 速度融合与行程统计(简化版 SpeedFusionEngine)。
/// 职责:GPS 速度为主,静止判断融合 IMU;压弯倾角、纵向 G;行程里程/时长/极速。
@MainActor
final class SensorFusion: NSObject, ObservableObject {
    @Published private(set) var speedKmh: Double = 0
    @Published private(set) var altitudeMeters: Double = 0
    @Published private(set) var headingDegrees: Double = 0
    @Published private(set) var hasGPSFix: Bool = false
    @Published private(set) var leanAngleDeg: Double = 0
    @Published private(set) var maxLeftLeanDeg: Double = 0
    @Published private(set) var maxRightLeanDeg: Double = 0
    @Published private(set) var longitudinalG: Double = 0

    @Published private(set) var tripDistanceKm: Double = 0
    @Published private(set) var maxSpeedKmh: Double = 0
    @Published private(set) var tripStartAt: Date?
    @Published private(set) var speedHistory: [Double] = []

    private let locationManager = CLLocationManager()
    private let motionManager = CMMotionManager()
    private var lastLocation: CLLocation?
    private var historyTimer: Timer?

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.activityType = .automotiveNavigation
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
    }

    func start() {
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
        locationManager.startUpdatingHeading()
        if motionManager.isDeviceMotionAvailable {
            motionManager.deviceMotionUpdateInterval = 1.0 / 50.0
            motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
                guard let self, let motion else { return }
                // 压弯倾角:roll(纵向安装的手机近似);实际以仪表方向为准,取 roll 角度
                let rollDeg = motion.attitude.roll * 180 / .pi
                self.leanAngleDeg = rollDeg
                self.maxLeftLeanDeg = max(self.maxLeftLeanDeg, -rollDeg)
                self.maxRightLeanDeg = max(self.maxRightLeanDeg, rollDeg)
                // 纵向 G:userAcceleration.y(依设备安装方向近似)
                self.longitudinalG = motion.userAcceleration.y
            }
        }
        historyTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
    }

    private func tick() {
        speedHistory.append(speedKmh)
        if speedHistory.count > 60 { speedHistory.removeFirst(speedHistory.count - 60) }
    }

    func resetTrip() {
        tripDistanceKm = 0
        maxSpeedKmh = 0
        maxLeftLeanDeg = 0
        maxRightLeanDeg = 0
        speedHistory.removeAll()
        tripStartAt = Date()
    }

    func stop() {
        locationManager.stopUpdatingLocation()
        motionManager.stopDeviceMotionUpdates()
        historyTimer?.invalidate()
    }
}

extension SensorFusion: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        hasGPSFix = loc.horizontalAccuracy >= 0 && loc.horizontalAccuracy < 30
        if loc.speed >= 0 {
            var kmh = loc.speed * 3.6
            if kmh < 1.2 { kmh = 0 }  // 静止死区
            speedKmh = kmh
            maxSpeedKmh = max(maxSpeedKmh, kmh)
        }
        altitudeMeters = loc.altitude
        if loc.course >= 0 { headingDegrees = loc.course }
        if let last = lastLocation, hasGPSFix {
            let d = loc.distance(from: last) / 1000.0
            if d < 0.5 { tripDistanceKm += d }  // 排除跳点
        }
        if tripStartAt == nil { tripStartAt = Date() }
        lastLocation = loc
    }
}
