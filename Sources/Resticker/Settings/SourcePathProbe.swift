import Foundation
import RestickerCore

/// Reads one byte of a file, or lists a directory, the same way a backup would read it.
/// This is the whole point of calling it from Settings: it makes macOS show its privacy
/// prompt (Full Disk Access / folder access) right when a path is added, instead of the
/// first time a scheduled backup silently fails to read it.
enum SourcePathProbe {
    /// True only when the failure was a permission denial. A path that is merely missing,
    /// e.g. a removable drive that is not attached, is not a permissions problem and must
    /// not show the "cannot read this folder" warning.
    static func isPermissionDenied(_ path: String) -> Bool {
        let expanded = Paths.expand(path)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory) else { return false }

        if isDirectory.boolValue {
            guard let dir = opendir(expanded) else { return errno == EACCES || errno == EPERM }
            closedir(dir)
            return false
        }

        let descriptor = open(expanded, O_RDONLY)
        guard descriptor >= 0 else { return errno == EACCES || errno == EPERM }
        var byte: UInt8 = 0
        _ = read(descriptor, &byte, 1)
        close(descriptor)
        return false
    }
}
