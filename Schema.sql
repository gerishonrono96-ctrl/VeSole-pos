-- ============================================================
-- VeSole POS — Database Schema (Supabase / PostgreSQL)
-- ============================================================
-- Run this in: Supabase Dashboard -> SQL Editor -> New Query
-- This creates every table, relationship, and Row-Level Security
-- (RLS) policy needed to run one or many client businesses safely
-- from a single Supabase project (multi-tenant via business_id).
--
-- If you prefer one Supabase project per client instead of a
-- shared multi-tenant project, this same schema still works —
-- you'd just skip filtering by business_id in the app since each
-- project only ever holds one business. RLS below is written to
-- be safe either way.
-- ============================================================

-- ------------------------------------------------------------
-- EXTENSIONS
-- ------------------------------------------------------------
create extension if not exists "uuid-ossp";

-- ------------------------------------------------------------
-- 1. BUSINESSES  (the configurable business profile)
-- ------------------------------------------------------------
create table businesses (
  id uuid primary key default uuid_generate_v4(),
  name text not null,
  logo_url text,
  phone text,
  email text,
  address text,
  currency text not null default 'KES',
  currency_symbol text not null default 'KSh',
  tax_enabled boolean not null default false,
  tax_rate numeric(5,2) not null default 0,        -- e.g. 16.00 for 16%
  receipt_footer text default 'Thank you for your business!',
  low_stock_threshold integer not null default 5,
  business_type text default 'retail',              -- retail, supermarket, pharmacy, restaurant, etc.
  created_at timestamptz not null default now()
);

-- ------------------------------------------------------------
-- 2. USERS / ROLES  (extends Supabase Auth users)
-- ------------------------------------------------------------
-- Supabase Auth already creates auth.users (email/password login).
-- This table adds business-specific profile + role info.
create table user_profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  business_id uuid not null references businesses(id) on delete cascade,
  full_name text not null,
  role text not null default 'cashier',   -- 'admin' or 'cashier'
  phone text,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

-- ------------------------------------------------------------
-- 3. CATEGORIES
-- ------------------------------------------------------------
create table categories (
  id uuid primary key default uuid_generate_v4(),
  business_id uuid not null references businesses(id) on delete cascade,
  name text not null,
  created_at timestamptz not null default now()
);

-- ------------------------------------------------------------
-- 4. SUPPLIERS
-- ------------------------------------------------------------
create table suppliers (
  id uuid primary key default uuid_generate_v4(),
  business_id uuid not null references businesses(id) on delete cascade,
  name text not null,
  phone text,
  email text,
  address text,
  amount_owed numeric(12,2) not null default 0,
  created_at timestamptz not null default now()
);

