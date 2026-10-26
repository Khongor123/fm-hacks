"use client";

import { useEffect, useRef } from "react";

type ProductSpinProps = {
  src: string;
  poster: string;
  label: string;
  className?: string;
};

export function ProductSpin({ src, poster, label, className = "" }: ProductSpinProps) {
  const containerRef = useRef<HTMLDivElement>(null);
  const videoRef = useRef<HTMLVideoElement>(null);

  useEffect(() => {
    const container = containerRef.current;
    const video = videoRef.current;
    if (!container || !video) return;

    const motion = window.matchMedia("(prefers-reduced-motion: reduce)");
    let visible = false;
    let dragging = false;
    let startX = 0;
    let startTime = 0;

    const syncPlayback = () => {
      if (visible && !dragging && !motion.matches && !document.hidden) {
        video.playbackRate = 0.35;
        void video.play().catch(() => {});
      } else {
        video.pause();
      }
    };
    const observer = new IntersectionObserver(([entry]) => {
      visible = entry.isIntersecting;
      syncPlayback();
    }, { threshold: 0.05 });
    observer.observe(container);

    const seek = (time: number) => {
      if (!Number.isFinite(video.duration) || video.duration <= 0) return;
      video.currentTime = ((time % video.duration) + video.duration) % video.duration;
    };
    const pointerDown = (event: PointerEvent) => {
      if (!Number.isFinite(video.duration)) return;
      dragging = true;
      startX = event.clientX;
      startTime = video.currentTime;
      video.pause();
      container.setPointerCapture(event.pointerId);
      container.classList.add("is-dragging");
    };
    const pointerMove = (event: PointerEvent) => {
      if (!dragging) return;
      seek(startTime + (event.clientX - startX) / container.clientWidth * video.duration);
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
      video.pause();
      seek(video.currentTime + (event.key === "ArrowRight" ? 1 : -1) * video.duration / 36);
      if (!motion.matches) syncPlayback();
    };

    container.addEventListener("pointerdown", pointerDown);
    container.addEventListener("pointermove", pointerMove);
    container.addEventListener("pointerup", pointerEnd);
    container.addEventListener("pointercancel", pointerEnd);
    container.addEventListener("keydown", keyDown);
    video.addEventListener("loadedmetadata", syncPlayback);
    motion.addEventListener("change", syncPlayback);
    document.addEventListener("visibilitychange", syncPlayback);

    return () => {
      video.pause();
      observer.disconnect();
      container.removeEventListener("pointerdown", pointerDown);
      container.removeEventListener("pointermove", pointerMove);
      container.removeEventListener("pointerup", pointerEnd);
      container.removeEventListener("pointercancel", pointerEnd);
      container.removeEventListener("keydown", keyDown);
      video.removeEventListener("loadedmetadata", syncPlayback);
      motion.removeEventListener("change", syncPlayback);
      document.removeEventListener("visibilitychange", syncPlayback);
    };
  }, []);

  return (
    <div
      ref={containerRef}
      className={`prize-model product-spin ${className}`.trim()}
      role="img"
      tabIndex={0}
      aria-label={`360 degree view of the ${label}. Drag left or right, or use the arrow keys, to rotate it.`}
    >
      <video
        ref={videoRef}
        src={src}
        poster={poster}
        muted
        loop
        playsInline
        preload="metadata"
        aria-hidden="true"
      />
    </div>
  );
}
