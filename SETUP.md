# VeSole POS — Setup Guide (Stage 1)

This gets your database live. Everything here can be done from a phone browser — no terminal needed.

## 1. Create a Supabase project

1. Go to https://supabase.com and sign up / log in.
2. Click **New Project**.
3. Pick an organization, name it (e.g. `vesole-pos-clienta`), set a strong database password (save it somewhere), pick a region close to Kenya (e.g. `eu-central` or `ap-south`).
4. Wait ~2 minutes for it to provision.

> One Supabase project can safely host multiple client businesses (the schema is multi-tenant via `business_id`), or you can spin up a separate free project per client for full isolation. Either works with this schema — start with one project, split later if you want cleaner separation.

## 2. Run the schema

1. In your Supabase project, open **SQL Editor** (left sidebar) → **New query**.
2. Copy the entire contents of `sql/schema.sql` and paste it in.
3. Click **Run**. You should see "Success. No rows returned."
4. Check **Table Editor** (left sidebar) — you should now see `businesses`, `products`, `sales`, etc.

## 3. Get your API keys

1. Go to **Project Settings → API**.
2. Copy the **Project URL** and the **anon public** key.
3. You'll paste these into `assets/js/supabase-client.js` in the next stage — keep them handy.

## 4. Create your first business + admin user

Once the schema is in, we'll do this two ways depending on what you want:
- **Quick way (SQL):** insert a row into `businesses`, then create a user via **Authentication → Users → Add user**, then link them in `user_profiles` with `role = 'admin'`.
- **App way:** once the login/signup page is built (next stage), a first-run "Create your business" flow will do this for you.

I'll walk you through whichever one you want when we get to the login page.

## What's next

Next stage: `assets/js/supabase-client.js` (connects the app to your project) + `index.html` (login page) + `dashboard.html`. Say the word when you're ready.