-- ------------------------------------------------------------
-- 5. PRODUCTS / INVENTORY
-- ------------------------------------------------------------
create table products (
  id uuid primary key default uuid_generate_v4(),
  business_id uuid not null references businesses(id) on delete cascade,
  category_id uuid references categories(id) on delete set null,
  supplier_id uuid references suppliers(id) on delete set null,
  name text not null,
  sku text,
  barcode text,
  image_url text,
  buying_price numeric(12,2) not null default 0,
  selling_price numeric(12,2) not null default 0,
  current_stock numeric(12,2) not null default 0,
  min_stock_level numeric(12,2) not null default 0,
  unit text default 'pcs',                 -- pcs, kg, litre, etc.
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index idx_products_business on products(business_id);
create index idx_products_barcode on products(barcode);

-- ------------------------------------------------------------
-- 6. STOCK MOVEMENTS  (audit trail for every stock change)
-- ------------------------------------------------------------
create table stock_movements (
  id uuid primary key default uuid_generate_v4(),
  business_id uuid not null references businesses(id) on delete cascade,
  product_id uuid not null references products(id) on delete cascade,
  change_qty numeric(12,2) not null,       -- positive = stock in, negative = stock out
  reason text not null,                    -- 'sale', 'restock', 'adjustment', 'return'
  reference_id uuid,                        -- e.g. sale_id if reason = 'sale'
  recorded_by uuid references user_profiles(id),
  created_at timestamptz not null default now()
);

-- ------------------------------------------------------------
-- 7. CUSTOMERS
-- ------------------------------------------------------------
create table customers (
  id uuid primary key default uuid_generate_v4(),
  business_id uuid not null references businesses(id) on delete cascade,
  name text not null,
  phone text,
  email text,
  outstanding_balance numeric(12,2) not null default 0,
  created_at timestamptz not null default now()
);

-- ------------------------------------------------------------
-- 8. SALES  (one row per transaction)
-- ------------------------------------------------------------
create table sales (
  id uuid primary key default uuid_generate_v4(),
  business_id uuid not null references businesses(id) on delete cascade,
  transaction_no text not null,             -- human-readable receipt number
  cashier_id uuid references user_profiles(id),
  customer_id uuid references customers(id),
  subtotal numeric(12,2) not null default 0,
  discount numeric(12,2) not null default 0,
  tax_amount numeric(12,2) not null default 0,
  total numeric(12,2) not null default 0,
  amount_received numeric(12,2) not null default 0,
  change_given numeric(12,2) not null default 0,
  status text not null default 'completed',  -- completed, refunded, partially_refunded
  created_at timestamptz not null default now()
);
create index idx_sales_business on sales(business_id);
create index idx_sales_created on sales(created_at);

-- ------------------------------------------------------------
-- 9. SALE ITEMS  (line items per sale)
-- ------------------------------------------------------------
create table sale_items (
  id uuid primary key default uuid_generate_v4(),
  sale_id uuid not null references sales(id) on delete cascade,
  product_id uuid references products(id),
  product_name text not null,               -- snapshot, in case product is edited/deleted later
  quantity numeric(12,2) not null,
  unit_price numeric(12,2) not null,
  line_total numeric(12,2) not null
);
create index idx_sale_items_sale on sale_items(sale_id);

-- ------------------------------------------------------------
-- 10. PAYMENTS  (a sale can be split across payment methods)
-- ------------------------------------------------------------
create table payments (
  id uuid primary key default uuid_generate_v4(),
  sale_id uuid not null references sales(id) on delete cascade,
  method text not null,                     -- cash, mpesa, card, other
  amount numeric(12,2) not null,
  mpesa_ref text,                            -- manual entry until API integration exists
  is_manual_entry boolean not null default true,  -- true = staff typed it in, false = future API-confirmed
  created_at timestamptz not null default now()
);

-- ------------------------------------------------------------
-- 11. EXPENSES
-- ------------------------------------------------------------
create table expenses (
  id uuid primary key default uuid_generate_v4(),
  business_id uuid not null references businesses(id) on delete cascade,
  name text not null,
  category text,
  amount numeric(12,2) not null,
  description text,
  recorded_by uuid references user_profiles(id),
  expense_date date not null default current_date,
  created_at timestamptz not null default now()
);

-- ============================================================
-- ROW LEVEL SECURITY
-- Every table is locked to rows matching the logged-in user's
-- own business_id, via a lookup into user_profiles.
-- ============================================================

create or replace function auth_business_id()
returns uuid
language sql
security definer
stable
as $$
  select business_id from user_profiles where id = auth.uid();
$$;

create or replace function auth_role()
returns text
language sql
security definer
stable
as $$
  select role from user_profiles where id = auth.uid();
$$;

alter table businesses enable row level security;
alter table user_profiles enable row level security;
alter table categories enable row level security;
alter table suppliers enable row level security;
alter table products enable row level security;
alter table stock_movements enable row level security;
alter table customers enable row level security;
alter table sales enable row level security;
alter table sale_items enable row level security;
alter table payments enable row level security;
alter table expenses enable row level security;

-- Businesses: a user can only see/edit their own business
create policy "own business read" on businesses for select using (id = auth_business_id());
create policy "own business update (admin only)" on businesses for update using (id = auth_business_id() and auth_role() = 'admin');

-- User profiles: see teammates in the same business; only admins manage accounts
create policy "same business read" on user_profiles for select using (business_id = auth_business_id());
create policy "admin manage users" on user_profiles for insert with check (auth_role() = 'admin');
create policy "admin update users" on user_profiles for update using (business_id = auth_business_id() and auth_role() = 'admin');
create policy "admin delete users" on user_profiles for delete using (business_id = auth_business_id() and auth_role() = 'admin');

-- Generic pattern applied to every business-scoped table:
-- read/write allowed only when business_id matches the caller's business.
create policy "biz read categories" on categories for select using (business_id = auth_business_id());
create policy "biz write categories" on categories for insert with check (business_id = auth_business_id());
create policy "biz update categories" on categories for update using (business_id = auth_business_id());
create policy "biz delete categories" on categories for delete using (business_id = auth_business_id() and auth_role() = 'admin');

create policy "biz read suppliers" on suppliers for select using (business_id = auth_business_id());
create policy "biz write suppliers" on suppliers for insert with check (business_id = auth_business_id());
create policy "biz update suppliers" on suppliers for update using (business_id = auth_business_id());
create policy "biz delete suppliers" on suppliers for delete using (business_id = auth_business_id() and auth_role() = 'admin');

create policy "biz read products" on products for select using (business_id = auth_business_id());
create policy "biz write products" on products for insert with check (business_id = auth_business_id());
create policy "biz update products" on products for update using (business_id = auth_business_id());
create policy "biz delete products" on products for delete using (business_id = auth_business_id() and auth_role() = 'admin');

create policy "biz read stock_movements" on stock_movements for select using (business_id = auth_business_id());
create policy "biz write stock_movements" on stock_movements for insert with check (business_id = auth_business_id());

create policy "biz read customers" on customers for select using (business_id = auth_business_id());
create policy "biz write customers" on customers for insert with check (business_id = auth_business_id());
create policy "biz update customers" on customers for update using (business_id = auth_business_id());
create policy "biz delete customers" on customers for delete using (business_id = auth_business_id() and auth_role() = 'admin');

create policy "biz read sales" on sales for select using (business_id = auth_business_id());
create policy "biz write sales" on sales for insert with check (business_id = auth_business_id());
create policy "biz update sales" on sales for update using (business_id = auth_business_id() and auth_role() = 'admin');

create policy "biz read sale_items" on sale_items for select using (
  sale_id in (select id from sales where business_id = auth_business_id())
);
create policy "biz write sale_items" on sale_items for insert with check (
  sale_id in (select id from sales where business_id = auth_business_id())
);

create policy "biz read payments" on payments for select using (
  sale_id in (select id from sales where business_id = auth_business_id())
);
create policy "biz write payments" on payments for insert with check (
  sale_id in (select id from sales where business_id = auth_business_id())
);

create policy "biz read expenses" on expenses for select using (business_id = auth_business_id());
create policy "biz write expenses" on expenses for insert with check (business_id = auth_business_id());
create policy "biz update expenses" on expenses for update using (business_id = auth_business_id());
create policy "biz delete expenses" on expenses for delete using (business_id = auth_business_id() and auth_role() = 'admin');

-- ============================================================
-- TRIGGER: keep products.updated_at fresh
-- ============================================================
create or replace function touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger products_touch_updated
before update on products
for each row execute function touch_updated_at();

-- ============================================================
-- Done. Next: create your first business + admin user
-- (see SETUP.md for step-by-step instructions).
-- ============================================================

