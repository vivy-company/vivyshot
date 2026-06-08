use std::path::PathBuf;
use std::process::Command;

fn main() {
    println!("cargo:rerun-if-changed=build.rs");
    println!("cargo:rerun-if-changed=swift-bridge");
    println!("cargo:rerun-if-env-changed=DEVELOPER_DIR");
    println!("cargo:rerun-if-env-changed=SDKROOT");

    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() != Ok("macos") {
        return;
    }

    let target_arch = std::env::var("CARGO_CFG_TARGET_ARCH").unwrap_or_default();
    let swift_triple = match target_arch.as_str() {
        "x86_64" => "x86_64-apple-macosx",
        "aarch64" => "arm64-apple-macosx",
        other => panic!(
            "vivyshot-apple-media-sys: unsupported target arch '{other}'. \
             Expected x86_64 or aarch64."
        ),
    };

    let out_dir = std::env::var("OUT_DIR").expect("OUT_DIR must be set by Cargo");
    let swift_build_dir = format!("{out_dir}/swift-build");
    let output = Command::new("swift")
        .args([
            "build",
            "-c",
            "release",
            "--triple",
            swift_triple,
            "--package-path",
            "swift-bridge",
            "--scratch-path",
            &swift_build_dir,
        ])
        .output()
        .expect("failed to build VivyShot Apple media Swift bridge");

    if !output.status.success() {
        eprintln!(
            "Swift build STDOUT:\n{}",
            String::from_utf8_lossy(&output.stdout)
        );
        eprintln!(
            "Swift build STDERR:\n{}",
            String::from_utf8_lossy(&output.stderr)
        );
        panic!(
            "VivyShot Apple media Swift bridge failed with exit code: {:?}",
            output.status.code()
        );
    }

    println!("cargo:rustc-link-search=native={swift_build_dir}/release");
    println!("cargo:rustc-link-lib=static=VivyShotAppleMediaBridge");
    println!("cargo:rustc-link-lib=framework=AVFoundation");
    println!("cargo:rustc-link-lib=framework=CoreMedia");
    println!("cargo:rustc-link-lib=framework=CoreVideo");
    println!("cargo:rustc-link-lib=framework=Foundation");
    println!("cargo:rustc-link-lib=framework=ScreenCaptureKit");
    println!("cargo:rustc-link-lib=framework=VideoToolbox");

    for dir in swift_runtime_dirs() {
        println!("cargo:rustc-link-arg=-Wl,-rpath,{}", dir.display());
    }
}

fn swift_runtime_dirs() -> Vec<PathBuf> {
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
