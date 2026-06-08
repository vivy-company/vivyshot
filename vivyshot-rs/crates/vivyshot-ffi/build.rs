use std::path::PathBuf;
use std::process::Command;

fn main() {
    println!("cargo:rerun-if-changed=build.rs");
    println!("cargo:rerun-if-env-changed=DEVELOPER_DIR");
    println!("cargo:rerun-if-env-changed=SDKROOT");

    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() != Ok("macos") {
        return;
    }

    let runtime_dirs = swift_runtime_dirs();
    if runtime_dirs.is_empty() {
        println!(
            "cargo:warning=vivyshot-ffi could not resolve Xcode Swift runtime rpaths; \
             Cargo test binaries that link the ScreenCaptureKit Swift bridge may need \
             DYLD_LIBRARY_PATH"
        );
        return;
    }

    for dir in runtime_dirs {
        println!("cargo:rustc-link-arg=-Wl,-rpath,{}", dir.display());
    }
}

fn swift_runtime_dirs() -> Vec<PathBuf> {
    // System Swift libraries may be provided by the dyld shared cache rather
    // than files on disk, so keep this rpath even when `exists()` is false.
    let mut dirs = vec![PathBuf::from("/usr/lib/swift")];

    let output = match Command::new("xcrun").args(["--find", "swift"]).output() {
        Ok(output) if output.status.success() => output,
        _ => return dirs,
    };
    let swift_path = String::from_utf8_lossy(&output.stdout).trim().to_string();
    let Some(usr_dir) = PathBuf::from(swift_path)
        .parent()
        .and_then(|bin_dir| bin_dir.parent())
        .map(PathBuf::from)
    else {
        return dirs;
    };

    dirs.extend(
        [
            usr_dir.join("lib/swift-5.5/macosx"),
            usr_dir.join("lib/swift/macosx"),
        ]
        .into_iter()
        .filter(|dir| dir.join("libswift_Concurrency.dylib").exists()),
    );
    dirs
}
