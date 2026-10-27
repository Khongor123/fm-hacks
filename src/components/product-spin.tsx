"use client";

import { useEffect, useRef } from "react";

type ProductSpinProps = {
  atlasPrefix: string;
  poster: string;
  label: string;
  frameCount: number;
  frameSize: number;
  durationMs: number;
};

const FRAMES_PER_SHEET = 32;
const COLUMNS = 8;

export function ProductSpin({ atlasPrefix, poster, label, frameCount, frameSize, durationMs }: ProductSpinProps) {
  const containerRef = useRef<HTMLDivElement>(null);
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const posterRef = useRef<HTMLImageElement>(null);

  useEffect(() => {
    const container = containerRef.current;
    const canvas = canvasRef.current;
    const posterImage = posterRef.current;
    const context = canvas?.getContext("2d");
    if (!container || !canvas || !posterImage || !context) return;

    const motion = window.matchMedia("(prefers-reduced-motion: reduce)");
    const sheets: HTMLImageElement[] = [];
    const sheetCount = Math.ceil(frameCount / FRAMES_PER_SHEET);
    let loaded = 0;
    let startedLoading = false;
    let visible = false;
    let dragging = false;
    let startX = 0;
    let startTime = 0;
    let currentTime = 0;
    let previous = 0;
    let frame = 0;
    let lastRenderedIndex = -1;

    const draw = () => {
      if (loaded !== sheetCount) return;
      const index = Math.floor(currentTime / durationMs * frameCount) % frameCount;
      if (index === lastRenderedIndex) return;
      lastRenderedIndex = index;
      const image = sheets[Math.floor(index / FRAMES_PER_SHEET)];
      const localIndex = index % FRAMES_PER_SHEET;
      const width = container.clientWidth;
      const height = container.clientHeight;
      const size = Math.min(width, height);
      context.clearRect(0, 0, width, height);
      context.drawImage(
        image,
        (localIndex % COLUMNS) * frameSize,
        Math.floor(localIndex / COLUMNS) * frameSize,
        frameSize,
        frameSize,
        (width - size) / 2,
        (height - size) / 2,
        size,
        size,
      );
    };
    const resize = () => {
      const scale = Math.min(window.devicePixelRatio || 1, 2);
      canvas.width = Math.round(container.clientWidth * scale);
      canvas.height = Math.round(container.clientHeight * scale);
      context.setTransform(scale, 0, 0, scale, 0, 0);
      lastRenderedIndex = -1;
      draw();
    };
    const tick = (time: number) => {
      if (previous) currentTime = (currentTime + (time - previous) * 0.35) % durationMs;
      previous = time;
      draw();
      frame = requestAnimationFrame(tick);
    };
    const syncPlayback = () => {
      cancelAnimationFrame(frame);
      frame = 0;
      previous = 0;
      if (loaded === sheetCount && visible && !dragging && !motion.matches && !document.hidden) {
        frame = requestAnimationFrame(tick);
      }
    };
    const loadSheets = () => {
      if (startedLoading) return;
      startedLoading = true;
      for (let index = 0; index < sheetCount; index++) {
        const image = new Image();
        sheets.push(image);
        image.onload = () => {
          loaded++;
          if (loaded === sheetCount) {
            resize();
            canvas.style.display = "block";
            posterImage.style.display = "none";
            syncPlayback();
          }
        };
        image.src = `${atlasPrefix}-${index}.webp`;
      }
    };
    const observer = new IntersectionObserver(([entry]) => {
      visible = entry.isIntersecting;
      if (visible) loadSheets();
      syncPlayback();
    }, { threshold: 0.05 });
    observer.observe(container);

    const seek = (time: number) => {
      currentTime = ((time % durationMs) + durationMs) % durationMs;
      draw();
    };
    const pointerDown = (event: PointerEvent) => {
      if (event.button !== 0 || loaded !== sheetCount) return;
      dragging = true;
      startX = event.clientX;
      startTime = currentTime;
      container.setPointerCapture(event.pointerId);
      container.classList.add("is-dragging");
      syncPlayback();
    };
    const pointerMove = (event: PointerEvent) => {
      if (!dragging) return;
      seek(startTime + (event.clientX - startX) / container.clientWidth * durationMs);
    };
    const pointerEnd = (event: PointerEvent) => {
      if (!dragging) return;
      dragging = false;
      if (container.hasPointerCapture(event.pointerId)) container.releasePointerCapture(event.pointerId);
      container.classList.remove("is-dragging");
      syncPlayback();
    };
    const keyDown = (event: KeyboardEvent) => {
      if (event.key !== "ArrowLeft" && event.key !== "ArrowRight") return;
      event.preventDefault();
      seek(currentTime + (event.key === "ArrowRight" ? 1 : -1) * durationMs / 36);
      if (!motion.matches) syncPlayback();
    };

    const resizeObserver = new ResizeObserver(resize);
    resizeObserver.observe(container);
    container.addEventListener("pointerdown", pointerDown);
    container.addEventListener("pointermove", pointerMove);
    container.addEventListener("pointerup", pointerEnd);
    container.addEventListener("pointercancel", pointerEnd);
    container.addEventListener("keydown", keyDown);
    motion.addEventListener("change", syncPlayback);
    document.addEventListener("visibilitychange", syncPlayback);
    resize();

    return () => {
      cancelAnimationFrame(frame);
      observer.disconnect();
      resizeObserver.disconnect();
      container.removeEventListener("pointerdown", pointerDown);
      container.removeEventListener("pointermove", pointerMove);
      container.removeEventListener("pointerup", pointerEnd);
      container.removeEventListener("pointercancel", pointerEnd);
      container.removeEventListener("keydown", keyDown);
      motion.removeEventListener("change", syncPlayback);
      document.removeEventListener("visibilitychange", syncPlayback);
      for (const image of sheets) image.onload = null;
    };
  }, [atlasPrefix, durationMs, frameCount, frameSize]);

  return (
    <div
      ref={containerRef}
      className="prize-model product-spin"
      role="img"
      tabIndex={0}
      aria-label={`360 degree view of the ${label}. Drag left or right, or use the arrow keys, to rotate it.`}
    >
      <img ref={posterRef} className="product-spin-poster" src={poster} alt="" aria-hidden="true" draggable={false} />
      <canvas ref={canvasRef} className="product-spin-canvas" aria-hidden="true" />
    </div>
  );
}
