-- Standings that follow the competition rules (points per result, tie-breaker order, positions).
-- Reads the current season's "League" row in competition_rules. If there is none, it uses 3 / 1 / 0
-- and goal difference then goals scored. Head-to-head is not applied yet.
-- Safe to run more than once. Changes only the standings calculation.

create or replace function public.recalculate_leone_rock_standings()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    rule record;
    v_win integer := 3;
    v_draw integer := 1;
    v_loss integer := 0;
    v_tiebreak text[] := array['goal_difference', 'goals_for'];
    v_gd_first boolean;
begin
    select r.points_win, r.points_draw, r.points_loss, r.tiebreaker_order
      into rule
    from public.competition_rules r
    join public.seasons s on s.id = r.season_id
    where s.is_current and r.competition_name = 'League'
    limit 1;

    if found then
        v_win := coalesce(rule.points_win, v_win);
        v_draw := coalesce(rule.points_draw, v_draw);
        v_loss := coalesce(rule.points_loss, v_loss);
        if rule.tiebreaker_order is not null then
            v_tiebreak := rule.tiebreaker_order;
        end if;
    end if;

    v_gd_first := coalesce(array_position(v_tiebreak, 'goal_difference'), 99)
                  <= coalesce(array_position(v_tiebreak, 'goals_for'), 99);

    insert into public.league_standings (club, mp, w, d, l, gf, ga, pts)
    with teams as (
        select trim(home_team) as club, home_goals as gf, away_goals as ga
        from public.match_results where status = 'CONFIRMED'
        union all
        select trim(away_team) as club, away_goals as gf, home_goals as ga
        from public.match_results where status = 'CONFIRMED'
    ),
    totals as (
        select club,
               count(*)::integer as mp,
               count(*) filter (where gf > ga)::integer as w,
               count(*) filter (where gf = ga)::integer as d,
               count(*) filter (where gf < ga)::integer as l,
               coalesce(sum(gf), 0)::integer as gf,
               coalesce(sum(ga), 0)::integer as ga,
               (count(*) filter (where gf > ga) * v_win
                 + count(*) filter (where gf = ga) * v_draw
                 + count(*) filter (where gf < ga) * v_loss)::integer as pts
        from teams
        group by club
    )
    select club, mp, w, d, l, gf, ga, pts from totals
    on conflict (club) do update set
        mp = excluded.mp, w = excluded.w, d = excluded.d, l = excluded.l,
        gf = excluded.gf, ga = excluded.ga, pts = excluded.pts;

    -- Clubs without any confirmed results stay in the table with zero totals.
    update public.league_standings s
    set mp = 0, w = 0, d = 0, l = 0, gf = 0, ga = 0, pts = 0
    where not exists (
        select 1 from public.match_results r
        where r.status = 'CONFIRMED'
          and (lower(trim(r.home_team)) = lower(trim(s.club))
            or lower(trim(r.away_team)) = lower(trim(s.club)))
    );

    -- Positions: points first, then the tie-breakers in the order the rules set.
    update public.league_standings s
    set pos = ranked.rn
    from (
        select club,
               row_number() over (
                   order by pts desc,
                            case when v_gd_first then gf - ga else gf end desc,
                            case when v_gd_first then gf else gf - ga end desc,
                            club
               )::integer as rn
        from public.league_standings
    ) ranked
    where s.club = ranked.club;
end;
$$;

-- Keep the trigger functions private, as before.
revoke all on function public.recalculate_leone_rock_standings() from public, anon, authenticated;

-- Refresh standings from the confirmed results that already exist.
select public.recalculate_leone_rock_standings();
