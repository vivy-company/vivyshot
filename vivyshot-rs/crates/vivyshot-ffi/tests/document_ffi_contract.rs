mod common;

use common::{destroy_doc, make_doc, zero_annotation_info};
use std::ffi::CStr;
use vivyshot_core::{
    vs_add_ellipse, vs_add_path, vs_add_rect, vs_annotation_info, vs_copy_annotations_affine,
    vs_core_version, vs_create_document_from_bgra, vs_dirty_rect, vs_ellipse_command,
    vs_list_annotations, vs_move_annotation, vs_path_style, vs_point_i32, vs_rect_command,
    vs_remove_annotation, vs_render_dirty, vs_render_full, vs_resize_annotation,
};

#[test]
fn core_version_returns_nonempty_c_string() {
    let ptr = vs_core_version();
    assert!(!ptr.is_null());

    // SAFETY: version pointer is static and null-terminated by the core.
    let text = unsafe { CStr::from_ptr(ptr) }.to_string_lossy();
    assert!(!text.is_empty());
}

#[test]
fn create_document_rejects_invalid_inputs() {
    let base = [0u8; 4 * 4 * 4];

    // SAFETY: pointers remain valid for each FFI call.
    unsafe {
        let null_width = vs_create_document_from_bgra(0, 4, 16, base.as_ptr(), base.len());
        assert!(null_width.is_null());

        let bad_stride = vs_create_document_from_bgra(4, 4, 8, base.as_ptr(), base.len());
        assert!(bad_stride.is_null());

        let null_ptr = vs_create_document_from_bgra(4, 4, 16, std::ptr::null(), base.len());
        assert!(null_ptr.is_null());

        let short_len = vs_create_document_from_bgra(4, 4, 16, base.as_ptr(), 8);
        assert!(short_len.is_null());
    }
}

#[test]
fn annotation_lifecycle_renders_and_reports_dirty_regions() {
    // SAFETY: handles are created and destroyed in this scope.
    unsafe {
        let doc = make_doc(64, 48);
        assert!(!doc.is_null());

        let rect = vs_rect_command {
            x: 6,
            y: 7,
            width: 20,
            height: 10,
            stroke_width: 2,
            r: 255,
            g: 32,
            b: 64,
            a: 255,
        };
        assert_eq!(vs_add_rect(doc, rect), 0);

        let ellipse = vs_ellipse_command {
            x: 28,
            y: 14,
            width: 16,
            height: 12,
            stroke_width: 2,
            r: 16,
            g: 200,
            b: 32,
            a: 255,
        };
        assert_eq!(vs_add_ellipse(doc, ellipse), 0);

        let path_points = [
            vs_point_i32 { x: 10, y: 28 },
            vs_point_i32 { x: 22, y: 34 },
            vs_point_i32 { x: 30, y: 36 },
        ];
        let path_style = vs_path_style {
            stroke_width: 3,
            r: 240,
            g: 240,
            b: 0,
            a: 255,
        };
        assert_eq!(
            vs_add_path(doc, path_points.as_ptr(), path_points.len(), path_style),
            0
        );

        let mut infos = [zero_annotation_info(); 4];
        let mut total = 0usize;
        assert_eq!(
            vs_list_annotations(doc, infos.as_mut_ptr(), infos.len(), &mut total),
            0
        );
        assert_eq!(total, 3);

        assert_eq!(vs_move_annotation(doc, 0, 4, 3), 0);
        assert_eq!(vs_resize_annotation(doc, 1, 24, 12, 20, 16), 0);
        assert_eq!(vs_resize_annotation(doc, 1, 24, 12, 0, 16), -2);

        let mut frame = vec![0u8; 64 * 48 * 4];
        assert_eq!(vs_render_full(doc, frame.as_mut_ptr(), frame.len()), 0);

        let mut dirty = [vs_dirty_rect {
            x: 0,
            y: 0,
            width: 0,
            height: 0,
        }; 1];
        let mut dirty_written = 0usize;
        assert_eq!(
            vs_render_dirty(
                doc,
                frame.as_mut_ptr(),
                frame.len(),
                dirty.as_mut_ptr(),
                dirty.len(),
                &mut dirty_written,
            ),
            0
        );
        assert_eq!(dirty_written, 0);

        assert_eq!(vs_remove_annotation(doc, 2), 0);
        assert_eq!(
            vs_render_dirty(
                doc,
                frame.as_mut_ptr(),
                frame.len(),
                dirty.as_mut_ptr(),
                dirty.len(),
                &mut dirty_written,
            ),
            0
        );
        assert_eq!(dirty_written, 1);
        assert!(dirty[0].width > 0);
        assert!(dirty[0].height > 0);

        destroy_doc(doc);
    }
}

#[test]
fn copy_annotations_affine_transfers_commands() {
    // SAFETY: handles are valid and cleaned up in this scope.
    unsafe {
        let src = make_doc(80, 60);
        let dst = make_doc(160, 120);
        assert!(!src.is_null());
        assert!(!dst.is_null());

        assert_eq!(
            vs_add_rect(
                src,
                vs_rect_command {
                    x: 8,
                    y: 10,
                    width: 18,
                    height: 14,
                    stroke_width: 2,
                    r: 255,
                    g: 0,
                    b: 0,
                    a: 255,
                },
            ),
            0
        );
        assert_eq!(
            vs_add_rect(
                src,
                vs_rect_command {
                    x: 35,
                    y: 20,
                    width: 22,
                    height: 18,
                    stroke_width: 2,
                    r: 0,
                    g: 255,
                    b: 0,
                    a: 255,
                },
            ),
            0
        );

        assert_eq!(vs_copy_annotations_affine(dst, src, 2.0, 2.0, 6.0, 4.0), 0);

        let mut out = [vs_annotation_info {
            index: 0,
            kind: 0,
            x: 0,
            y: 0,
            width: 0,
            height: 0,
        }; 4];
        let mut total = 0usize;
        assert_eq!(
            vs_list_annotations(dst, out.as_mut_ptr(), out.len(), &mut total),
            0
        );
        assert_eq!(total, 2);
        assert!(out[0].x >= 0);
        assert!(out[0].width > 0);

        let mut frame = vec![0u8; 160 * 120 * 4];
        assert_eq!(vs_render_full(dst, frame.as_mut_ptr(), frame.len()), 0);
        assert!(frame.iter().any(|b| *b != 0));

        destroy_doc(src);
        destroy_doc(dst);
    }
}
