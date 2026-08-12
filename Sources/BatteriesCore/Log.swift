import os

/// Centralized loggers, viewable live via:
///   log stream --predicate 'subsystem == "com.akhilchandran.batteries"'
/// or after the fact via Console.app / `log show`.
enum Log {
    static let refresh = Logger(subsystem: "com.akhilchandran.batteries", category: "refresh")
    static let shell = Logger(subsystem: "com.akhilchandran.batteries", category: "shell")
    static let devices = Logger(subsystem: "com.akhilchandran.batteries", category: "devices")
}
