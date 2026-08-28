// ============================================================
// VeSole POS — Supabase Client
// ============================================================
// Fill in YOUR project's values below (Supabase Dashboard →
// Project Settings → API). Every other file in this app loads
// this one first and uses the shared `supabase` object it creates.
// ============================================================

const SUPABASE_URL = "PASTE_YOUR_PROJECT_URL_HERE";      // e.g. https://xxxxxxxx.supabase.co
const SUPABASE_ANON_KEY = "PASTE_YOUR_ANON_KEY_HERE";

// Loads the Supabase JS library from CDN (no npm/build step needed)
// and exposes a single shared client as `window.supabase`.
const script = document.createElement("script");
script.src = "https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2";
script.onload = () => {
  window.supabase = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
  window.dispatchEvent(new Event("supabase-ready"));
};
document.head.appendChild(script);

// ------------------------------------------------------------
// Small shared helpers used across pages
// ------------------------------------------------------------

// Wait for the Supabase client to finish loading before using it.
function onSupabaseReady(callback) {
  if (window.supabase && typeof window.supabase.from === "function") {
    callback();
  } else {
    window.addEventListener("supabase-ready", callback, { once: true });
  }
}

// Redirect to login if there's no active session. Call at the top
// of every protected page (dashboard, pos, inventory, etc.).
async function requireAuth() {
  return new Promise((resolve) => {
    onSupabaseReady(async () => {
      const { data: { session } } = await window.supabase.auth.getSession();
      if (!session) {
        window.location.href = "index.html";
        return;
      }
      resolve(session);
    });
  });
}

// Fetches the logged-in user's profile row (business_id, role, name).
async function getCurrentProfile() {
  const { data: { user } } = await window.supabase.auth.getUser();
  if (!user) return null;
  const { data, error } = await window.supabase
    .from("user_profiles")
    .select("*, businesses(*)")
    .eq("id", user.id)
    .single();
  if (error) {
    console.error("Failed to load profile:", error);
    return null;
  }
  return data;
}

// Formats a number as currency using the business's configured symbol.
function formatMoney(amount, symbol = "KSh") {
  const n = Number(amount || 0);
  return `${symbol} ${n.toLocaleString("en-KE", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
}
