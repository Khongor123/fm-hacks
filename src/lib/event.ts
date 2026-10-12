export const EVENT_DAY_START = "2026-11-07T09:00:00-05:00";
export const SUBMISSIONS_OPEN = "2026-11-07T10:00:00-05:00";
export const SUBMISSIONS_CLOSE = "2026-11-08T10:00:00-05:00";
export const SLIDE_BUCKET = "submission-slides";
export const MAX_SLIDE_BYTES = 10 * 1024 * 1024;
export const TRACKS = ["AI", "Social good", "Creative build"] as const;

export type Submission = {
  id: string;
  team_id: string | null;
  solo_user_id: string | null;
  status: "draft" | "submitted";
  title: string | null;
  description: string | null;
  track: string | null;
  github_url: string | null;
  public_repo_confirmed: boolean;
  ai_level: string | null;
  ai_disclosure: string | null;
  slide_path: string | null;
  onsite_confirmed: boolean;
  no_outside_help_confirmed: boolean;
  updated_at: string;
  submitted_at: string | null;
};

export function eventPhase(now: number): "before" | "event" | "submissions" | "closed" {
  if (now < Date.parse(EVENT_DAY_START)) return "before";
  if (now < Date.parse(SUBMISSIONS_OPEN)) return "event";
  if (now < Date.parse(SUBMISSIONS_CLOSE)) return "submissions";
  return "closed";
}

export function nextBoundaryDelay(now: number, phase: ReturnType<typeof eventPhase>): number | null {
  const next = phase === "before" ? EVENT_DAY_START
    : phase === "event" ? SUBMISSIONS_OPEN
    : phase === "submissions" ? SUBMISSIONS_CLOSE : null;
  return next ? Math.min(2_147_000_000, Math.max(0, Date.parse(next) - now + 100)) : null;
}
