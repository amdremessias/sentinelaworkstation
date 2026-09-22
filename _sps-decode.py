"""Decode the H264 SPS bytes as served to the DVR (sprop-parameter-sets)."""
import base64

# From the DESCRIBE response (sprop-parameter-sets=..., comma separates SPS,PPS)
SPS_B64 = "Z01AKNoB4AiflhAAAAMAEAAAAwHo8YMq"
PPS_B64 = "aO88gA=="


def parse_ue(data, idx):
    """Read Exp-Golomb ue(v), returns (value, new_idx)."""
    zeros = 0
    while idx < len(data) and data[idx] == 0:
        zeros += 1
        idx += 1
    if idx >= len(data):
        return 0, idx
    idx += 1
    bits = 1
    val = 1
    while bits <= zeros:
        if idx < len(data) and data[idx] == 1:
            val = (val << 1) | 1
        else:
            val <<= 1
        idx += 1
        bits += 1
    return val - 1, idx


def bits_to_str(data, nbits, label):
    return "".join(str(data[i]) for i in range(nbits))


def decode_sps(b64, name):
    raw = base64.b64decode(b64)
    # strip NAL header (1 byte: F|NRI|type)
    nal = raw[1:]
    data = []
    for byte in nal:
        for i in range(7, -1, -1):
            data.append((byte >> i) & 1)
    idx = 0
    profile = 0
    for i in range(8):
        profile = (profile << 1) | data[idx]
        idx += 1
    constraint = 0
    for i in range(8):
        constraint = (constraint << 1) | data[idx]
        idx += 1
    level = 0
    for i in range(8):
        level = (level << 1) | data[idx]
        idx += 1
    sps_id, idx = parse_ue(data, idx)
    log2_max_frame_num_minus4, idx = parse_ue(data, idx)
    pic_order_cnt_type, idx = parse_ue(data, idx)
    log2_max_poc_lsb_minus4 = None
    delta_pic_order_always_zero = None
    if pic_order_cnt_type == 0:
        log2_max_poc_lsb_minus4, idx = parse_ue(data, idx)
    elif pic_order_cnt_type == 1:
        delta_pic_order_always_zero, idx = parse_ue(data, idx)
    max_num_ref_frames, idx = parse_ue(data, idx)
    gaps_in_frame_num, idx = parse_ue(data, idx)
    pic_width_in_mbs_minus1, idx = parse_ue(data, idx)
    pic_height_in_map_units_minus1, idx = parse_ue(data, idx)
    frame_mbs_only = data[idx]; idx += 1
    if not frame_mbs_only:
        mb_adaptive, idx = (data[idx], idx + 1)
    direct_8x8 = data[idx]; idx += 1
    frame_cropping = data[idx]; idx += 1
    crop_l = crop_r = crop_t = crop_b = None
    if frame_cropping:
        crop_l, idx = parse_ue(data, idx)
        crop_r, idx = parse_ue(data, idx)
        crop_t, idx = parse_ue(data, idx)
        crop_b, idx = parse_ue(data, idx)
    vui_present = data[idx]; idx += 1
    crop_unit_x, crop_unit_y = (2, 2) if frame_mbs_only else (2, 4)
    if frame_cropping:
        crop_l *= crop_unit_x; crop_r *= crop_unit_x
        crop_t *= crop_unit_y; crop_b *= crop_unit_y
    else:
        crop_l = crop_r = crop_t = crop_b = 0
    width = (pic_width_in_mbs_minus1 + 1) * 16 - crop_l - crop_r
    height = (pic_height_in_map_units_minus1 + 1) * (2 if frame_mbs_only else 4) - crop_t - crop_b

    print(f"--- {name} ---")
    print(f"  profile_idc      : {profile} ({'Main' if profile == 77 else 'Baseline' if profile == 66 else 'High' if profile == 100 else '?'})")
    print(f"  constraint flags : 0x{constraint:02x}")
    print(f"  level_idc        : {level} (level {level / 10:.1f})")
    print(f"  sps_id           : {sps_id}")
    print(f"  log2_max_frame_num_minus4: {log2_max_frame_num_minus4}")
    print(f"  pic_order_cnt_type: {pic_order_cnt_type}")
    print(f"  max_num_ref_frames: {max_num_ref_frames}")
    print(f"  frame_mbs_only    : {frame_mbs_only}")
    print(f"  direct_8x8_inference: {direct_8x8}")
    print(f"  frame_cropping    : {frame_cropping} -> crop_l={crop_l} crop_r={crop_r} crop_t={crop_t} crop_b={crop_b}")
    print(f"  WIDTH x HEIGHT    : {width}x{height}")
    print(f"  vui_parameters_present: {vui_present}")
    if vui_present:
        aspect_ratio_info = data[idx]; idx += 1
        print(f"  aspect_ratio_info_present: {aspect_ratio_info}")
        if aspect_ratio_info:
            ar_idc = 0
            for i in range(8):
                ar_idc = (ar_idc << 1) | data[idx]
                idx += 1
            print(f"    aspect_ratio_idc: {ar_idc}")
            if ar_idc == 255:
                sar_w = sar_h = 0
                for i in range(16):
                    sar_w = (sar_w << 1) | data[idx]
                    idx += 1
                for i in range(16):
                    sar_h = (sar_h << 1) | data[idx]
                    idx += 1
                print(f"    sar: {sar_w}:{sar_h}")
        overscan = data[idx]; idx += 1
        print(f"  overscan_info_present: {overscan}")
        if overscan:
            overscan_appropriate = data[idx]; idx += 1
            print(f"    overscan_appropriate: {overscan_appropriate}")
        video_signal_type = data[idx]; idx += 1
        print(f"  video_signal_type_present: {video_signal_type}")
        if video_signal_type:
            vst = 0
            for i in range(3):
                vst = (vst << 1) | data[idx]
                idx += 1
            full_range = data[idx]; idx += 1
            color_desc = data[idx]; idx += 1
            print(f"    video_format: {vst}  video_full_range: {full_range}  colour_description: {color_desc}")
            if color_desc:
                cp = ctc = cr = 0
                for i in range(8):
                    cp = (cp << 1) | data[idx]
                    idx += 1
                for i in range(8):
                    ctc = (ctc << 1) | data[idx]
                    idx += 1
                for i in range(8):
                    cr = (cr << 1) | data[idx]
                    idx += 1
                print(f"    colour_primaries: {cp}  transfer: {ctc}  matrix_coefficients: {cr}")
        chroma_loc = data[idx]; idx += 1
        print(f"  chroma_loc_info_present: {chroma_loc}")
        if chroma_loc:
            tf, bf = 0, 0
            for i in range(2 + 1):
                pass
            # chroma_sample_loc_type_top_field / bottom
            t0, idx = parse_ue(data, idx)
            b0, idx = parse_ue(data, idx)
            print(f"    chroma_sample_loc: top={t0} bottom={b0}")
        timing = data[idx]; idx += 1
        print(f"  timing_info_present: {timing}")
        if timing:
            nu_tick = fixed = 0
            for i in range(32):
                nu_tick = (nu_tick << 1) | data[idx]
                idx += 1
            for i in range(32):
                fixed = (fixed << 1) | data[idx]
                idx += 1
            pix_tick = 0
            for i in range(32):
                pix_tick = (pix_tick << 1) | data[idx]
                idx += 1
            print(f"    num_units_in_tick: {nu_tick}  time_scale: {pix_tick}  fixed_frame_rate: {fixed}")
        low_delay = data[idx]; idx += 1
        print(f"  low_delay_hrd: {low_delay}")


decode_sps(SPS_B64, "SPS (served to DVR)")
print()
decode_sps(PPS_B64, "PPS")