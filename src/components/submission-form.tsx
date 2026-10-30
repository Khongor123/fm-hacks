"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/browser";
import { MAX_SLIDE_BYTES, SLIDE_BUCKET, TRACKS, type Submission } from "@/lib/event";
import { SlideDownload } from "@/components/slide-download";
import { useDeadlineRemaining } from "@/components/use-deadline-remaining";

type FormState = {
  title: string; description: string; track: string; github_url: string;
  public_repo_confirmed: boolean; ai_level: string; ai_disclosure: string;
  onsite_confirmed: boolean; no_outside_help_confirmed: boolean;
};
function initialForm(value: Submission | null): FormState {
  return {
    title: value?.title ?? "", description: value?.description ?? "", track: value?.track ?? "",
    github_url: value?.github_url ?? "", public_repo_confirmed: value?.public_repo_confirmed ?? false,
    ai_level: value?.ai_level ?? "", ai_disclosure: value?.ai_disclosure ?? "",
    onsite_confirmed: value?.onsite_confirmed ?? false,
    no_outside_help_confirmed: value?.no_outside_help_confirmed ?? false,
  };
}
function contentType(extension: string) {
  return extension === "pdf" ? "application/pdf" : extension === "pptx"
    ? "application/vnd.openxmlformats-officedocument.presentationml.presentation"
    : "application/x-iwork-keynote-sffkey";
}
async function uploadSlide(file: File, path: string, onProgress: (percent: number) => void) {
  const supabase = createClient();
  const extension = path.split(".").pop()!;
  if (file.size <= 6 * 1024 * 1024) {
    const { error } = await supabase.storage.from(SLIDE_BUCKET).upload(path, file, { contentType: contentType(extension), upsert: false });
    if (error) throw error;
    onProgress(100);
    return;
  }
  const { data: { session } } = await supabase.auth.getSession();
  if (!session) throw new Error("Your session expired. Sign in again.");
  const projectUrl = process.env.NEXT_PUBLIC_SUPABASE_URL!;
  const endpoint = `${projectUrl.replace(".supabase.co", ".storage.supabase.co")}/storage/v1/upload/resumable`;
  const key = `slide-upload:${path}`;
  const baseHeaders = { "Tus-Resumable": "1.0.0", authorization: `Bearer ${session.access_token}` };
  let uploadUrl = window.sessionStorage.getItem(key);
  if (!uploadUrl) {
    const metadata = { bucketName: SLIDE_BUCKET, objectName: path, contentType: contentType(extension), cacheControl: "3600" };
    const response = await fetch(endpoint, {
      method: "POST",
      headers: { ...baseHeaders, "Upload-Length": String(file.size), "Upload-Metadata": Object.entries(metadata).map(([name, value]) => `${name} ${btoa(value)}`).join(",") },
    });
    if (!response.ok) throw new Error(`Slide upload could not start (${response.status}).`);
    const location = response.headers.get("Location");
    if (!location) throw new Error("Slide upload response had no location.");
    uploadUrl = new URL(location, endpoint).toString();
    window.sessionStorage.setItem(key, uploadUrl);
  }
  let offset = 0;
  const head = await fetch(uploadUrl, { method: "HEAD", headers: baseHeaders });
  if (head.ok) offset = Number(head.headers.get("Upload-Offset") ?? "0");
  else if (head.status !== 404) throw new Error(`Could not resume slide upload (${head.status}).`);
  else { window.sessionStorage.removeItem(key); throw new Error("Upload expired. Please try again."); }
  while (offset < file.size) {
    const chunk = file.slice(offset, Math.min(file.size, offset + 6 * 1024 * 1024));
    let complete = false;
    for (let attempt = 0; attempt < 4 && !complete; attempt++) {
      try {
        const response = await fetch(uploadUrl, {
          method: "PATCH", headers: { ...baseHeaders, "Content-Type": "application/offset+octet-stream", "Upload-Offset": String(offset) }, body: chunk,
        });
        if (!response.ok) throw new Error(`Slide upload failed (${response.status}).`);
        offset = Number(response.headers.get("Upload-Offset") ?? offset + chunk.size);
        onProgress(Math.round(offset / file.size * 100));
        complete = true;
      } catch (error) {
        const resumed = await fetch(uploadUrl, { method: "HEAD", headers: baseHeaders });
        if (!resumed.ok) throw error;
        const newOffset = Number(resumed.headers.get("Upload-Offset") ?? offset);
        if (newOffset > offset) { offset = newOffset; complete = true; }
        else if (attempt === 3) throw error;
        else await new Promise(resolve => window.setTimeout(resolve, 1000 * (attempt + 1)));
      }
    }
  }
  window.sessionStorage.removeItem(key);
}

