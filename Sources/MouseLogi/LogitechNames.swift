/// Display names for Logitech receivers' paired mice.
enum LogitechNames {
    static func name(wpid: Int?, codename: String?) -> String {
        if wpid == 0x4074 { return "Logitech G304 / G305" }
        if let codename, !codename.isEmpty { return "Logitech \(codename)" }
        return "Logitech mouse"
    }
}
