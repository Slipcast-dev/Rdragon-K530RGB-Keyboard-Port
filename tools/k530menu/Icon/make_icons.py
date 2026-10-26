#!/usr/bin/env python3
"""Сборка иконок K530Lighting из Icon/source/dragon-emblem.png: AppIcon.icns и StatusIcon@2x.png (шаблонный значок для строки меню).
Требуется macOS: sips (масштаб), iconutil. Сторонние пакеты не нужны."""
import os, struct, subprocess, sys, zlib, shutil

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", ".build", "icons")

def run(*a): subprocess.run(a, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

def read_png(path):
    """Читает PNG 8 бит (RGB или RGBA, без чересстрочности) и возвращает (w, h, строки RGBA)."""
    d = open(path, "rb").read(); i = 8; idat = b""
    while i < len(d):
        n, t = struct.unpack(">I4s", d[i:i+8]); c = d[i+8:i+8+n]
        if t == b"IHDR": w, h, bd, ct, _, _, il = struct.unpack(">IIBBBBB", c)
        if t == b"IDAT": idat += c
        i += 12 + n
    assert bd == 8 and ct in (2, 6) and il == 0, "ожидается RGB/RGBA 8 бит без чересстрочности"
    bpp = 3 if ct == 2 else 4
    raw = zlib.decompress(idat); stride = w * bpp; rows = []; prev = bytearray(stride); p = 0
    for _ in range(h):
        f = raw[p]; line = bytearray(raw[p+1:p+1+stride]); p += 1 + stride
        for x in range(stride):
            a = line[x-bpp] if x >= bpp else 0; b = prev[x]; c = prev[x-bpp] if x >= bpp else 0
            if f == 1: line[x] = (line[x] + a) & 255
            elif f == 2: line[x] = (line[x] + b) & 255
            elif f == 3: line[x] = (line[x] + ((a + b) >> 1)) & 255
            elif f == 4:
                pa, pb, pc = abs(b-c), abs(a-c), abs(a+b-2*c)
                line[x] = (line[x] + (a if pa <= pb and pa <= pc else (b if pb <= pc else c))) & 255
        prev = line
        if bpp == 3:
            r = bytearray(w * 4)
            for x in range(w): r[x*4:x*4+3] = line[x*3:x*3+3]; r[x*4+3] = 255
            line = r
        rows.append(line)
    return w, h, rows

def write_png(path, w, h, rows):
    def chunk(t, c):
        return struct.pack(">I", len(c)) + t + c + struct.pack(">I", zlib.crc32(t + c) & 0xffffffff)
    body = b"".join(b"\x00" + bytes(r) for r in rows)
    open(path, "wb").write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
                           + chunk(b"IDAT", zlib.compress(body, 9)) + chunk(b"IEND", b""))

def render(svg, size, name):
    run("qlmanage", "-t", "-s", str(size), "-o", OUT, os.path.join(HERE, svg))
    return os.path.join(OUT, svg + ".png")

def sdf_round_rect(px, py, cx=512.0, cy=512.0, half=412.0, r=185.0):
    """Расстояние до скруглённого квадрата стандартной иконки macOS (824×824 на холсте 1024; <0 — внутри)."""
    qx = abs(px - cx) - (half - r); qy = abs(py - cy) - (half - r)
    return (max(qx, 0) ** 2 + max(qy, 0) ** 2) ** 0.5 + min(max(qx, qy), 0) - r

def scale_png(src, size, dst):
    run("sips", "-z", str(size), str(size), src, "--out", dst)

def main():
    shutil.rmtree(OUT, ignore_errors=True); os.makedirs(OUT)
    emblem_src = os.path.join(HERE, "source", "dragon-emblem.png")
    # --- иконка приложения: белый скруглённый квадрат стандартного размера macOS (824 из 1024) с мягкой тенью,
    #     эмблема вписана «умножением» (белый фон картинки сливается с плиткой)
    S = 840
    emb = os.path.join(OUT, "emblem_scaled.png"); scale_png(emblem_src, S, emb)
    _, _, erows = read_png(emb); off = (1024 - S) // 2
    rows = []
    for y in range(1024):
        row = bytearray(1024 * 4)
        for x in range(1024):
            d = sdf_round_rect(x + .5, y + .5)
            cover = min(max(0.5 - d, 0.0), 1.0)
            ds = sdf_round_rect(x + .5, y + .5 - 12)          # тень смещена вниз
            sh = 0.30 * max(0.0, 1.0 - max(ds, 0.0) / 30.0) ** 2
            o = x * 4
            if cover <= 0.0 and sh <= 0.002:
                continue
            # плитка: тёплый белый с лёгким вертикальным градиентом
            g = 1.0 - 0.045 * (y - 100) / 824.0
            br, bg, bb = 255 * g, 252 * g, 248 * g
            ex, ey = x - off, y - off
            if 0 <= ex < S and 0 <= ey < S:
                e = erows[ey]; k = ex * 4
                br, bg, bb = br * e[k] / 255.0, bg * e[k+1] / 255.0, bb * e[k+2] / 255.0
            # плитка поверх тени
            a_out = cover + sh * (1 - cover)
            if a_out <= 0: continue
            r_ = (br * cover + 0 * sh * (1 - cover)) / a_out
            g_ = (bg * cover) / a_out
            b_ = (bb * cover) / a_out
            row[o:o+4] = bytes((round(min(r_, 255)), round(min(g_, 255)), round(min(b_, 255)), round(a_out * 255)))
        rows.append(row)
    big = os.path.join(OUT, "app_1024.png"); write_png(big, 1024, 1024, rows)
    iconset = os.path.join(OUT, "AppIcon.iconset"); os.makedirs(iconset)
    for base in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            px = base * scale
            name = f"icon_{base}x{base}" + ("@2x" if scale == 2 else "") + ".png"
            run("sips", "-z", str(px), str(px), big, "--out", os.path.join(iconset, name))
    run("iconutil", "-c", "icns", iconset, "-o", os.path.join(OUT, "AppIcon.icns"))
    # --- значок строки меню: голова и шея дракона из эмблемы, чёрный шаблон; прозрачность = «красность» пикселя
    crop = os.path.join(OUT, "head_crop.png")
    run("sips", "-c", "500", "500", "--cropOffset", "100", "110", emblem_src, "--out", crop)
    head = os.path.join(OUT, "head_144.png"); scale_png(crop, 144, head)
    w, h, hrows = read_png(head)
    for y in range(h):
        row = hrows[y]
        for x in range(w):
            o = x * 4; lowest = min(row[o], row[o+1], row[o+2])
            # вне круга внутри рамки (радиус 255 из 740 вокруг центра эмблемы) — прозрачно, чтобы не попал орнамент
            inside = ((x - 74.9) ** 2 + (y - 77.8) ** 2) ** 0.5 <= 73.4
            row[o:o+4] = bytes((0, 0, 0, max(0, min(255, round((255 - lowest) * 1.15))) if inside else 0))
    write_png(os.path.join(OUT, "status_144.png"), w, h, hrows)
    run("sips", "-z", "36", "36", os.path.join(OUT, "status_144.png"), "--out", os.path.join(OUT, "StatusIcon@2x.png"))
    run("sips", "-z", "18", "18", os.path.join(OUT, "status_144.png"), "--out", os.path.join(OUT, "StatusIcon.png"))
    print("Готово:", OUT)

if __name__ == "__main__":
    main()
