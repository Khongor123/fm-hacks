"use client";

import { useEffect, useRef } from "react";
import * as THREE from "three";

const material = (color: string, roughness = 0.72, metalness = 0) =>
  new THREE.MeshStandardMaterial({ color, roughness, metalness });

function addBox(
  group: THREE.Group,
  size: [number, number, number],
  position: [number, number, number],
  color: string,
  radius = 0.08,
  roughness = 0.7,
) {
  const [width, height, depth] = size;
  const shape = new THREE.Shape();
  const x = -width / 2;
  const y = -height / 2;
  const r = Math.min(radius, width / 2, height / 2);
  shape.moveTo(x + r, y);
  shape.lineTo(x + width - r, y);
  shape.quadraticCurveTo(x + width, y, x + width, y + r);
  shape.lineTo(x + width, y + height - r);
  shape.quadraticCurveTo(x + width, y + height, x + width - r, y + height);
  shape.lineTo(x + r, y + height);
  shape.quadraticCurveTo(x, y + height, x, y + height - r);
  shape.lineTo(x, y + r);
  shape.quadraticCurveTo(x, y, x + r, y);
  const geometry = new THREE.ExtrudeGeometry(shape, {
    depth: Math.max(0.001, depth - 0.06),
    bevelEnabled: true,
    bevelSegments: 3,
    steps: 1,
    bevelSize: Math.min(0.03, depth / 4),
    bevelThickness: Math.min(0.03, depth / 4),
    curveSegments: 8,
  });
  geometry.translate(0, 0, -depth / 2 + 0.03);
  const mesh = new THREE.Mesh(geometry, material(color, roughness));
  mesh.position.set(...position);
  group.add(mesh);
  return mesh;
}

function addCylinder(
  group: THREE.Group,
  radius: number,
  depth: number,
  position: [number, number, number],
  color: string,
  roughness = 0.5,
  metalness = 0,
) {
  const mesh = new THREE.Mesh(
    new THREE.CylinderGeometry(radius, radius, depth, 64),
    material(color, roughness, metalness),
  );
  mesh.rotation.x = Math.PI / 2;
  mesh.position.set(...position);
  group.add(mesh);
  return mesh;
}

