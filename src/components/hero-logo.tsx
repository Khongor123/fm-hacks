"use client";

import Image from "next/image";
import { useEffect, useRef } from "react";
import type { KeyboardEvent, PointerEvent } from "react";
import { Countdown } from "@/components/countdown";

const cornerRadius = 30;
const cornerDepth = 28;
const cornerSteps = 12;
const cornerStripWidth = 2 * cornerRadius * Math.sin(Math.PI / (4 * cornerSteps)) + 1.5;
const corners = [
  { name: "top-left", start: 180 },
  { name: "top-right", start: 270 },
  { name: "bottom-right", start: 0 },
  { name: "bottom-left", start: 90 },
] as const;

const cornerSegments = corners.flatMap(({ name, start }) =>
  Array.from({ length: cornerSteps + 1 }, (_, index) => {
    const angle = start + (index * 90) / cornerSteps;
    const radians = (angle * Math.PI) / 180;
    const x = cornerRadius * Math.cos(radians) - cornerStripWidth / 2;
    const y = cornerRadius * Math.sin(radians) - cornerDepth / 2;
    const offset = (value: number) => `${value < 0 ? "-" : "+"} ${Math.abs(value).toFixed(2)}px`;

    return {
      key: `${name}-${index}`,
      name,
      style: {
        left: `calc(var(--corner-x) ${offset(x)})`,
        top: `calc(var(--corner-y) ${offset(y)})`,
        width: `${cornerStripWidth}px`,
        transform: `rotateZ(${angle + 90}deg) rotateX(90deg)`,
      },
    };
  }),
);

export function HeroLogo() {
  const blockRef = useRef<HTMLDivElement>(null);
  const rotation = useRef({ x: -8, y: 0 });
  const drag = useRef<{ pointerId: number; x: number; y: number } | null>(null);
  const returnAnimation = useRef<{
    start: number;
    fromX: number;
    fromY: number;
    toX: number;
    toY: number;
  } | null>(null);

  function renderRotation() {
    if (blockRef.current) {
      blockRef.current.style.transform = `rotateX(${rotation.current.x}deg) rotateY(${rotation.current.y}deg)`;
    }
  }

  useEffect(() => {
    const block = blockRef.current;
    if (!block) return;

    const motionPreference = window.matchMedia("(prefers-reduced-motion: reduce)");
    let visible = true;
    let frame = 0;
    let previousTime = 0;

    const observer = new IntersectionObserver(([entry]) => {
      visible = entry.isIntersecting;
      previousTime = 0;
    });
    observer.observe(block);

    function tick(time: number) {
      const returning = returnAnimation.current;
      if (returning) {
        const progress = Math.min((time - returning.start) / 850, 1);
        const eased = 1 - (1 - progress) ** 3;
        rotation.current.x = returning.fromX + (returning.toX - returning.fromX) * eased;
        rotation.current.y = returning.fromY + (returning.toY - returning.fromY) * eased;
        if (progress === 1) {
          rotation.current = { x: -8, y: 0 };
          returnAnimation.current = null;
        }
        renderRotation();
        previousTime = 0;
      } else if (visible && document.visibilityState === "visible" && !motionPreference.matches && !drag.current) {
        if (previousTime) {
          rotation.current.y += Math.min(time - previousTime, 100) * 0.02;
          renderRotation();
        }
        previousTime = time;
      } else {
        previousTime = 0;
      }
      frame = window.requestAnimationFrame(tick);
    }

    frame = window.requestAnimationFrame(tick);
    return () => {
      observer.disconnect();
      window.cancelAnimationFrame(frame);
    };
  }, []);

  function startDrag(event: PointerEvent<HTMLDivElement>) {
    if (event.button !== 0 || drag.current) return;
    event.preventDefault();
    returnAnimation.current = null;
    event.currentTarget.setPointerCapture(event.pointerId);
    event.currentTarget.classList.add("is-dragging");
    drag.current = { pointerId: event.pointerId, x: event.clientX, y: event.clientY };
  }

  function moveDrag(event: PointerEvent<HTMLDivElement>) {
    const current = drag.current;
    if (!current || current.pointerId !== event.pointerId) return;
    rotation.current.y += ((event.clientX - current.x) / event.currentTarget.clientWidth) * 360;
    rotation.current.x -= ((event.clientY - current.y) / event.currentTarget.clientHeight) * 360;
    current.x = event.clientX;
    current.y = event.clientY;
    renderRotation();
  }

  function stopDrag(event: PointerEvent<HTMLDivElement>) {
    if (drag.current?.pointerId !== event.pointerId) return;
    drag.current = null;
    event.currentTarget.classList.remove("is-dragging");
    if (event.currentTarget.hasPointerCapture(event.pointerId)) {
      event.currentTarget.releasePointerCapture(event.pointerId);
    }
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      rotation.current = { x: -8, y: 0 };
      renderRotation();
      return;
    }
    returnAnimation.current = {
      start: performance.now(),
      fromX: rotation.current.x,
      fromY: rotation.current.y,
      toX: -8 + Math.round((rotation.current.x + 8) / 360) * 360,
      toY: Math.round(rotation.current.y / 360) * 360,
    };
  }

  function rotateWithKeyboard(event: KeyboardEvent<HTMLDivElement>) {
    const step = 10;
    switch (event.key) {
      case "ArrowLeft": rotation.current.y -= step; break;
      case "ArrowRight": rotation.current.y += step; break;
      case "ArrowUp": rotation.current.x += step; break;
      case "ArrowDown": rotation.current.x -= step; break;
      default: return;
    }
    event.preventDefault();
    returnAnimation.current = null;
    renderRotation();
  }

  return (
    <div className="hero-logo-scene">
      <div className="hero-logo-ground-shadow" aria-hidden="true" />
      <div
        ref={blockRef}
        className="hero-logo-block"
        role="group"
        aria-label="Rotating F&MHacks logo and countdown. Drag to turn it in any direction; it returns to the front when released. Arrow keys also rotate it."
        tabIndex={0}
        onPointerDown={startDrag}
        onPointerMove={moveDrag}
        onPointerUp={stopDrag}
        onPointerCancel={stopDrag}
        onKeyDown={rotateWithKeyboard}
      >
        <span className="hero-logo-side hero-logo-side-left" aria-hidden="true" />
        <span className="hero-logo-side hero-logo-side-right" aria-hidden="true" />
        <span className="hero-logo-side hero-logo-side-top" aria-hidden="true" />
        <span className="hero-logo-side hero-logo-side-bottom" aria-hidden="true" />
        {cornerSegments.map((segment) => (
          <span
            className={`hero-logo-corner hero-logo-corner-${segment.name}`}
            style={segment.style}
            aria-hidden="true"
            key={segment.key}
          />
        ))}
        <div className="hero-logo-face hero-logo-back" aria-hidden="true">
          <Image className="hero-logo-image" src="/hero-logo-badge.webp" alt="" width={1000} height={1003} draggable={false} />
          <span className="hero-logo-back-caption">F&amp;MHACKS / 26</span>
        </div>
        <div className="hero-logo-face hero-logo-front">
          <Image
            className="hero-logo-image"
            src="/hero-logo-badge.webp"
            alt="F&MHacks pixel horse logo"
            width={1000}
            height={1003}
            priority
            draggable={false}
          />
          <Countdown />
        </div>
      </div>
    </div>
  );
}
