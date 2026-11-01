-- ═══════════════════════════════════════════════════════════
-- 밀양손씨 목사공파 가계도 — Supabase 스키마 (로그인 없는 공개 편집판)
-- 정책: 누구나 읽기 + 누구나 쓰기 (로그인 불필요)
-- ⚠ 링크를 아는 사람은 누구나 수정할 수 있습니다. 가족 내부용 전제.
-- ═══════════════════════════════════════════════════════════

-- ── 사람 ──────────────────────────────────────────────────
create table if not exists people (
  id          text primary key,
  gen         int  not null,
  name        text,
  ord         text,
  father_id   text,
  sex         text check (sex in ('m','f')),
  birth       text,
  death       text,
  tel         text,
  note        text,
  conf        text not null default 'unknown'
              check (conf in ('sure','guess','unknown')),
  updated_at  timestamptz not null default now()
);
create index if not exists people_father_idx on people(father_id);
create index if not exists people_gen_idx    on people(gen);

alter table people drop constraint if exists people_not_self_parent;
alter table people add constraint people_not_self_parent check (id <> father_id);

-- ── 순환 참조 방지 ────────────────────────────────────────
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
end $$ language plpgsql;

drop trigger if exists trg_no_cycle on people;
create trigger trg_no_cycle before insert or update of father_id on people
  for each row execute function check_no_cycle();

create or replace function touch_updated() returns trigger as $$
begin new.updated_at := now(); return new; end $$ language plpgsql;
drop trigger if exists trg_touch on people;
create trigger trg_touch before update on people
  for each row execute function touch_updated();

-- ── RLS: 누구나(anon) 읽기+쓰기 ───────────────────────────
alter table people enable row level security;

drop policy if exists people_read  on people;
drop policy if exists people_write on people;
drop policy if exists people_all   on people;
create policy people_all on people for all
  using (true) with check (true);

grant select, insert, update, delete on people to anon, authenticated;

-- ═══════════════════════════════════════════════════════════
-- 끝. 로그인·편집자·전화번호가리기·변경이력 전부 없음 (공개 편집판)
-- ═══════════════════════════════════════════════════════════