function buildFitbit() {
  const group = new THREE.Group();
  // The Obsidian band is a broad woven loop with the tracker on its inner face.
  const canvas = document.createElement("canvas");
  canvas.width = 64;
  canvas.height = 64;
  const context = canvas.getContext("2d")!;
  context.fillStyle = "#242527";
  context.fillRect(0, 0, 64, 64);
  for (let row = -1; row < 9; row++) {
    for (let col = -1; col < 9; col++) {
      const x = col * 8 + (row % 2) * 4;
      const y = row * 8;
      context.strokeStyle = (row + col) % 2 ? "#515257" : "#35373a";
      context.lineWidth = 3;
      context.beginPath();
      context.moveTo(x, y + 7);
      context.lineTo(x + 7, y);
      context.stroke();
    }
  }
  const weave = new THREE.CanvasTexture(canvas);
  weave.colorSpace = THREE.SRGBColorSpace;
  weave.wrapS = THREE.RepeatWrapping;
  weave.wrapT = THREE.RepeatWrapping;
  const vertices: number[] = [];
  const uvs: number[] = [];
  const indices: number[] = [];
  const segments = 128;
  const width = 0.57;
  for (let i = 0; i <= segments; i++) {
    const angle = (i / segments) * Math.PI * 2;
    const cos = Math.cos(angle);
    const sin = Math.sin(angle);
    for (const y of [-width / 2, width / 2]) {
      vertices.push(cos * 1.13, y, sin * 0.74);
      vertices.push(cos * 1.08, y, sin * 0.69);
      uvs.push((i / segments) * 16, y < 0 ? 0 : 1);
      uvs.push((i / segments) * 16, y < 0 ? 0 : 1);
    }
  }
  for (let i = 0; i < segments; i++) {
    const a = i * 4;
    const b = a + 4;
    for (const [u, v, w, q] of [
      [a, b, b + 1, a + 1],
      [a + 2, a + 3, b + 3, b + 2],
      [a, a + 2, b + 2, b],
      [a + 1, b + 1, b + 3, a + 3],
    ]) indices.push(u, v, w, u, w, q);
  }
  const bandGeometry = new THREE.BufferGeometry();
  bandGeometry.setAttribute("position", new THREE.Float32BufferAttribute(vertices, 3));
  bandGeometry.setAttribute("uv", new THREE.Float32BufferAttribute(uvs, 2));
  bandGeometry.setIndex(indices);
  bandGeometry.computeVertexNormals();
  const band = new THREE.Mesh(
    bandGeometry,
    new THREE.MeshStandardMaterial({ map: weave, roughness: 1, side: THREE.DoubleSide }),
  );
  group.add(band);
  for (const y of [-width / 2, width / 2]) {
    const points = Array.from({ length: 65 }, (_, index) => {
      const angle = (index / 64) * Math.PI * 2;
      return new THREE.Vector3(Math.cos(angle) * 1.13, y, Math.sin(angle) * 0.74);
    });
    const seam = new THREE.Mesh(
      new THREE.TubeGeometry(new THREE.CatmullRomCurve3(points, true), 128, 0.018, 6, true),
      material("#151617", 1),
    );
    group.add(seam);
  }
  // The closure folds over the front of the fabric band.
  const closure = addBox(group, [0.43, 0.64, 0.07], [-0.61, 0, 0.64], "#191a1d", 0.08, 0.98);
  closure.rotation.y = -0.55;
  // Pebble shaped sensor, mounted inside the upper span of the loop.
  addBox(group, [1.32, 0.43, 0.15], [0.12, 0, -0.65], "#111214", 0.2, 0.45);
  addBox(group, [1.17, 0.34, 0.07], [0.12, 0, -0.54], "#08090b", 0.17, 0.36);
  for (const x of [-0.31, 0.53]) {
    addCylinder(group, 0.04, 0.014, [x, 0, -0.493], "#94999d", 0.28);
  }
  for (const x of [-0.09, 0.09, 0.27]) {
    addBox(group, [0.085, 0.075, 0.008], [x, 0, -0.492], "#484b50", 0.01, 0.4);
  }
  addBox(group, [0.24, 0.1, 0.1], [0.64, 0.23, -0.72], "#212225", 0.04, 0.5);
  group.rotation.set(0.68, -0.24, -0.12);
  return group;
}

