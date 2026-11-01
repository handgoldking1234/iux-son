-- ═══════════════════════════════════════════════════════════
-- 밀양손씨 목사공파 가계도 — Supabase 스키마
-- 정책: 보기는 누구나(전화번호 제외) / 편집은 카카오 로그인
-- ═══════════════════════════════════════════════════════════

-- ── 1. 사람 ────────────────────────────────────────────────
create table if not exists people (
  id          text primary key,                    -- 'p001'
  gen         int  not null,                       -- 대(代)
  name        text,                                -- null = 미상
  ord         text,                                -- 서열 ('1','2'…)
  father_id   text references people(id) on delete set null,
  sex         text check (sex in ('m','f')),
  birth       text,
  death       text,
  tel         text,                                -- ★ 비로그인에게 노출 금지
  note        text,
  conf        text not null default 'unknown'
              check (conf in ('sure','guess','unknown')),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  updated_by  uuid references auth.users(id)
);
create index if not exists people_father_idx on people(father_id);
create index if not exists people_gen_idx    on people(gen);

-- 자기 자신이 아버지가 되는 것 방지
alter table people drop constraint if exists people_not_self_parent;
alter table people add constraint people_not_self_parent check (id <> father_id);

-- ── 2. 편집 허용 명단 ──────────────────────────────────────
-- 카카오 로그인만으로는 부족함: 아무나 가입할 수 있으므로
-- 이 표에 등록된 사람만 편집 가능
create table if not exists editors (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  label      text,                                 -- '관리자', '창오' 등
  role       text not null default 'editor'
             check (role in ('admin','editor')),
  added_at   timestamptz not null default now()
);

-- ── 3. 변경 이력 (누가 뭘 고쳤나) ──────────────────────────
create table if not exists changes (
  id         bigserial primary key,
  person_id  text,
  action     text not null,                        -- insert/update/delete
  before     jsonb,
  after      jsonb,
  user_id    uuid references auth.users(id),
  at         timestamptz not null default now()
);
create index if not exists changes_at_idx on changes(at desc);

-- ── 4. 순환 참조 방지 ──────────────────────────────────────
create or replace function check_no_cycle() returns trigger as $$
declare cur text; depth int := 0;
begin
  if new.father_id is null then return new; end if;
  if new.father_id = new.id then
    raise exception '자기 자신을 아버지로 지정할 수 없습니다';
  end if;
  cur := new.father_id;
  while cur is not null and depth < 200 loop
    if cur = new.id then
      raise exception '순환 참조: %는 자기 자손 아래로 갈 수 없습니다', new.id;
    end if;
    select father_id into cur from people where id = cur;
    depth := depth + 1;
  end loop;
  return new;
end $$ language plpgsql security definer set search_path = public;

drop trigger if exists trg_no_cycle on people;
create trigger trg_no_cycle before insert or update of father_id on people
  for each row execute function check_no_cycle();

-- ── 5. updated_at 자동 갱신 + 이력 기록 ────────────────────
create or replace function touch_and_log() returns trigger as $$
begin
  if TG_OP = 'DELETE' then
    insert into changes(person_id, action, before, user_id)
      values (old.id, 'delete', to_jsonb(old), auth.uid());
    return old;
  end if;
  new.updated_at := now();
  new.updated_by := auth.uid();
  if TG_OP = 'INSERT' then
    insert into changes(person_id, action, after, user_id)
      values (new.id, 'insert', to_jsonb(new), auth.uid());
  else
    insert into changes(person_id, action, before, after, user_id)
      values (new.id, 'update', to_jsonb(old), to_jsonb(new), auth.uid());
  end if;
  return new;
end $$ language plpgsql security definer set search_path = public;

drop trigger if exists trg_touch on people;
create trigger trg_touch before insert or update on people
  for each row execute function touch_and_log();
drop trigger if exists trg_del on people;
create trigger trg_del after delete on people
  for each row execute function touch_and_log();

-- ── 6. RLS ─────────────────────────────────────────────────
alter table people  enable row level security;
alter table editors enable row level security;
alter table changes enable row level security;

create or replace function is_editor() returns boolean as $$
  select exists (select 1 from editors where user_id = auth.uid());
$$ language sql security definer stable set search_path = public;
-- security definer 함수는 소유자 권한으로 돌아 editors 의 RLS를 우회한다.
-- 이게 없으면 편집자 본인도 자기가 편집자인 걸 확인하지 못해 전부 차단된다.

