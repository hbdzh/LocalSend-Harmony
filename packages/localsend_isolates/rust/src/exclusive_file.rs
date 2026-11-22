use std::ffi::CStr;
use std::fs::OpenOptions;
use std::os::fd::IntoRawFd;
use std::os::raw::{c_char, c_int};

/// Atomically creates a new file. A non-negative result is an owned file
/// descriptor; a negative result is the negated operating-system error code.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn localsend_create_exclusive(path: *const c_char) -> c_int {
    if path.is_null() {
        return -22;
    }
    // SAFETY: the caller supplies a live, NUL-terminated string.
    let path = unsafe { CStr::from_ptr(path) };
    use std::os::unix::ffi::OsStrExt;
    let path = std::ffi::OsStr::from_bytes(path.to_bytes());
    match OpenOptions::new().write(true).create_new(true).open(path) {
        Ok(file) => file.into_raw_fd(),
        Err(error) => -error.raw_os_error().unwrap_or(5),
    }
}

/// Closes a descriptor if Dart could not hand it over to the Rust receiver.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn localsend_close_descriptor(fd: c_int) {
    use std::os::fd::{FromRawFd, OwnedFd};
    if fd >= 0 {
        // SAFETY: the caller transfers an open descriptor exactly once.
        drop(unsafe { OwnedFd::from_raw_fd(fd) });
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::ffi::CString;
    use std::io::Write;
    use std::os::fd::FromRawFd;

    #[test]
    fn replacing_name_does_not_redirect_write_and_descriptor_closes() {
        let root = std::env::temp_dir().join(format!("localsend-fd-{}", uuid::Uuid::new_v4()));
        std::fs::create_dir(&root).unwrap();
        let path = root.join("file.txt");
        let original = root.join("original.txt");
        let name = CString::new(path.to_str().unwrap()).unwrap();
        let fd = unsafe { localsend_create_exclusive(name.as_ptr()) };
        assert!(fd >= 0);
        assert_eq!(unsafe { localsend_create_exclusive(name.as_ptr()) }, -17);
        std::fs::rename(&path, &original).unwrap();
        std::fs::write(&path, b"keep").unwrap();
        {
            let mut file = unsafe { std::fs::File::from_raw_fd(fd) };
            file.write_all(b"received").unwrap();
        }
        assert_eq!(std::fs::read(&path).unwrap(), b"keep");
        assert_eq!(std::fs::read(&original).unwrap(), b"received");
        unsafe extern "C" {
            fn fcntl(fd: c_int, cmd: c_int, ...) -> c_int;
        }
        assert_eq!(unsafe { fcntl(fd, 1) }, -1); // F_GETFD: descriptor was closed.
        std::fs::remove_dir_all(root).unwrap();
    }
}