export function SubmissionForm({ initial, ownerId, ownerKind, open, checkedIn, serverNow }: {
  initial: Submission | null; ownerId: string; ownerKind: "team" | "solo"; open: boolean; checkedIn: boolean; serverNow: number;
}) {
  const router = useRouter();
  const remaining = useDeadlineRemaining(serverNow);
  const editable = open && remaining > 0;
  const [submission, setSubmission] = useState(initial);
  const [form, setForm] = useState<FormState>(() => initialForm(initial));
  const [file, setFile] = useState<File | null>(null);
  const [fileInputKey, setFileInputKey] = useState(0);
  const [busy, setBusy] = useState(false);
  const [progress, setProgress] = useState<number | null>(null);
  const [message, setMessage] = useState("");
  const [error, setError] = useState("");
  const set = <K extends keyof FormState>(key: K, value: FormState[K]) => setForm(previous => ({ ...previous, [key]: value }));
  const state = !editable ? "Deadline passed" : submission?.status === "submitted" ? "Submitted" : "Draft";

  async function save(final: boolean) {
    if (!checkedIn || !editable || busy) return;
    if (!TRACKS.some(track => track === form.track)) {
      setError("Choose a track before saving or submitting your project.");
      document.getElementById("project_track")?.focus();
      return;
    }
    setBusy(true); setMessage(""); setError(""); setProgress(null);
    const supabase = createClient();
    let newPath: string | null = null;
    let uploadComplete = false;
    let saved = false;
    let pendingKey: string | null = null;
    try {
      if (file) {
        const extension = file.name.split(".").pop()?.toLowerCase();
        if (!extension || !["pdf", "pptx", "key"].includes(extension)) throw new Error("Choose a .pptx, .key, or .pdf file.");
        if (!file.size || file.size > MAX_SLIDE_BYTES) throw new Error("Slides must be 10 MB or less.");
        if (file.size > 6 * 1024 * 1024) {
          pendingKey = `pending-slide:${ownerKind}/${ownerId}:${file.name}:${file.size}:${file.lastModified}`;
          newPath = window.sessionStorage.getItem(pendingKey);
        }
        newPath ??= `${ownerKind}/${ownerId}/${crypto.randomUUID()}.${extension}`;
        if (pendingKey) window.sessionStorage.setItem(pendingKey, newPath);
        await uploadSlide(file, newPath, setProgress);
        uploadComplete = true;
      }
      const { error: saveError } = await supabase.rpc("save_submission", {
        p_title: form.title, p_description: form.description, p_track: form.track,
        p_github_url: form.github_url, p_public_repo_confirmed: form.public_repo_confirmed,
        p_ai_level: form.ai_level || null, p_ai_disclosure: form.ai_disclosure,
        p_slide_path: newPath ?? submission?.slide_path ?? null, p_submit: final,
        p_onsite_confirmed: form.onsite_confirmed,
        p_no_outside_help_confirmed: form.no_outside_help_confirmed,
        p_expected_updated_at: submission?.updated_at ?? null,
      });
      if (saveError) throw saveError;
      saved = true;
      if (pendingKey) window.sessionStorage.removeItem(pendingKey);
      const oldPath = submission?.slide_path;
      const { data, error: readError } = await supabase.rpc("get_my_submission");
      if (!readError) setSubmission(data as Submission | null);
      setFile(null); setFileInputKey(value => value + 1);
      setMessage(readError ? "Saved. Refresh this page to see the latest version." : final ? "Submission received. Your team can revise and resubmit until the deadline." : "Draft saved for your team.");
      if (newPath && oldPath && oldPath !== newPath) {
        const { error: removeError } = await supabase.storage.from(SLIDE_BUCKET).remove([oldPath]);
        if (removeError) setMessage("Saved. Ask an organizer to remove the previous slide file if storage cleanup is needed.");
      }
      router.refresh();
    } catch (caught) {
      if (saved) {
        setMessage("Saved. Refresh this page to see the latest version.");
      } else {
        if (newPath && uploadComplete) {
          try {
            await supabase.storage.from(SLIDE_BUCKET).remove([newPath]);
          } catch (cleanupError) {
            console.error("Could not remove unsaved slide upload", cleanupError);
          }
          if (pendingKey) window.sessionStorage.removeItem(pendingKey);
        }
        setError(caught instanceof Error ? caught.message : "Could not save the submission.");
      }
    } finally { setBusy(false); setProgress(null); }
  }

  async function updateRepo() {
    setBusy(true); setError(""); setMessage("");
    try {
      const supabase = createClient();
      const { error } = await supabase.rpc("update_submission_repo", { p_github_url: form.github_url });
      if (error) setError(error.message);
      else { setMessage("Repository link updated."); router.refresh(); }
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "Could not update the repository link.");
    } finally {
      setBusy(false);
    }
  }

  return <section className="participant-panel submission-panel" id="submission">
    <div className="submission-heading"><div><span className="card-label">PROJECT SUBMISSION</span><h2>{ownerKind === "team" ? "One submission for your team." : "Your solo submission."}</h2></div><span className={`submission-state ${state.toLowerCase().replaceAll(" ", "-")}`}>{state}</span></div>
    {!editable ? <><p>The deadline has passed. Your submission is view only; the repository link can still be corrected.</p>{submission ? <>
        <dl className="submission-summary"><div><dt>Project</dt><dd>{submission.title || "Untitled draft"}</dd></div><div><dt>Description</dt><dd>{submission.description || "—"}</dd></div><div><dt>Track</dt><dd>{submission.track || "—"}</dd></div><div><dt>AI use</dt><dd>{submission.ai_level || "—"}</dd></div><div><dt>AI disclosure</dt><dd>{submission.ai_disclosure || "—"}</dd></div><div><dt>Slides</dt><dd>{submission.slide_path ? <SlideDownload path={submission.slide_path} /> : "None uploaded"}</dd></div></dl>
        {checkedIn ? <><div className="field"><label htmlFor="late_repo">GitHub repository URL</label><input id="late_repo" type="url" value={form.github_url} onChange={event => set("github_url", event.target.value)} /></div><button type="button" className="button button-dark" onClick={updateRepo} disabled={busy}>Update repository link</button></> : <p>Find an organizer to check in before correcting the repository link.</p>}
      </> : <p>No submission was saved before the deadline.</p>}</>
      : !checkedIn ? <p>Check in with an organizer at Stager Auditorium before editing or submitting. Bring your student ID so they can verify your identity.</p>
      : <><p>Any checked-in team member can save, revise, and submit this shared entry until Sunday at 10:00 a.m. ET.</p>
        <div className="submission-fields"><div className="field"><label htmlFor="project_title">Project title</label><input id="project_title" maxLength={120} value={form.title} onChange={event => set("title", event.target.value)} /></div>
          <div className="field"><label htmlFor="project_description">Short description</label><textarea id="project_description" maxLength={500} rows={3} value={form.description} onChange={event => set("description", event.target.value)} /></div>
          <div className="field"><label htmlFor="project_track">Track (required)</label><select id="project_track" value={form.track} onChange={event => { set("track", event.target.value); setError(""); }} required><option value="">Choose a track</option>{TRACKS.map(track => <option key={track}>{track}</option>)}</select></div>
          <div className="field"><label htmlFor="project_github">Public GitHub repository URL</label><input id="project_github" type="url" placeholder="https://github.com/owner/repository" value={form.github_url} onChange={event => set("github_url", event.target.value)} /><small>Organizers will check that this link opens publicly.</small></div>
          <label className="check-line"><input type="checkbox" checked={form.public_repo_confirmed} onChange={event => set("public_repo_confirmed", event.target.checked)} /> I confirm the repository is public.</label>
          <div className="field"><label htmlFor="ai_level">AI-use level</label><select id="ai_level" value={form.ai_level} onChange={event => set("ai_level", event.target.value)}><option value="">Choose a level</option><option value="none">None</option><option value="assisted">Assisted</option><option value="substantial">Substantial</option></select></div>
          <div className="field"><label htmlFor="ai_disclosure">How did you use AI?</label><textarea id="ai_disclosure" maxLength={1000} rows={3} placeholder="If none, write ‘No AI used.’" value={form.ai_disclosure} onChange={event => set("ai_disclosure", event.target.value)} /></div>
          <div className="field"><label htmlFor="slides">Presentation slides</label><input key={fileInputKey} id="slides" type="file" accept=".pptx,.key,.pdf" onChange={event => setFile(event.target.files?.[0] ?? null)} /><small>.pptx, .key, or .pdf, up to 10 MB. A Keynote package should be <a href="https://support.apple.com/en-gb/guide/keynote/tana0d19882a/mac" target="_blank" rel="noreferrer">exported to PDF</a> before upload.</small>{submission?.slide_path && <span>Current slides: <SlideDownload path={submission.slide_path} /></span>}</div>
          <label className="check-line"><input type="checkbox" checked={form.onsite_confirmed} onChange={event => set("onsite_confirmed", event.target.checked)} /> Our project work was done onsite during the hackathon.</label>
          <label className="check-line"><input type="checkbox" checked={form.no_outside_help_confirmed} onChange={event => set("no_outside_help_confirmed", event.target.checked)} /> Direct project work came only from our team; we received no outside help.</label>
        </div><div className="submission-actions"><button type="button" className="button button-ghost" disabled={busy} onClick={() => save(false)}>Save draft</button><button type="button" className="button button-dark" disabled={busy} onClick={() => save(true)}>{submission?.status === "submitted" ? "Resubmit project" : "Submit project"}</button></div>
        {progress !== null && <p role="status">Uploading slides: {progress}%</p>}
      </>}
    {message && <p className="form-notice success" role="status">{message}</p>}{error && <p className="form-notice error" role="alert">{error}</p>}
  </section>;
}
