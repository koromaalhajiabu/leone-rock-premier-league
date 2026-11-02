// Public viewer: matches, league table, teams, players and news.
// Read-only. Uses only data the database already exposes to the public.
(function () {
  var cfg = window.SLFA_CONFIG;
  var db = window.supabase.createClient(cfg.supabaseUrl, cfg.supabasePublishableKey, {
    auth: { persistSession: false, autoRefreshToken: false }
  });
  function $(id) { return document.getElementById(id); }
  function esc(s) { return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
    return { '&':'&amp;', '<':'&lt;', '>':'&gt;', '"':'&quot;', "'":'&#39;' }[c]; }); }
  function fmt(d) { try { return new Date(d).toLocaleString(undefined, { dateStyle: 'medium', timeStyle: 'short' }); } catch (e) { return d || ''; } }
  function badge(url, name) {
    return url ? '<img class="badge" src="' + esc(url) + '" alt="">' : '<span class="badge ph">' + esc((name || '?').charAt(0)) + '</span>';
  }
  function empty(msg) { return '<p class="muted empty">' + msg + '</p>'; }

  // Tabs
  document.querySelectorAll('[data-tab]').forEach(function (btn) {
    btn.addEventListener('click', function () {
      document.querySelectorAll('[data-tab]').forEach(function (b) { b.setAttribute('aria-selected', String(b === btn)); });
      document.querySelectorAll('[data-view]').forEach(function (v) { v.hidden = v.dataset.view !== btn.dataset.tab; });
    });
  });

  // Matches
  function loadMatches() {
    db.from('matches').select('id, match_date, venue, match_status, home_team, away_team, home_score, away_score, motm_name, motm_jersey_number')
      .order('match_date', { ascending: true }).limit(200)
      .then(function (res) {
        if (res.error) { $('matchList').innerHTML = empty('Matches are not available right now.'); return; }
        var rows = res.data || [];
        var up = rows.filter(function (m) { return m.home_score == null; });
        var done = rows.filter(function (m) { return m.home_score != null; }).reverse();
        $('matchList').innerHTML =
          '<h3 class="sub">Upcoming</h3>' + (up.length ? up.map(matchCard).join('') : empty('No upcoming matches yet.')) +
          '<h3 class="sub">Results</h3>' + (done.length ? done.map(matchCard).join('') : empty('No results yet.'));
        wireMatchDetails();
      });
  }
  function matchCard(m) {
    var score = m.home_score == null ? '<span class="vs">v</span>' : '<span class="score">' + esc(m.home_score) + ' – ' + esc(m.away_score) + '</span>';
    var motm = m.motm_name ? '<div class="meta">Man of the Match: ' + esc(m.motm_name) + (m.motm_jersey_number ? ' (#' + esc(m.motm_jersey_number) + ')' : '') + '</div>' : '';
    return '<article class="match" data-match="' + esc(m.id) + '" tabindex="0">' +
      '<div class="meta">' + esc(fmt(m.match_date)) + (m.venue ? ' · ' + esc(m.venue) : '') + '</div>' +
      '<div class="teams"><span>' + esc(m.home_team) + '</span>' + score + '<span>' + esc(m.away_team) + '</span></div>' +
      motm + '<div class="detail" hidden></div></article>';
  }

  // Match details: goals, cards and substitutions, published events only
  function wireMatchDetails() {
    document.querySelectorAll('.match[data-match]').forEach(function (card) {
      card.addEventListener('click', function () { toggleDetail(card); });
      card.addEventListener('keydown', function (e) { if (e.key === 'Enter') toggleDetail(card); });
    });
  }
  function toggleDetail(card) {
    var box = card.querySelector('.detail');
    if (!box.hidden) { box.hidden = true; return; }
    box.hidden = false;
    if (box.dataset.loaded) return;
    box.textContent = 'Loading…';
    db.from('match_events').select('event_type, team_name, player_name, player_off_name, assist_player_name, minute')
      .eq('match_id', String(card.dataset.match))
      .order('minute', { ascending: true })
      .then(function (res) {
        box.dataset.loaded = '1';
        if (res.error) { box.textContent = 'Details are not available right now.'; return; }
        var ev = res.data || [];
        box.innerHTML = ev.length ? ev.map(eventLine).join('') : '<p class="muted">No match events yet.</p>';
      });
  }
  var ICON = { goal:'⚽', yellow_card:'🟨', red_card:'🟥', substitution:'🔁' };
  function eventLine(e) {
    var t = String(e.event_type || '').toLowerCase();
    var who = e.player_name || '';
    var text = t === 'substitution' ? (who + ' on, ' + (e.player_off_name || '') + ' off')
      : t === 'goal' ? (who + (e.assist_player_name ? ' (assist ' + e.assist_player_name + ')' : ''))
      : who;
    return '<div class="ev"><span class="min">' + esc(e.minute) + "'</span><span class=\"ico\">" + (ICON[t] || '•') + '</span><span class="etxt">' + esc(text) + '<small>' + esc(e.team_name || '') + '</small></span></div>';
  }

  // League table
  function loadTable() {
    db.from('league_standings').select('pos, club, mp, w, d, l, gf, ga, pts').order('pos', { ascending: true })
      .then(function (res) {
        if (res.error || !(res.data || []).length) { $('tableBody').innerHTML = '<tr><td colspan="9">' + (res.error ? 'The table is not available right now.' : 'The table will appear after the first results.') + '</td></tr>'; return; }
        $('tableBody').innerHTML = res.data.map(function (r) {
          return '<tr><td>' + esc(r.pos) + '</td><td class="club">' + esc(r.club) + '</td><td>' + esc(r.mp) + '</td><td>' + esc(r.w) + '</td><td>' + esc(r.d) + '</td><td>' + esc(r.l) + '</td><td>' + esc(r.gf) + '</td><td>' + esc(r.ga) + '</td><td class="pts">' + esc(r.pts) + '</td></tr>';
        }).join('');
      });
  }

  // Teams
  function loadTeams() {
    db.from('league_clubs').select('id, club_name, logo_url').eq('is_active', true).order('club_name')
      .then(function (res) {
        if (res.error || !(res.data || []).length) { $('teamGrid').innerHTML = empty('Teams will appear here once they are added.'); return; }
        $('teamGrid').innerHTML = res.data.map(function (c) {
          return '<div class="team">' + badge(c.logo_url, c.club_name) + '<span>' + esc(c.club_name) + '</span></div>';
        }).join('');
      });
  }

  // Players: top scorers, assists, clean sheets
  function list(rows, label, valueKey) {
    if (!rows || !rows.length) return empty('No ' + label + ' yet.');
    return rows.map(function (r, i) {
      return '<div class="row"><span class="rank">' + (i + 1) + '</span>' + badge(r.photo_url, r.name) +
        '<span class="pname">' + esc(r.name) + '<small>' + esc(r.club) + '</small></span><span class="pval">' + esc(r[valueKey]) + '</span></div>';
    }).join('');
  }
  function loadPlayers() {
    db.from('top_scorers').select('player, club, goals, photo_url').order('goals', { ascending: false }).limit(10)
      .then(function (res) {
        $('scorers').innerHTML = list((res.data || []).map(function (r) { return { name: r.player, club: r.club, photo_url: r.photo_url, goals: r.goals }; }), 'goals', 'goals');
      });
    db.from('top_assists').select('player, club, assists, photo_url').order('assists', { ascending: false }).limit(10)
      .then(function (res) {
        $('assists').innerHTML = list((res.data || []).map(function (r) { return { name: r.player, club: r.club, photo_url: r.photo_url, assists: r.assists }; }), 'assists', 'assists');
      });
    db.from('clean_sheets').select('goalkeeper, club, clean_sheets, photo_url').order('clean_sheets', { ascending: false }).limit(10)
      .then(function (res) {
        $('cleanSheets').innerHTML = list((res.data || []).map(function (r) { return { name: r.goalkeeper, club: r.club, photo_url: r.photo_url, sheets: r.clean_sheets }; }), 'clean sheets', 'sheets');
      });
  }

  // News and media (published only)
  function loadNews() {
    db.from('media_posts').select('id, category, title, body, image_url, video_url, published_at, status')
      .eq('status', 'PUBLISHED').order('published_at', { ascending: false }).limit(20)
      .then(function (res) {
        if (res.error || !(res.data || []).length) { $('newsList').innerHTML = empty('No news yet.'); return; }
        $('newsList').innerHTML = res.data.map(function (p) {
          return '<article class="news">' +
            (p.image_url ? '<img src="' + esc(p.image_url) + '" alt="">' : '') +
            '<div class="meta">' + esc(p.category || 'News') + ' · ' + esc(fmt(p.published_at)) + '</div>' +
            '<h3>' + esc(p.title) + '</h3>' +
            '<p>' + esc(p.body) + '</p>' +
            (p.video_url ? '<a href="' + esc(p.video_url) + '" target="_blank" rel="noopener">Watch video</a>' : '') +
            '<button class="share" data-title="' + esc(p.title) + '">Share</button></article>';
        }).join('');
        wireShare();
      });
  }

  // Sharing
  function wireShare() {
    document.querySelectorAll('.share').forEach(function (b) {
      b.addEventListener('click', function () { shareText(b.dataset.title); });
    });
  }
  function shareText(text) {
    var data = { title: 'SLFA League', text: text, url: location.href };
    if (navigator.share) { navigator.share(data).catch(function () {}); }
    else if (navigator.clipboard) { navigator.clipboard.writeText(text + ' ' + location.href); alert('Link copied.'); }
  }
  $('shareApp').addEventListener('click', function () { shareText('Follow the league on the SLFA League app'); });

  // ALERTS: anyone can subscribe on their phone or computer
  function urlBase64ToUint8Array(b64) {
    var pad = '='.repeat((4 - b64.length % 4) % 4);
    var raw = atob((b64 + pad).replace(/-/g, '+').replace(/_/g, '/'));
    return Uint8Array.from(raw, function (c) { return c.charCodeAt(0); });
  }
  function setAlertStatus(msg) { var el = $('alertStatus'); if (el) el.textContent = msg; }
  var alertBtn = $('alertBtn');
  if (alertBtn) {
    if (!('serviceWorker' in navigator) || !('PushManager' in window) || !('Notification' in window)) {
      alertBtn.disabled = true;
      setAlertStatus('Alerts are not supported on this browser. On iPhone, add the app to your Home Screen first.');
    }
    alertBtn.addEventListener('click', function () {
      setAlertStatus('Turning on alerts…');
      Notification.requestPermission().then(function (perm) {
        if (perm !== 'granted') { setAlertStatus('Alerts are off. You can allow them in your browser settings.'); return; }
        return navigator.serviceWorker.register('sw.js').then(function (reg) {
          return navigator.serviceWorker.ready.then(function () {
            return reg.pushManager.getSubscription().then(function (sub) {
              return sub || reg.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: urlBase64ToUint8Array(cfg.vapidPublicKey) });
            });
          });
        }).then(function (sub) {
          var j = sub.toJSON();
          return db.from('push_subscriptions').insert([{ user_id: null, endpoint: j.endpoint, p256dh: j.keys.p256dh, auth: j.keys.auth }]).then(function (res) {
            if (res.error && res.error.code !== '23505') throw res.error;
            setAlertStatus('Alerts are on for this device.');
          });
        }).catch(function () { setAlertStatus('Could not turn on alerts. Please try again.'); });
      });
    });
  }

  refreshAll();
  subscribeLive();
})();