-- people: 읽기는 누구나 / 쓰기는 편집자만
drop policy if exists people_read on people;
create policy people_read on people for select using (true);

drop policy if exists people_write on people;
create policy people_write on people for all
  using (is_editor()) with check (is_editor());

-- editors 정책 주의:
--   여기서 is_editor() 나 editors 하위쿼리를 쓰면 정책이 자기 자신을 다시 불러
--   'infinite recursion detected in policy' 가 나고, is_editor()가 조용히 false가 되어
--   모든 편집이 막힌다. 그래서 정책 안에서는 auth.uid() 직접 비교만 쓴다.
create or replace function is_admin() returns boolean as $$
  select exists (select 1 from editors where user_id = auth.uid() and role = 'admin');
$$ language sql security definer stable set search_path = public;

drop policy if exists editors_read on editors;
create policy editors_read on editors for select
  using (user_id = auth.uid());          -- 본인 행만. 재귀 없음

drop policy if exists editors_admin_ins on editors;
create policy editors_admin_ins on editors for insert with check (is_admin());
drop policy if exists editors_admin_upd on editors;
create policy editors_admin_upd on editors for update using (is_admin()) with check (is_admin());
drop policy if exists editors_admin_del on editors;
create policy editors_admin_del on editors for delete using (is_admin());

-- changes: 편집자만 열람
drop policy if exists changes_read on changes;
create policy changes_read on changes for select using (is_editor());

-- ── 7. 전화번호 가리기 ─────────────────────────────────────
-- 비로그인/비편집자는 tel 을 아예 못 받는 뷰
create or replace view people_public
with (security_invoker = true) as
select
  id, gen, name, ord, father_id, sex, birth, death, note, conf,
  case when is_editor() then tel else null end as tel,
  (tel is not null) as has_tel,        -- 있다는 표시만
  updated_at
from people;

grant select on people_public to anon, authenticated;
grant select on people  to anon, authenticated;
grant insert, update, delete on people to authenticated;
grant select on editors to authenticated;
grant select on changes to authenticated;
grant usage, select on sequence changes_id_seq to authenticated;

-- ═══════════════════════════════════════════════════════════
-- 첫 관리자 등록 (카카오로 한 번 로그인한 뒤 실행)
--   select id, email from auth.users;   ← 여기서 본인 uuid 확인
--   insert into editors(user_id, label, role)
--     values ('여기에-본인-uuid', '관리자', 'admin');
-- ═══════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════
-- 8. 편집자 관리용 (앱에서 SQL 없이 추가/삭제)
-- ═══════════════════════════════════════════════════════════

-- 로그인한 적 있는 사람 목록 (admin만 조회 가능)
-- auth.users 는 직접 읽을 수 없으므로 security definer 로 감싼다
create or replace function list_accounts()
returns table (
  user_id  uuid,
  display  text,
  provider text,
  is_editor boolean,
  role     text,
  joined   timestamptz
) as $$
  select
    u.id,
    coalesce(
      u.raw_user_meta_data->>'name',
      u.raw_user_meta_data->>'full_name',
      u.raw_user_meta_data->>'nickname',
      split_part(u.email,'@',1),
      '이름없음'
    )::text,
    coalesce(u.raw_app_meta_data->>'provider','email')::text,
    (e.user_id is not null),
    coalesce(e.role,'')::text,
    u.created_at
  from auth.users u
  left join editors e on e.user_id = u.id
  where is_admin()                      -- admin이 아니면 0행
  order by u.created_at;
$$ language sql security definer stable set search_path = public;

grant execute on function list_accounts() to authenticated;

-- 편집자 추가/삭제 (admin만)
create or replace function set_editor(target uuid, make_editor boolean, lbl text default null)
returns void as $$
begin
  if not is_admin() then
    raise exception '관리자만 편집자를 변경할 수 있습니다';
  end if;
  if make_editor then
    insert into editors(user_id, label, role)
      values (target, coalesce(lbl,'편집자'), 'editor')
      on conflict (user_id) do update set label = coalesce(excluded.label, editors.label);
  else
    if exists (select 1 from editors where user_id = target and role = 'admin') then
      if (select count(*) from editors where role = 'admin') <= 1 then
        raise exception '마지막 관리자는 삭제할 수 없습니다';
      end if;
    end if;
    delete from editors where user_id = target;
  end if;
end $$ language plpgsql security definer set search_path = public;

grant execute on function set_editor(uuid, boolean, text) to authenticated;