export function PrizeModel() {
  const containerRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const container = containerRef.current;
    if (!container) return;
    let renderer: THREE.WebGLRenderer;
    try {
      renderer = new THREE.WebGLRenderer({ alpha: true, antialias: true, preserveDrawingBuffer: true, powerPreference: "low-power" });
    } catch {
      return;
    }
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    renderer.outputColorSpace = THREE.SRGBColorSpace;
    container.appendChild(renderer.domElement);
    const still = document.createElement("img");
    still.alt = "";
    still.className = "prize-model-still";
    still.style.display = "none";
    container.appendChild(still);

    const scene = new THREE.Scene();
    const camera = new THREE.PerspectiveCamera(35, 1, 0.1, 100);
    camera.position.set(0, 0.08, 4.5);
    scene.add(new THREE.AmbientLight(0xffffff, 2.1));
    const key = new THREE.DirectionalLight(0xffffff, 2.4);
    key.position.set(-3, 5, 6);
    scene.add(key);
    const fill = new THREE.DirectionalLight(0xa9c9f3, 1.25);
    fill.position.set(4, 0, -2);
    scene.add(fill);
    const model = buildFitbit();
    scene.add(model);

    const motion = window.matchMedia("(prefers-reduced-motion: reduce)");
    let visible = false;
    let dragging = false;
    let lastX = 0;
    let frame = 0;
    let previous = 0;
    const render = () => renderer.render(scene, camera);
    const tick = (time: number) => {
      if (!visible || motion.matches) {
        frame = 0;
        previous = 0;
        return;
      }
      if (previous) model.rotation.y += Math.min((time - previous) / 1000, 0.05) * 0.18;
      previous = time;
      render();
      frame = requestAnimationFrame(tick);
    };
    const updateAnimation = () => {
      cancelAnimationFrame(frame);
      frame = 0;
      previous = 0;
      render();
      if (motion.matches) {
        still.src = renderer.domElement.toDataURL("image/png");
        still.style.display = "block";
      } else {
        still.style.display = "none";
      }
      if (visible && !dragging && !motion.matches) frame = requestAnimationFrame(tick);
    };
    const pointerDown = (event: PointerEvent) => {
      if (event.button !== 0) return;
      dragging = true;
      lastX = event.clientX;
      cancelAnimationFrame(frame);
      frame = 0;
      previous = 0;
      still.style.display = "none";
      container.setPointerCapture(event.pointerId);
      container.classList.add("is-dragging");
    };
    const pointerMove = (event: PointerEvent) => {
      if (!dragging) return;
      model.rotation.y += (event.clientX - lastX) / container.clientWidth * Math.PI * 2;
      lastX = event.clientX;
      render();
    };
    const pointerEnd = (event: PointerEvent) => {
      if (!dragging) return;
      dragging = false;
      if (container.hasPointerCapture(event.pointerId)) container.releasePointerCapture(event.pointerId);
      container.classList.remove("is-dragging");
      updateAnimation();
    };
    const keyDown = (event: KeyboardEvent) => {
      if (event.key !== "ArrowLeft" && event.key !== "ArrowRight") return;
      event.preventDefault();
      model.rotation.y += (event.key === "ArrowRight" ? 1 : -1) * Math.PI / 18;
      updateAnimation();
    };
    const resize = () => {
      const { width, height } = container.getBoundingClientRect();
      if (!width || !height) return;
      camera.aspect = width / height;
      camera.updateProjectionMatrix();
      renderer.setSize(width, height, false);
      render();
      if (motion.matches) {
        still.src = renderer.domElement.toDataURL("image/png");
        still.style.display = "block";
      }
    };
    const resizeObserver = new ResizeObserver(resize);
    resizeObserver.observe(container);
    const intersectionObserver = new IntersectionObserver(([entry]) => {
      visible = entry.isIntersecting;
      updateAnimation();
    }, { threshold: 0.05 });
    intersectionObserver.observe(container);
    motion.addEventListener("change", updateAnimation);
    container.addEventListener("pointerdown", pointerDown);
    container.addEventListener("pointermove", pointerMove);
    container.addEventListener("pointerup", pointerEnd);
    container.addEventListener("pointercancel", pointerEnd);
    container.addEventListener("keydown", keyDown);
    resize();

    return () => {
      cancelAnimationFrame(frame);
      motion.removeEventListener("change", updateAnimation);
      container.removeEventListener("pointerdown", pointerDown);
      container.removeEventListener("pointermove", pointerMove);
      container.removeEventListener("pointerup", pointerEnd);
      container.removeEventListener("pointercancel", pointerEnd);
      container.removeEventListener("keydown", keyDown);
      intersectionObserver.disconnect();
      resizeObserver.disconnect();
      scene.traverse(object => {
        if (object instanceof THREE.Mesh) {
          object.geometry.dispose();
          const materials = Array.isArray(object.material) ? object.material : [object.material];
          materials.forEach(item => {
            if ((item instanceof THREE.MeshBasicMaterial || item instanceof THREE.MeshStandardMaterial) && item.map) item.map.dispose();
            item.dispose();
          });
        }
      });
      renderer.dispose();
      renderer.domElement.remove();
      still.remove();
    };
  }, []);

  return (
    <div
      ref={containerRef}
      className="prize-model prize-model-draggable"
      role="img"
      tabIndex={0}
      aria-label="3D view of the Google Fitbit Air. Drag left or right, or use the arrow keys, to rotate it."
    />
  );
}
