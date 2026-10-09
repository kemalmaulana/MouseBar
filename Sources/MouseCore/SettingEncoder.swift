public struct SettingEncoder: Sendable {
    public let layouts: ButtonLayouts
    public init(layouts: ButtonLayouts) { self.layouts = layouts }
    public func encode(_ spec: SettingSpec, value: SettingValue) throws -> [UInt8] {
        throw MouseCoreError.unsupportedValueType(spec.valueType)
    }
}
