import os
import subprocess
import shutil
from PIL import Image, ImageDraw, ImageFilter
import numpy as np

def create_keylite_icon():
    base_dir = os.path.dirname(os.path.abspath(__file__))
    res_dir = os.path.join(base_dir, 'Resources')
    os.makedirs(res_dir, exist_ok=True)
    
    # 优先使用 Resources 目录下的母图，若不存在则使用同名备用图
    user_img_path = os.path.join(res_dir, 'icon_1024.png')
    if not os.path.exists(user_img_path):
        alt_path = os.path.join(res_dir, 'icon.png')
        if os.path.exists(alt_path):
            user_img_path = alt_path
        else:
            print(f"Error: {user_img_path} not found")
            return
        
    img = Image.open(user_img_path).convert('RGBA')
    
    # 裁剪中央圆角图标主体 (裁掉外围暗黑背景)
    box = (160, 142, 863, 861)
    cropped = img.crop(box)
    w, h = cropped.size
    
    # 4倍超采样高质量抗锯齿圆角遮罩
    scale = 4
    mask_hires = Image.new('L', (w * scale, h * scale), 0)
    draw = ImageDraw.Draw(mask_hires)
    radius = int(w * 0.235 * scale)
    draw.rounded_rectangle([0, 0, w * scale - 1, h * scale - 1], radius=radius, fill=255)
    mask = mask_hires.resize((w, h), Image.Resampling.LANCZOS)
    cropped.putalpha(mask)
    
    # 标准 macOS 图标画布: 1024x1024 画布，主体 824x824
    canvas_size = 1024
    body_size = 824
    offset = (canvas_size - body_size) // 2
    
    icon_body = cropped.resize((body_size, body_size), Image.Resampling.LANCZOS)
    body_mask = mask.resize((body_size, body_size), Image.Resampling.LANCZOS)
    
    # macOS 规范拟真阴影
    shadow_mask = Image.new('L', (canvas_size, canvas_size), 0)
    shadow_mask.paste(body_mask, (offset, offset + 12))
    shadow_mask = shadow_mask.filter(ImageFilter.GaussianBlur(16))
    
    shadow_arr = np.array(shadow_mask).astype(np.float32) * 0.35
    shadow_img = Image.fromarray(shadow_arr.astype(np.uint8))
    
    shadow = Image.new('RGBA', (canvas_size, canvas_size), (0, 0, 0, 0))
    black = Image.new('RGBA', (canvas_size, canvas_size), (0, 0, 0, 255))
    shadow.paste(black, (0, 0), shadow_img)
    
    canvas = Image.new('RGBA', (canvas_size, canvas_size), (0, 0, 0, 0))
    canvas = Image.alpha_composite(canvas, shadow)
    canvas.paste(icon_body, (offset, offset), icon_body)
    
    png_path = os.path.join(res_dir, 'icon_1024.png')
    canvas.save(png_path)
    
    # 生成 icns
    iconset_dir = os.path.join(res_dir, 'icon.iconset')
    if os.path.exists(iconset_dir):
        shutil.rmtree(iconset_dir)
    os.makedirs(iconset_dir, exist_ok=True)
    
    specs = [
        ('icon_16x16.png', 16),
        ('icon_16x16@2x.png', 32),
        ('icon_32x32.png', 32),
        ('icon_32x32@2x.png', 64),
        ('icon_128x128.png', 128),
        ('icon_128x128@2x.png', 256),
        ('icon_256x256.png', 256),
        ('icon_256x256@2x.png', 512),
        ('icon_512x512.png', 512),
        ('icon_512x512@2x.png', 1024)
    ]
    
    for filename, size in specs:
        resized = canvas.resize((size, size), Image.Resampling.LANCZOS)
        resized.save(os.path.join(iconset_dir, filename))
        
    icns_path = os.path.join(res_dir, 'icon.icns')
    if os.path.exists(icns_path):
        os.remove(icns_path)
        
    subprocess.run(['iconutil', '-c', 'icns', iconset_dir, '-o', icns_path], check=True)
    print("✅ 成功生成全新定制应用图标:", icns_path)

if __name__ == '__main__':
    create_keylite_icon()
