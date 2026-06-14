const sharp = require('sharp');
const fs = require('fs');
const path = require('path');

const scssDir = path.join(__dirname, 'scss');

// App Store sizes to generate
const batches = {
  'iphone_65': { w: 1242, h: 2688, label: 'iPhone 6.5"' },
  'iphone_67': { w: 1284, h: 2778, label: 'iPhone 6.7"' },
  'ipad_13':  { w: 2064, h: 2752, label: 'iPad 13"' },
};

async function resizeAll() {
  const files = fs.readdirSync(scssDir).filter(f => /\.(jpg|jpeg|png)$/i.test(f));
  
  for (const [dir, size] of Object.entries(batches)) {
    const outDir = path.join(scssDir, dir);
    fs.mkdirSync(outDir, { recursive: true });
  }

  for (const file of files) {
    const input = path.join(scssDir, file);
    for (const [dir, size] of Object.entries(batches)) {
      const outDir = path.join(scssDir, dir);
      const outName = file.replace(/\.(jpg|jpeg|png)$/i, `.${size.w}x${size.h}.jpg`);
      const output = path.join(outDir, outName);

      await sharp(input)
        .resize(size.w, size.h, { fit: 'fill' })
        .jpeg({ quality: 95 })
        .toFile(output);

      const img = await sharp(output).metadata();
      console.log(`${size.label}: ${img.width}x${img.height} → ${output}`);
    }
  }
  console.log('\nDone!');
}

resizeAll().catch(e => { console.error(e); process.exit(1); });
