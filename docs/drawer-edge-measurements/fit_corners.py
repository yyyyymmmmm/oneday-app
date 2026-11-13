#!/usr/bin/env python3
"""
抽屉边缘互补几何量测（2026-11-13，fix/drawer-edge-geometry，
DESIGN §202）

方法沿 §182.2 文档化口径（原 measure_corners_v2.py 文件已不在
仓内，按 DESIGN-V4 §182.2 记载的方法复写）：沿前景页左边界逐
行采样前景/底层亮度突变点（平滑后梯度峰值），对角部弧段做最
小二乘圆拟合（Kasa），两遍拟合、第二遍按残差剔离群点。

本轮实证的三条抗污染纪律：
- 平滑必须用边缘填充：np.convolve 的 mode='same' 是零填充，
  会在窗口两端凭空造假陡升边，梯度峰恒落在窗口左缘（首三轮
  拟合全灭于此）；
- 接缝 x0 取中段多行梯度峰的中位数（个别行被卡内文字抢峰）；
- 弧段取拟合域而非全高扫描：顶弧 y in [40,190]（避状态栏图标
  带）；底弧只取弧尾净段 [H-68,H-1]（上段被底部丸件遮挡，
  丸件假边界成串时残差剔除救不回全域拟合，实证）。

用法：python3 fit_corners.py <image.jpg> <label>
输出：<label>_fit.json ＋四角裁切图（原生分辨率）。
倍率：1206x2622 = 402pt 逻辑宽 @3.0；对照列 @3.07（§182.2 旧
折算 393pt）。
拟合结论（ref_muse，四组独立估计）：半径 156-174px（顶弧主
拟合 158.5px/残差 1.47、底弧合并拟合 168.5px/残差 0.79）、
inset 1.3-2.7pt、r+inset 54-59pt——与社区设备角半径表
（55-62pt）吻合。出货定值取池化中心：半径 54.5pt、纵向
inset 2.0pt（r+inset=56.5pt）。
"""
import json
import sys

import numpy as np
from PIL import Image


def load_lum(path):
    img = Image.open(path).convert("RGB")
    a = np.asarray(img).astype(np.float64)
    return 0.2126 * a[:, :, 0] + 0.7152 * a[:, :, 1] + 0.0722 * a[:, :, 2]


def smooth1d(v, k=9):
    if k <= 1:
        return v.copy()
    pad = k // 2
    return np.convolve(
        np.pad(v, pad, mode="edge"), np.ones(k) / k, mode="valid"
    )


def edge_x(lum, y, x_lo, x_hi):
    row = smooth1d(lum[y, x_lo:x_hi], 9)
    g = np.gradient(row)
    return x_lo + int(np.argmax(g)) + 0.5


def kasa_circle(xs, ys):
    A = np.column_stack([xs, ys, np.ones_like(xs)])
    b = -(xs ** 2 + ys ** 2)
    sol, *_ = np.linalg.lstsq(A, b, rcond=None)
    D, E, F = float(sol[0]), float(sol[1]), float(sol[2])
    cx, cy = -D / 2, -E / 2
    r = np.sqrt(max(cx * cx + cy * cy - F, 0.0))
    resid = np.abs(np.sqrt((xs - cx) ** 2 + (ys - cy) ** 2) - r)
    return cx, cy, r, resid


def robust_fit(xs, ys):
    cx, cy, r, resid = kasa_circle(xs, ys)
    keep = resid <= max(2.5 * np.median(resid), 2.0)
    if 10 <= keep.sum() < len(xs):
        cx, cy, r, resid = kasa_circle(xs[keep], ys[keep])
        return cx, cy, r, resid, int(keep.sum()), int(len(xs))
    return cx, cy, r, resid, int(len(xs)), int(len(xs))


def arc_points(lum, x0, y_lo, y_hi, step, dx_max):
    pts = []
    for y in range(y_lo, y_hi, step):
        x = edge_x(lum, y, int(x0) - 40, lum.shape[1] - 5)
        if 3 < x - x0 < dx_max:
            pts.append((x, float(y)))
    return pts


def main():
    path, label = sys.argv[1], sys.argv[2]
    lum = load_lum(path)
    H, W = lum.shape
    out = {"image": path, "size_px": [W, H]}

    xs_mid = [edge_x(lum, y, 830, 1150) for y in range(1000, 1700, 25)]
    x0 = float(np.median(xs_mid))
    out["seam_x_px"] = x0

    fits = {}
    pts_t = arc_points(lum, x0, 40, 192, 4, 200)
    if len(pts_t) >= 10:
        xs = np.array([p[0] for p in pts_t])
        ys = np.array([p[1] for p in pts_t])
        cx, cy, r, resid, kept, total = robust_fit(xs, ys)
        fits["top_left"] = {
            "n_total": total, "n_kept": kept, "cx": cx, "cy": cy,
            "r_px": r, "resid_mean_px": float(resid.mean()),
            "resid_max_px": float(resid.max()),
            "implied_left_edge_px": cx - r,
            "implied_top_edge_px": cy - r,
        }
    # 底弧取点（实证定版）：弧尾净段 y in [H-68, H-1] 步长 2
    # ——上方弧段被抽屉底部浮丸件（composer/底栏）遮挡，其假边
    # 界 dx 160-218 恒定成串，先到先得的梯度峰全落在丸件上；
    # 净段内稳健拟合残差 0.79px。
    pts_b = arc_points(lum, x0, H - 68, H - 1, 2, 220)
    if len(pts_b) >= 10:
        xs = np.array([p[0] for p in pts_b])
        ys = np.array([p[1] for p in pts_b])
        cx, cy, r, resid, kept, total = robust_fit(xs, ys)
        fits["bottom_left"] = {
            "n_total": total, "n_kept": kept, "cx": cx, "cy": cy,
            "r_px": r, "resid_mean_px": float(resid.mean()),
            "resid_max_px": float(resid.max()),
            "implied_left_edge_px": cx - r,
            "implied_bottom_edge_px": cy + r,
        }
    out["arc_fits"] = fits

    for scale, name in ((3.0, "pt@3.0_w402"), (1206 / 393.0, "pt@3.07_w393")):
        d = {"seam_x": x0 / scale}
        if "top_left" in fits:
            f = fits["top_left"]
            d["top_r"] = f["r_px"] / scale
            d["top_inset"] = f["implied_top_edge_px"] / scale
            d["top_r_plus_inset"] = (f["r_px"] + f["implied_top_edge_px"]) / scale
        if "bottom_left" in fits:
            f = fits["bottom_left"]
            d["bottom_r"] = f["r_px"] / scale
            d["bottom_inset"] = (H - f["implied_bottom_edge_px"]) / scale
            d["bottom_r_plus_inset"] = (
                f["r_px"] + (H - f["implied_bottom_edge_px"])) / scale
        out[name] = d

    with open(f"{label}_fit.json", "w") as fh:
        json.dump(out, fh, indent=1, ensure_ascii=False)
    print(json.dumps(out, indent=1, ensure_ascii=False))

    img = Image.open(path)
    cw = 460
    crops = {
        "TL": (int(x0) - 170, 0, int(x0) + 310, cw),
        "BL": (int(x0) - 170, H - cw, int(x0) + 310, H),
        "TR": (W - cw, 0, W, cw),
        "BR": (W - cw, H - cw, W, H),
    }
    for nm, box in crops.items():
        img.crop(box).save(f"{label}_corner_{nm}.png")


if __name__ == "__main__":
    main()
