use super::*;

pub(crate) fn register_handle(registry: &OnceLock<Mutex<HashSet<usize>>>, handle: *mut c_void) {
    if handle.is_null() {
        return;
    }
    let lock = registry.get_or_init(|| Mutex::new(HashSet::new()));
    let mut guard = match lock.lock() {
        Ok(v) => v,
        Err(poisoned) => poisoned.into_inner(),
    };
    guard.insert(handle as usize);
}

pub(crate) fn unregister_handle(registry: &OnceLock<Mutex<HashSet<usize>>>, handle: *mut c_void) -> bool {
    if handle.is_null() {
        return false;
    }
    let Some(lock) = registry.get() else {
        return false;
    };
    let mut guard = match lock.lock() {
        Ok(v) => v,
        Err(poisoned) => poisoned.into_inner(),
    };
    guard.remove(&(handle as usize))
}

pub(crate) fn validate_handle(
    registry: &OnceLock<Mutex<HashSet<usize>>>,
    handle: *const c_void,
) -> Result<(), i32> {
    if handle.is_null() {
        return Err(VS_STATUS_NULL_POINTER);
    }
    let Some(lock) = registry.get() else {
        return Err(VS_STATUS_INVALID_ARGUMENT);
    };
    let guard = match lock.lock() {
        Ok(v) => v,
        Err(poisoned) => poisoned.into_inner(),
    };
    if guard.contains(&(handle as usize)) {
        Ok(())
    } else {
        Err(VS_STATUS_INVALID_ARGUMENT)
    }
}


#[no_mangle]
pub extern "C" fn vs_core_version() -> *const c_char {
    VERSION.as_ptr().cast()
}

#[no_mangle]
pub unsafe extern "C" fn vs_core_abi_version(
    out_major: *mut u32,
    out_minor: *mut u32,
    out_patch: *mut u32,
) -> i32 {
    if out_major.is_null() || out_minor.is_null() || out_patch.is_null() {
        return VS_STATUS_NULL_POINTER;
    }

    unsafe {
        *out_major = VS_CORE_ABI_VERSION_MAJOR;
        *out_minor = VS_CORE_ABI_VERSION_MINOR;
        *out_patch = VS_CORE_ABI_VERSION_PATCH;
    }
    VS_STATUS_OK
}
