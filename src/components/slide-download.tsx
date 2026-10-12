"use client";
import { useState } from "react";
import { createClient } from "@/lib/supabase/browser";
import { SLIDE_BUCKET } from "@/lib/event";

export function SlideDownload({ path }: { path: string }) {
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);
  async function download() {
    setBusy(true); setError("");
    const { data, error } = await createClient().storage.from(SLIDE_BUCKET).download(path);
    if (error || !data) setError("Slides could not be downloaded.");
    else {
      const url = URL.createObjectURL(data);
      const link = document.createElement("a");
      link.href = url;
      link.download = `slides.${path.split(".").pop()}`;
      link.click();
      window.setTimeout(() => URL.revokeObjectURL(url), 60_000);
    }
    setBusy(false);
  }
  return <span><button type="button" className="text-link" onClick={download} disabled={busy}>{busy ? "Downloading…" : "Download slides ↗"}</button>{error && <small role="alert"> {error}</small>}</span>;
}
