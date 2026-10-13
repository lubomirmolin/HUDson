import AudioToolbox
import CoreAudio
import Foundation

/// Volume and mute of the current default output device, plus change notifications for changes
/// made elsewhere (menu bar slider, AirPods, other apps).
final class AudioOutput {
    var onExternalChange: (() -> Void)?

    private(set) var deviceID = AudioDeviceID(kAudioObjectUnknown)
    private var observedDevice = AudioDeviceID(kAudioObjectUnknown)
    private lazy var defaultDeviceListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        self?.refreshDevice()
    }
    private lazy var levelListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        self?.onExternalChange?()
    }

    init() {
        var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, defaultDeviceListener)
        refreshDevice()
    }

    // MARK: Level

    var canSetVolume: Bool {
        var address = Self.volumeAddress
        guard AudioObjectHasProperty(deviceID, &address) else { return false }
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(deviceID, &address, &settable) == noErr && settable.boolValue
    }

    var volume: Float {
        get { read(Self.volumeAddress, default: Float32(0)) }
        set { write(Self.volumeAddress, Float32(min(max(newValue, 0), 1))) }
    }

    var isMuted: Bool {
        get { read(Self.muteAddress, default: UInt32(0)) != 0 }
        set { write(Self.muteAddress, UInt32(newValue ? 1 : 0)) }
    }

    // MARK: Device info

    enum Kind { case speakers, headphones, airPods, airPodsPro, airPodsMax, display }

    var kind: Kind {
        let name = deviceName.lowercased()
        switch read(Self.address(kAudioDevicePropertyTransportType), default: UInt32(0)) {
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
            if name.contains("airpods max") { return .airPodsMax }
            if name.contains("airpods pro") { return .airPodsPro }
            if name.contains("airpods") { return .airPods }
            return .headphones
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort:
            return .display
        case kAudioDeviceTransportTypeBuiltIn:
            let headphonesSource: UInt32 = 0x6864_706E // 'hdpn'
            let source = read(Self.address(kAudioDevicePropertyDataSource, scope: kAudioDevicePropertyScopeOutput), default: UInt32(0))
            return source == headphonesSource ? .headphones : .speakers
        default:
            return .speakers
        }
    }

    var deviceName: String {
        var address = Self.address(kAudioObjectPropertyName)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &name) == noErr,
              let name else { return "" }
        return name.takeRetainedValue() as String
    }

    // MARK: Plumbing

    private func refreshDevice() {
        deviceID = read(Self.address(kAudioHardwarePropertyDefaultOutputDevice),
                        of: AudioObjectID(kAudioObjectSystemObject),
                        default: AudioDeviceID(kAudioObjectUnknown))
        guard deviceID != observedDevice else { return }

        for var address in [Self.volumeAddress, Self.muteAddress] {
            if observedDevice != kAudioObjectUnknown {
                AudioObjectRemovePropertyListenerBlock(observedDevice, &address, .main, levelListener)
            }
            if deviceID != kAudioObjectUnknown, AudioObjectHasProperty(deviceID, &address) {
                AudioObjectAddPropertyListenerBlock(deviceID, &address, .main, levelListener)
            }
        }
        observedDevice = deviceID
    }

    private func read<T: BitwiseCopyable>(_ address: AudioObjectPropertyAddress, of object: AudioObjectID? = nil, default fallback: T) -> T {
        var address = address
        var value = fallback
        var size = UInt32(MemoryLayout<T>.size)
        let status = AudioObjectGetPropertyData(object ?? deviceID, &address, 0, nil, &size, &value)
        return status == noErr ? value : fallback
    }

    private func write<T: BitwiseCopyable>(_ address: AudioObjectPropertyAddress, _ value: T) {
        var address = address
        var value = value
        AudioObjectSetPropertyData(deviceID, &address, 0, nil, UInt32(MemoryLayout<T>.size), &value)
    }

    private static func address(_ selector: AudioObjectPropertySelector,
                                scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static let volumeAddress = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope: kAudioDevicePropertyScopeOutput)
    private static let muteAddress = address(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput)
}
