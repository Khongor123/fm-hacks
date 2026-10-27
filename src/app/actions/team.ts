"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

const knownErrors = new Set([
  "Team changes have closed.",
  "Only confirmed participants can join teams.",
  "Team names must be 2 to 40 characters.",
  "Leave your current team before creating another.",
  "Leave your current team before joining another.",
  "Could not create a team code. Try again.",
  "Enter a valid 6-character team code.",
  "Team code not found.",
  "This team is full.",
  "You are not on a team.",
  "This team no longer exists.",
]);

function teamError(message: string, code?: string): never {
  const copy = code === "23505"
    ? "You are already on a team. Refresh this page to see it."
    : knownErrors.has(message) ? message : "Team action failed. Please try again.";
  redirect(`/team?team_error=${encodeURIComponent(copy)}`);
}

export async function createTeam(formData: FormData) {
  const name = String(formData.get("team_name") ?? "").trim();
  if (name.length < 2 || name.length > 40) teamError("Team names must be 2 to 40 characters.");
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");
  const { error } = await supabase.rpc("create_team", { p_name: name });
  if (error) teamError(error.message, error.code);
  revalidatePath("/");
  revalidatePath("/team");
  redirect("/team?team_notice=created");
}

export async function joinTeam(formData: FormData) {
  const code = String(formData.get("team_code") ?? "").trim().toUpperCase();
  if (!/^[0-9A-F]{6}$/.test(code)) teamError("Enter a valid 6-character team code.");
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");
  const { error } = await supabase.rpc("join_team", { p_code: code });
  if (error) teamError(error.message, error.code);
  revalidatePath("/");
  revalidatePath("/team");
  redirect("/team?team_notice=joined");
}

export async function leaveTeam() {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");
  const { error } = await supabase.rpc("leave_team");
  if (error) teamError(error.message, error.code);
  revalidatePath("/");
  revalidatePath("/team");
  redirect("/team?team_notice=left");
}
