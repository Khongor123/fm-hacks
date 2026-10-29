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

export type RegistrationState = { error: string | null };

export async function register(_previous: RegistrationState, data: FormData): Promise<RegistrationState> {
  if (!registrationOpen()) return { error: "Registration has closed." };
  const fullName = value(data, "full_name");
  const grade = value(data, "grade");
  const email = value(data, "email").toLowerCase();
  const repeatedEmail = value(data, "repeat_email").toLowerCase();
  const password = String(data.get("password") ?? "");
  const tshirtSize = value(data, "tshirt_size");
  const committed = data.get("attendance_commitment") === "on";

  if (fullName.length < 2 || fullName.length > 120) return { error: "Enter your full name." };
  if (!["first-year", "sophomore", "junior", "senior"].includes(grade)) return { error: "Choose your class year." };
  if (!/^[^@\s]+@fandm\.edu$/.test(email)) return { error: "Use your F&M email address." };
  if (email !== repeatedEmail) return { error: "The email addresses do not match." };
  if (password.length < 8) return { error: "Use a password with at least 8 characters." };
  if (!["XS", "S", "M", "L", "XL", "2XL", "3XL"].includes(tshirtSize)) return { error: "Choose a T-shirt size." };
  if (!committed) return { error: "Please confirm you expect to attend." };

  const supabase = await createClient();
  let signup;
  try {
    const result = await supabase.auth.signUp({
      email,
      password,
      options: {
        data: { full_name: fullName, grade, tshirt_size: tshirtSize, attendance_commitment: true },
      },
    });
    if (result.error) {
      console.error("Registration failed:", result.error);
      return { error: result.error.message.includes("already registered")
        ? "This email already has an account. Log in instead."
        : "We could not create your account. Check your details or try logging in." };
    }
    signup = result.data;
  } catch (error) {
    console.error("Registration connection failed:", error);
    return { error: "Could not reach the registration service. Check your connection and try again." };
  }
  if (!signup.session) redirect("/register?confirmation_required=1");
  redirect("/#dashboard");
}

export async function login(data: FormData) {
  const email = value(data, "email").toLowerCase();
  const password = String(data.get("password") ?? "");
  const supabase = await createClient();
  let error;
  try {
    ({ error } = await supabase.auth.signInWithPassword({ email, password }));
  } catch (cause) {
    console.error("Sign-in connection failed:", cause);
    errorRedirect("/login", "Could not reach the sign-in service. Try again shortly.");
  }
  if (error) {
    if (error.code === "invalid_credentials") errorRedirect("/login", "Email or password is incorrect. Check that this account was created for this site.");
    console.error("Sign-in failed:", { code: error.code, status: error.status, message: error.message });
    errorRedirect("/login", "Sign-in is unavailable right now. Please try again shortly.");
  }
  redirect("/#dashboard");
}

export async function logout() {
  const supabase = await createClient();
  await supabase.auth.signOut();
  redirect("/");
}

export async function deleteAccount(data: FormData) {
  if (data.get("confirm_delete") !== "yes") errorRedirect("/account/delete", "Confirm that you want to delete your account.");
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");
  const { error } = await supabase.rpc("delete_my_account");
  if (error) {
    console.error("Account deletion failed:", error);
    errorRedirect("/account/delete", "Could not delete your account. Please try again.");
  }
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

export async function confirmPasswordReset(data: FormData) {
  const tokenHash = value(data, "token_hash");
  if (!tokenHash) errorRedirect("/forgot-password", "Reset link is invalid. Request a new one.");
  const supabase = await createClient();
  const { error } = await supabase.auth.verifyOtp({ token_hash: tokenHash, type: "recovery" });
  if (error) errorRedirect("/forgot-password", "Reset link expired or was already used. Request a new one.");
  redirect("/reset-password");
}

export async function updatePassword(data: FormData) {
  const password = String(data.get("password") ?? "");
  if (password.length < 8) errorRedirect("/reset-password", "Use a password with at least 8 characters.");
  const supabase = await createClient();
  const { data: userData } = await supabase.auth.getUser();
  if (!userData.user) errorRedirect("/reset-password", "Your reset link expired. Request a new one.");
  const { error } = await supabase.auth.updateUser({ password });
  if (error) errorRedirect("/reset-password", "Password update failed. Request a new link.");
  redirect("/account?password_updated=1");
}
