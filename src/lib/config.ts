export const REGISTRATION_DEADLINE = "2026-11-04T00:00:00-05:00";
export const EVENT_START = "2026-11-07T09:00:00-05:00";
export const EVENT_END = "2026-11-08T13:30:00-05:00";
export const CAPACITY = 75;

export function registrationOpen() {
  return Date.now() < new Date(REGISTRATION_DEADLINE).getTime();
}

export const teamChangesOpen = registrationOpen;

export function siteUrl() {
  return process.env.NEXT_PUBLIC_SITE_URL?.replace(/\/$/, "") || "http://localhost:3000";
}
