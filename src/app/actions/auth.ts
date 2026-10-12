"use server";

import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { registrationOpen, siteUrl } from "@/lib/config";

function value(data: FormData, key: string) {
  return String(data.get(key) ?? "").trim();
}

function errorRedirect(path: string, message: string): never {
  redirect(`${path}?error=${encodeURIComponent(message)}`);
}

export async function register(data: FormData) {
  if (!registrationOpen()) errorRedirect("/register", "Registration has closed.");
  const fullName = value(data, "full_name");
  const grade = value(data, "grade");
  const email = value(data, "email").toLowerCase();
  const repeatedEmail = value(data, "repeat_email").toLowerCase();
  const password = String(data.get("password") ?? "");
  const tshirtSize = value(data, "tshirt_size");
  const committed = data.get("attendance_commitment") === "on";

  if (fullName.length < 2 || fullName.length > 120) errorRedirect("/register", "Enter your full name.");
  if (!["first-year", "sophomore", "junior", "senior"].includes(grade)) errorRedirect("/register", "Choose your class year.");
  if (!/^[^@\s]+@fandm\.edu$/.test(email)) errorRedirect("/register", "Use your F&M email address.");
  if (email !== repeatedEmail) errorRedirect("/register", "The email addresses do not match.");
  if (password.length < 12) errorRedirect("/register", "Use a password with at least 12 characters.");
  if (!["XS", "S", "M", "L", "XL", "2XL", "3XL"].includes(tshirtSize)) errorRedirect("/register", "Choose a T-shirt size.");
  if (!committed) errorRedirect("/register", "Please confirm you expect to attend.");

  const supabase = await createClient();
  const { data: signup, error } = await supabase.auth.signUp({
    email,
    password,
    options: {
      data: { full_name: fullName, grade, tshirt_size: tshirtSize, attendance_commitment: true },
    },
  });
  if (error) errorRedirect("/register", "We could not create your account. Check your details or try logging in.");
  if (!signup.session) redirect("/register?confirmation_required=1");
  redirect("/account");
}

export async function login(data: FormData) {
  const email = value(data, "email").toLowerCase();
  const password = String(data.get("password") ?? "");
  const supabase = await createClient();
  const { error } = await supabase.auth.signInWithPassword({ email, password });
  if (error) errorRedirect("/login", "Email or password is incorrect.");
  redirect("/account");
}

export async function logout() {
  const supabase = await createClient();
  await supabase.auth.signOut();
  redirect("/");
}

export async function requestPasswordReset(data: FormData) {
  const email = value(data, "email").toLowerCase();
  if (!/^[^@\s]+@fandm\.edu$/.test(email)) errorRedirect("/forgot-password", "Use your F&M email address.");
  const supabase = await createClient();
  await supabase.auth.resetPasswordForEmail(email, {
    redirectTo: `${siteUrl()}/auth/callback?next=/reset-password`,
  });
  redirect("/forgot-password?sent=1");
}

export async function updatePassword(data: FormData) {
  const password = String(data.get("password") ?? "");
  if (password.length < 12) errorRedirect("/reset-password", "Use a password with at least 12 characters.");
  const supabase = await createClient();
  const { data: userData } = await supabase.auth.getUser();
  if (!userData.user) errorRedirect("/reset-password", "Your reset link expired. Request a new one.");
  const { error } = await supabase.auth.updateUser({ password });
  if (error) errorRedirect("/reset-password", "Password update failed. Request a new link.");
  redirect("/account?password_updated=1");
}
