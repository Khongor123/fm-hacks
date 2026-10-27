import fs from "node:fs/promises";
import path from "node:path";
import sharp from "sharp";

const [kind, inputDir, outputPrefix, countArg, sizeArg] = process.argv.slice(2);
const frameCount = Number(countArg);
const size = Number(sizeArg);
if (!["echo", "instax"].includes(kind) || !inputDir || !outputPrefix || !frameCount || !size) {
  throw new Error("Usage: node build-spin-atlas.mjs echo|instax input-dir output-prefix frame-count frame-size");
}

const columns = 8;
const framesPerSheet = 32;
const sheets = Math.ceil(frameCount / framesPerSheet);
const outputDir = path.dirname(outputPrefix);
await fs.mkdir(outputDir, { recursive: true });

function alphaMask(data, width, height) {
  const pixels = width * height;
  const rgba = Buffer.alloc(pixels * 4);
  const foreground = new Uint8Array(pixels);
  if (kind === "echo") {
    // The dark speaker separates cleanly from the white set. Keeping only its
    // dark silhouette also drops the light fringe baked into the source video.
    for (let index = 0; index < pixels; index++) {
      const offset = index * 3;
      const brightness = (data[offset] + data[offset + 1] + data[offset + 2]) / 3;
      foreground[index] = brightness < 120 ? 1 : 0;
    }
  } else {
    const background = new Uint8Array(pixels);
    const queue = new Int32Array(pixels);
    let head = 0;
    let tail = 0;
    const isWhite = (index) => {
      const offset = index * 3;
      const r = data[offset];
      const g = data[offset + 1];
      const b = data[offset + 2];
      return Math.min(r, g, b) >= 242 && Math.max(r, g, b) - Math.min(r, g, b) <= 12;
    };
    const add = (index) => {
      if (background[index] || !isWhite(index)) return;
      background[index] = 1;
      queue[tail++] = index;
    };
    for (let x = 0; x < width; x++) {
      add(x);
      add((height - 1) * width + x);
    }
    for (let y = 0; y < height; y++) {
      add(y * width);
      add(y * width + width - 1);
    }
    while (head < tail) {
      const index = queue[head++];
      const x = index % width;
      if (x > 0) add(index - 1);
      if (x < width - 1) add(index + 1);
      if (index >= width) add(index - width);
      if (index < pixels - width) add(index + width);
    }
    for (let index = 0; index < pixels; index++) foreground[index] = background[index] ? 0 : 1;
  }

  // Both products are solid across each scanline. Closing the line restores
  // pale camera details that a white-background flood would otherwise erase.
  for (let y = 0; y < height; y++) {
    let left = width;
    let right = -1;
    const row = y * width;
    for (let x = 0; x < width; x++) {
      if (foreground[row + x]) {
        left = Math.min(left, x);
        right = x;
      }
    }
    if (right < left) continue;
    for (let x = left; x <= right; x++) {
      const index = y * width + x;
      const offset = index * 3;
      let alpha = Math.min(1, (x - left + 0.5) / 1.5, (right - x + 0.5) / 1.5);
      if (kind === "echo") {
        // The gray floor reflection starts below the speaker's blue light ring.
        alpha *= Math.max(0, Math.min(1, (0.865 - y / height) / 0.006));
      } else {
        // Fade the residual floor shadow below the camera body.
        alpha *= Math.max(0, Math.min(1, (0.918 - y / height) / 0.035));
      }

      rgba[index * 4] = data[offset];
      rgba[index * 4 + 1] = data[offset + 1];
      rgba[index * 4 + 2] = data[offset + 2];
      rgba[index * 4 + 3] = Math.round(alpha * 255);
    }
  }
  return rgba;
}

for (let sheet = 0; sheet < sheets; sheet++) {
  const composites = [];
  const first = sheet * framesPerSheet;
  const last = Math.min(first + framesPerSheet, frameCount);
  for (let index = first; index < last; index++) {
    const file = path.join(inputDir, `frame-${String(index).padStart(3, "0")}.png`);
    const { data, info } = await sharp(file).resize(size, size).removeAlpha().raw().toBuffer({ resolveWithObject: true });
    const rgba = alphaMask(data, info.width, info.height);
    const frame = sharp(rgba, { raw: { width: size, height: size, channels: 4 } });
    if (index === 0) {
      await frame.clone().png().toFile(`${outputPrefix}-poster.png`);
    }
    composites.push({ input: await frame.png().toBuffer(), left: ((index - first) % columns) * size, top: Math.floor((index - first) / columns) * size });
  }
  const output = `${outputPrefix}-${sheet}.webp`;
  await sharp({ create: { width: columns * size, height: 4 * size, channels: 4, background: { r: 0, g: 0, b: 0, alpha: 0 } } })
    .composite(composites)
    .webp({ quality: 86, effort: 6 })
    .toFile(output);
  console.log(output);
}
