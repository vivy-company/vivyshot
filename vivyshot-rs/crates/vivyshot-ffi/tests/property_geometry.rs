use proptest::prelude::*;
use vivyshot_core::{
    vs_f32_point, vs_f32_rect, vs_image_delta_to_view_delta, vs_image_rect_to_view_rect,
    vs_view_delta_to_image_delta, vs_view_rect_to_image_rect,
};

proptest! {
    #[test]
    fn view_image_roundtrip_holds_for_random_rects(
        dst_x in 0.0f32..200.0,
        dst_y in 0.0f32..200.0,
        dst_w in 120.0f32..2400.0,
        dst_h in 120.0f32..1400.0,
        inset_l in 0.0f32..120.0,
        inset_t in 0.0f32..120.0,
        inset_r in 0.0f32..120.0,
        inset_b in 0.0f32..120.0,
        img_w in 64u32..4096u32,
        img_h in 64u32..3072u32,
    ) {
        let destination = vs_f32_rect {
            x: dst_x,
            y: dst_y,
            width: dst_w,
            height: dst_h,
        };

        let min_x = dst_x + inset_l.min(dst_w * 0.4);
        let min_y = dst_y + inset_t.min(dst_h * 0.4);
        let max_x = dst_x + dst_w - inset_r.min(dst_w * 0.4);
        let max_y = dst_y + dst_h - inset_b.min(dst_h * 0.4);
        prop_assume!(max_x - min_x >= 4.0);
        prop_assume!(max_y - min_y >= 4.0);

        let view_rect = vs_f32_rect {
            x: min_x,
            y: min_y,
            width: max_x - min_x,
            height: max_y - min_y,
        };

        let mut image_rect = vs_f32_rect::default();
        // SAFETY: output pointers are valid local storage.
        let map_status = unsafe {
            vs_view_rect_to_image_rect(view_rect, destination, img_w, img_h, &mut image_rect)
        };
        prop_assert_eq!(map_status, 0);

        let mut roundtrip = vs_f32_rect::default();
        // SAFETY: output pointers are valid local storage.
        let inv_status = unsafe {
            vs_image_rect_to_view_rect(image_rect, destination, img_w, img_h, &mut roundtrip)
        };
        prop_assert_eq!(inv_status, 0);

        prop_assert!((roundtrip.x - view_rect.x).abs() <= 2.0);
        prop_assert!((roundtrip.y - view_rect.y).abs() <= 2.0);
        prop_assert!((roundtrip.width - view_rect.width).abs() <= 2.0);
        prop_assert!((roundtrip.height - view_rect.height).abs() <= 2.0);

        let mut img_delta = vs_f32_point::default();
        let mut view_delta = vs_f32_point::default();
        // SAFETY: output pointers are valid local storage.
        let d1 = unsafe {
            vs_view_delta_to_image_delta(15.0, -9.0, destination, img_w, img_h, &mut img_delta)
        };
        prop_assert_eq!(d1, 0);

        // SAFETY: output pointers are valid local storage.
        let d2 = unsafe {
            vs_image_delta_to_view_delta(img_delta.x, img_delta.y, destination, img_w, img_h, &mut view_delta)
        };
        prop_assert_eq!(d2, 0);

        prop_assert!((view_delta.x - 15.0).abs() <= 0.1);
        prop_assert!((view_delta.y - (-9.0)).abs() <= 0.1);
    }
}
