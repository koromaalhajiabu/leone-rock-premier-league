// Administration tools, shown after sign-in and based on the signed-in role.
// Super Admin: fixtures, results, news and player approval. Media Officer: news posts. Club Managers: squads.
(function () {
  var db = window.slfaDb;
  function $(id) { return document.getElementById(id); }
  function esc(s) { return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
    return { '&':'&amp;', '<':'&lt;', '>':'&gt;', '"':'&quot;', "'":'&#39;' }[c]; }); }
  function box() {
    var b = $('roleTools');
    if (!b) { b = document.createElement('div'); b.id = 'roleTools'; $('signedIn').insertBefore(b, $('signedIn').querySelector('.btns')); }
    return b;
  }
  function msg(text) { var m = $('roleMsg'); if (m) m.textContent = text; }
  function input(id, label, type, extra) {
    return '<label for="' + id + '">' + label + '</label><input id="' + id + '" type="' + (type || 'text') + '" ' + (extra || '') + '>';
  }

  function currentUser() {
    return db.auth.getUser().then(function (u) {
      if (!u.data || !u.data.user) return null;
      return db.from('user_profiles').select('id, system_role, status, full_name, email, club_id').eq('id', u.data.user.id).maybeSingle()
        .then(function (r) { return r.data && String(r.data.status).toLowerCase() === 'active' ? r.data : null; });
    });
  }

  function render() {
    currentUser().then(function (p) {
      if (!p) { var old = $('roleTools'); if (old) old.remove(); return; }
      var role = String(p.system_role).toUpperCase();
      if (role === 'SUPER_ADMIN') return superAdmin(p);
      if (role === 'MEDIA_OFFICER') return mediaOfficer(p);
      if (role === 'REFEREE') return referee(p);
      if (role === 'DEVELOPER') return developer(p);
      if (role === 'CLUB_ADMIN') return clubManager(p);
      box().innerHTML = '';
    });
  }

  // ---------- SUPER ADMIN ----------
  function superAdmin(p) {
    box().innerHTML =
      '<h2 class="rt">Add a fixture</h2>' +
      input('fxHome', 'Home team') + input('fxAway', 'Away team') +
      input('fxDate', 'Date and time', 'datetime-local') + input('fxVenue', 'Venue') +
      '<div class="btns"><button class="primary" id="fxSave">Add fixture</button></div>' +
      '<h2 class="rt">Enter a result</h2>' +
      '<label for="resMatch">Match</label><select id="resMatch"><option value="">Loading matches…</option></select>' +
      '<div class="scores"><input id="resHome" type="number" min="0" placeholder="Home"><span>–</span><input id="resAway" type="number" min="0" placeholder="Away"></div>' +
      '<div class="btns"><button class="primary" id="resSave">Record result</button></div>' +
      '<h2 class="rt">Live match</h2>' +
      '<label for="lvMatch">Match</label><select id="lvMatch"><option value="">Loading matches…</option></select>' +
      '<div class="btns"><button class="secondary" id="lvStart">Start match</button><button class="primary" id="lvEnd">End match</button></div>' +
      '<div id="lvPanel" class="hidden">' +
        '<label for="lvTeam">Team</label><select id="lvTeam"></select>' +
        input('lvPlayer', 'Player') + input('lvAssist', 'Assist (optional)') + input('lvOff', 'Player off (substitutions only)') +
        '<label for="lvType">Event</label><select id="lvType"><option value="goal">Goal</option><option value="yellow_card">Yellow card</option><option value="red_card">Red card</option><option value="substitution">Substitution</option></select>' +
        input('lvMinute', 'Minute', 'number', 'min="0" max="130"') +
        '<div class="btns"><button class="primary" id="lvAdd">Record event</button></div>' +
      '</div>' +
      '<h2 class="rt">Assign a referee</h2>' +
      '<label for="asMatch">Match</label><select id="asMatch"><option value="">Loading…</option></select>' +
      '<label for="asRef">Referee</label><select id="asRef"><option value="">Loading referees…</option></select>' +
      '<div class="btns"><button class="primary" id="asSave">Assign</button></div>' +
      '<h2 class="rt">Final scores awaiting approval</h2><div id="pendingResults" class="muted">Loading…</div>' +
      '<h2 class="rt">News awaiting approval</h2><div id="reviewList" class="muted">Loading…</div>' +
      '<h2 class="rt">Player registrations awaiting approval</h2><div id="squadReview" class="muted">Loading…</div>' +
      '<div class="status" id="roleMsg"></div>';

    $('fxSave').addEventListener('click', function () {
      var h = $('fxHome').value.trim(), a = $('fxAway').value.trim(), d = $('fxDate').value, v = $('fxVenue').value.trim();
      if (!h || !a || !d) { msg('Enter both teams and the date.'); return; }
      db.from('seasons').select('id').order('id', { ascending: false }).limit(1).maybeSingle().then(function (s) {
        return db.from('matches').insert([{ home_team: h, away_team: a, match_date: new Date(d).toISOString(), venue: v || null, season_id: s.data ? s.data.id : null }]);
      }).then(function (r) {
        if (r.error) { msg(r.error.message); return; }
        msg('Fixture added.'); $('fxHome').value = ''; $('fxAway').value = ''; $('fxVenue').value = ''; loadMatchesForResult();
      });
    });

    loadMatchesForResult();
    $('resSave').addEventListener('click', function () {
      var id = $('resMatch').value, h = parseInt($('resHome').value, 10), a = parseInt($('resAway').value, 10);
      if (!id || isNaN(h) || isNaN(a)) { msg('Choose a match and enter both scores.'); return; }
      db.rpc('record_match_result', { p_match_id: Number(id), p_home: h, p_away: a }).then(function (r) {
        if (r.error) { msg(r.error.message); return; }
        msg('Result recorded and the table updated.'); $('resHome').value = ''; $('resAway').value = ''; loadMatchesForResult();
      });
    });

    loadReview();
    loadSquadReview();
    wireLive();
    loadAssignOptions();
    loadPendingResults();
    $('asSave').addEventListener('click', function () {
      var m = $('asMatch').value, r = $('asRef').value;
      if (!m || !r) { msg('Choose a match and a referee.'); return; }
      db.auth.getUser().then(function (u) {
        return db.from('match_referee_assignments').insert([{ match_id: Number(m), referee_user_id: r, assigned_by: u.data.user.id, official_role: 'MAIN', assignment_status: 'ACTIVE' }]);
      }).then(function (res) { msg(res.error ? res.error.message : 'Referee assigned.'); });
    });
  }

  function loadAssignOptions() {
    db.from('matches').select('id, home_team, away_team, match_date').order('match_date', { ascending: false }).limit(60).then(function (r) {
      $('asMatch').innerHTML = '<option value="">Choose a match…</option>' + (r.data || []).map(function (m) {
        return '<option value="' + esc(m.id) + '">' + esc(m.home_team) + ' v ' + esc(m.away_team) + '</option>'; }).join('');
    });
    db.from('user_profiles').select('id, full_name, email').eq('system_role', 'REFEREE').then(function (r) {
      $('asRef').innerHTML = '<option value="">Choose a referee…</option>' + (r.data || []).map(function (u) {
        return '<option value="' + esc(u.id) + '">' + esc(u.full_name || u.email) + '</option>'; }).join('') || '<option value="">No referees yet</option>';
    });
  }

  function loadPendingResults() {
    db.from('match_results').select('id, home_team, away_team, home_goals, away_goals, recorded_by').eq('status', 'PENDING').order('id', { ascending: true })
      .then(function (r) {
        var rows = r.data || [];
        $('pendingResults').innerHTML = rows.length ? rows.map(function (x) {
          return '<div class="post"><strong>' + esc(x.home_team) + ' ' + x.home_goals + ' – ' + x.away_goals + ' ' + esc(x.away_team) + '</strong>' +
            '<div class="btns"><button class="primary" data-approve="' + x.id + '">Approve</button><button class="secondary" data-reject="' + x.id + '">Reject</button></div></div>';
        }).join('') : 'No final scores waiting.';
        document.querySelectorAll('[data-approve]').forEach(function (b) {
          b.addEventListener('click', function () {
            db.rpc('approve_match_result', { p_result_id: Number(b.dataset.approve) }).then(function (res) {
              msg(res.error ? res.error.message : 'Approved. The table is updated.'); loadPendingResults(); loadMatchesForResult(); });
          });
        });
        document.querySelectorAll('[data-reject]').forEach(function (b) {
          b.addEventListener('click', function () {
            if (!confirm('Reject this score? The referee will need to send it again.')) return;
            db.from('match_results').delete().eq('id', Number(b.dataset.reject)).then(function (res) {
              msg(res.error ? res.error.message : 'Rejected.'); loadPendingResults(); });
          });
        });
      });
  }

  // Live match: start, record events, end (end saves the score to the table)
  var liveMatch = null;
  function wireLive() {
    loadLiveOptions();
    $('lvMatch').addEventListener('change', function () { liveMatch = null; loadLiveMatch(this.value); });
    $('lvStart').addEventListener('click', function () {
      var id = $('lvMatch').value; if (!id) { msg('Choose a match.'); return; }
      db.from('matches').update({ match_status: 'LIVE' }).eq('id', id).then(function (r) {
        msg(r.error ? r.error.message : 'Match is live.'); loadLiveMatch(id); loadLiveOptions();
      });
    });
    $('lvEnd').addEventListener('click', function () {
      var id = $('lvMatch').value; if (!id || !liveMatch) { msg('Choose a live match first.'); return; }
      var hg = goalsFor(liveMatch.home_team), ag = goalsFor(liveMatch.away_team);
      if (!confirm('End the match at ' + liveMatch.home_team + ' ' + hg + ' – ' + ag + ' ' + liveMatch.away_team + '? This saves the result to the table.')) return;
      db.rpc('record_match_result', { p_match_id: Number(id), p_home: hg, p_away: ag }).then(function (r) {
        if (r.error) { msg(r.error.message); return; }
        return db.from('matches').update({ match_status: 'FINISHED' }).eq('id', id).then(function () {
          msg('Match finished and the table updated.'); liveMatch = null; loadLiveOptions(); loadLiveMatch('');
        });
      });
    });
    $('lvAdd').addEventListener('click', function () {
      if (!liveMatch) { msg('Choose a live match.'); return; }
      var type = $('lvType').value, player = $('lvPlayer').value.trim(), minute = parseInt($('lvMinute').value, 10);
      if (!player || isNaN(minute)) { msg('Enter the player and the minute.'); return; }
      if (type === 'substitution' && !$('lvOff').value.trim()) { msg('Enter the player coming off.'); return; }
      db.auth.getUser().then(function (u) {
        return db.from('match_events').insert([{
          match_id: String($('lvMatch').value), event_type: type, team_name: $('lvTeam').value, player_name: player,
          assist_player_name: $('lvAssist').value.trim() || null, player_off_name: $('lvOff').value.trim() || null,
          minute: minute, recorded_by: u.data.user.id, recorded_at: new Date().toISOString(), published_at: new Date().toISOString()
        }]);
      }).then(function (r) {
        if (r.error) { msg(r.error.message); return; }
        msg('Recorded.'); ['lvPlayer','lvAssist','lvOff','lvMinute'].forEach(function (x) { $(x).value = ''; });
        loadLiveMatch($('lvMatch').value);
      });
    });
  }
  var liveEvents = [];
  function goalsFor(team) { return liveEvents.filter(function (e) { return e.event_type === 'goal' && e.team_name === team; }).length; }
  function loadLiveOptions() {
    db.from('matches').select('id, home_team, away_team, match_status, match_date').order('match_date', { ascending: false }).limit(60)
      .then(function (r) {
        var rows = r.data || [];
        var cur = $('lvMatch').value;
        $('lvMatch').innerHTML = '<option value="">Choose a match…</option>' + rows.map(function (m) {
          var tag = m.match_status === 'LIVE' ? ' · LIVE' : '';
          return '<option value="' + esc(m.id) + '">' + esc(m.home_team) + ' v ' + esc(m.away_team) + tag + '</option>';
        }).join('');
        if (cur) $('lvMatch').value = cur;
      });
  }
  function loadLiveMatch(id) {
    if (!id) { $('lvPanel').classList.add('hidden'); return; }
    db.from('matches').select('id, home_team, away_team, match_status').eq('id', id).maybeSingle().then(function (r) {
      liveMatch = r.data;
      if (!liveMatch) return;
      $('lvTeam').innerHTML = '<option>' + esc(liveMatch.home_team) + '</option><option>' + esc(liveMatch.away_team) + '</option>';
      $('lvPanel').classList.toggle('hidden', liveMatch.match_status !== 'LIVE');
      db.from('match_events').select('event_type, team_name, player_name, minute').eq('match_id', String(id)).order('minute', { ascending: true })
        .then(function (e) { liveEvents = e.data || []; });
    });
  }

  function loadMatchesForResult() {
    db.from('matches').select('id, match_date, home_team, away_team, home_score').order('match_date', { ascending: false }).limit(60)
      .then(function (r) {
        var rows = r.data || [];
        $('resMatch').innerHTML = '<option value="">Choose a match…</option>' + rows.map(function (m) {
          return '<option value="' + esc(m.id) + '">' + esc(m.home_team) + ' v ' + esc(m.away_team) + (m.home_score != null ? ' (' + m.home_score + ' – ' + m.away_score + ')' : '') + '</option>';
        }).join('');
      });
  }

  function loadReview() {
    db.from('media_posts').select('id, title, category, body, created_by_name, submitted_at').eq('status', 'SUBMITTED').order('submitted_at', { ascending: true })
      .then(function (r) {
        var rows = r.data || [];
        $('reviewList').innerHTML = rows.length ? rows.map(function (p) {
          return '<div class="post"><div class="muted">' + esc(p.category) + ' · by ' + esc(p.created_by_name || 'Media Officer') + '</div>' +
            '<strong>' + esc(p.title) + '</strong><p>' + esc(p.body) + '</p>' +
            '<div class="btns"><button class="primary" data-pub="' + esc(p.id) + '">Publish</button><button class="secondary" data-ret="' + esc(p.id) + '">Return</button></div></div>';
        }).join('') : 'Nothing waiting for approval.';
        document.querySelectorAll('[data-pub]').forEach(function (b) { b.addEventListener('click', function () { decide(b.dataset.pub, 'PUBLISHED'); }); });
        document.querySelectorAll('[data-ret]').forEach(function (b) { b.addEventListener('click', function () { decide(b.dataset.ret, 'RETURNED'); }); });
      });
  }
  function decide(id, status) {
    var upd = { status: status };
    if (status === 'PUBLISHED') upd.published_at = new Date().toISOString();
    db.auth.getUser().then(function (u) {
      upd.reviewed_by = u.data.user.id; upd.reviewed_at = new Date().toISOString();
      return db.from('media_posts').update(upd).eq('id', id);
    }).then(function (r) {
      if (r.error) { msg(r.error.message); return; }
      msg(status === 'PUBLISHED' ? 'Published.' : 'Returned to the Media Officer.'); loadReview();
    });
  }

  // ---------- CLUB MANAGER: squad ----------
  function clubManager(p) {
    if (!p.club_id) {
      box().innerHTML = '<h2 class="rt">Club squad</h2><p class="muted">Your account is not linked to a club yet. The Technical Director needs to assign your club.</p>';
      return;
    }
    box().innerHTML =
      '<h2 class="rt">Club squad</h2><div id="clubName" class="muted">Loading club…</div>' +
      '<h2 class="rt">Add a player</h2>' +
      input('spName', 'Full name') + input('spNin', 'National ID number') + input('spDob', 'Date of birth', 'date') +
      '<label for="spPos">Position</label><select id="spPos"><option value="GK">Goalkeeper</option><option value="DF">Defender</option><option value="MF">Midfielder</option><option value="FW">Forward</option></select>' +
      '<div class="btns"><button class="primary" id="spSave">Add player</button></div>' +
      '<h2 class="rt">Your players</h2><div id="squadList" class="muted">Loading…</div>' +
      '<div class="status" id="roleMsg"></div>';
    db.from('league_clubs').select('club_name').eq('id', p.club_id).maybeSingle().then(function (r) {
      $('clubName').innerHTML = '<strong>' + esc(r.data ? r.data.club_name : 'Your club') + '</strong>';
    });
    $('spSave').addEventListener('click', function () { addPlayer(p); });
    loadSquad(p);
  }
  function addPlayer(p) {
    var name = $('spName').value.trim(), nin = $('spNin').value.trim(), dob = $('spDob').value, pos = $('spPos').value;
    if (!name || !nin || !dob) { msg('Enter the name, ID number and date of birth.'); return; }
    db.auth.getUser().then(function (u) {
      return db.from('club_squad').insert({ player_name: name, player_nin: nin, date_of_birth: dob, position: pos,
        status: 'Active', registration_status: 'Pending', club_id: p.club_id, created_by: u.data.user.id });
    }).then(function (r) {
      if (r.error) { msg(r.error.message); return; }
      msg('Player added. The Super Admin will approve the registration.');
      ['spName', 'spNin', 'spDob'].forEach(function (x) { $(x).value = ''; });
      loadSquad(p);
    });
  }
  function loadSquad(p) {
    db.from('club_squad').select('id, player_name, position, status, registration_status').eq('club_id', p.club_id).order('player_name')
      .then(function (r) {
        var rows = r.data || [];
        $('squadList').innerHTML = rows.length ? rows.map(function (x) {
          var on = String(x.status) === 'Active';
          return '<div class="post"><strong>' + esc(x.player_name) + '</strong> <span class="muted">' + esc(x.position) + '</span>' +
            '<div class="muted">' + esc(x.registration_status) + ' · ' + (on ? 'Active' : 'Inactive') + '</div>' +
            '<div class="btns"><button class="small" data-toggle="' + esc(x.id) + '" data-next="' + (on ? 'Inactive' : 'Active') + '">' + (on ? 'Mark inactive' : 'Mark active') + '</button></div></div>';
        }).join('') : 'No players yet.';
        document.querySelectorAll('[data-toggle]').forEach(function (b) {
          b.addEventListener('click', function () {
            db.from('club_squad').update({ status: b.dataset.next }).eq('id', b.dataset.toggle).then(function (res) {
              msg(res.error ? res.error.message : 'Updated.'); loadSquad(p);
            });
          });
        });
      });
  }

  // ---------- SUPER ADMIN: player registrations ----------
  function loadSquadReview() {
    db.from('club_squad').select('id, player_name, player_nin, position, club_id, date_of_birth').eq('registration_status', 'Pending').order('created_at', { ascending: true })
      .then(function (r) {
        var rows = r.data || [];
        if (!rows.length) { $('squadReview').innerHTML = 'No players waiting.'; return; }
        db.from('league_clubs').select('id, club_name').then(function (c) {
          var names = {}; (c.data || []).forEach(function (k) { names[k.id] = k.club_name; });
          $('squadReview').innerHTML = rows.map(function (x) {
            return '<div class="post"><strong>' + esc(x.player_name) + '</strong> <span class="muted">' + esc(x.position) + '</span>' +
              '<div class="muted">' + esc(names[x.club_id] || 'Unknown club') + ' · ID ' + esc(x.player_nin) + ' · born ' + esc(x.date_of_birth) + '</div>' +
              '<div class="btns"><button class="primary" data-sq="' + esc(x.id) + '" data-to="Approved">Approve</button><button class="secondary" data-sq="' + esc(x.id) + '" data-to="Rejected">Reject</button></div></div>';
          }).join('');
          document.querySelectorAll('[data-sq]').forEach(function (b) {
            b.addEventListener('click', function () {
              db.from('club_squad').update({ registration_status: b.dataset.to }).eq('id', b.dataset.sq).then(function (res) {
                msg(res.error ? res.error.message : (b.dataset.to === 'Approved' ? 'Player approved.' : 'Player rejected.')); loadSquadReview();
              });
            });
          });
        });
      });
  }

  // ---------- TECHNICAL DIRECTOR: assign roles ----------
  var clubsCache = [];
  var ROLE_OPTIONS = [['VIEWER','Viewer'],['PLAYER','Player'],['CLUB_ADMIN','Club Manager'],['REFEREE','Match Official (Referee)'],['MEDIA_OFFICER','Media Officer'],['FINANCE_OFFICER','Finance Officer'],['STAFF','Staff (read-only)'],['SUPER_ADMIN','Super Admin']];
  function developer(p) {
    box().innerHTML =
      '<h2 class="rt">League status</h2><div id="leagueState" class="muted">Checking…</div>' +
      '<div class="btns"><button class="secondary" id="pauseBtn">Freeze league</button><button class="primary" id="resumeBtn">Resume league</button></div>' +
      '<h2 class="rt">Accounts</h2><p class="muted">Assign roles, suspend or restore. Each change needs a reason and is logged.</p>' +
      '<div id="roleList" class="muted">Loading accounts…</div>' +
      '<h2 class="rt">Recent role changes</h2><div id="roleLog" class="muted">Loading…</div>' +
      '<div class="status" id="roleMsg"></div>';

    loadLeagueState(); loadAccountsDev(p); loadRoleLog();

    $('pauseBtn').addEventListener('click', function () { setPause(true); });
    $('resumeBtn').addEventListener('click', function () { setPause(false); });
  }

  function loadLeagueState() {
    db.from('system_pause').select('paused, reason, changed_at').eq('id', 1).maybeSingle().then(function (r) {
      var st = r.data || { paused: false };
      $('leagueState').innerHTML = st.paused
        ? '<strong style="color:#ff8a80">Frozen.</strong> The league is paused. Results and fixtures cannot change.' + (st.reason ? '<br><small>Reason: ' + esc(st.reason) + '</small>' : '')
        : '<strong style="color:#7ee6a0">Live.</strong> The league is running normally.';
    });
  }
  function setPause(pause) {
    var reason = prompt(pause ? 'Reason for freezing the league (at least 5 characters, kept in the log):' : 'Reason for resuming the league (at least 5 characters, kept in the log):');
    if (reason == null) return;
    if (reason.trim().length < 5) { msg('Give a reason of at least 5 characters.'); return; }
    db.rpc('set_system_pause', { p_paused: pause, p_reason: reason.trim() }).then(function (res) {
      msg(res.error ? res.error.message : (pause ? 'League frozen and logged.' : 'League resumed and logged.'));
      loadLeagueState(); loadRoleLog();
    });
  }

  function clubPicker(u) {
    var opts = '<option value="">No club</option>' + clubsCache.map(function (c) {
      return '<option value="' + esc(c.id) + '"' + (c.id === u.club_id ? ' selected' : '') + '>' + esc(c.club_name) + '</option>';
    }).join('');
    return '<label>Club</label><select data-club-for="' + esc(u.id) + '">' + opts + '</select>' +
      '<div class="btns"><button class="small" data-club-apply="' + esc(u.id) + '">Apply club</button></div>';
  }
  function loadAccountsDev(p) {
    db.from('league_clubs').select('id, club_name').order('club_name').then(function (c) {
      clubsCache = c.data || [];
      return db.from('user_profiles').select('id, full_name, email, system_role, status, club_id').order('email').limit(300);
    }).then(function (r) {
      var rows = r.data || [];
      $('roleList').innerHTML = rows.length ? rows.map(function (u) {
        var isMe = u.id === p.id;
        var isDev = String(u.system_role).toUpperCase() === 'DEVELOPER';
        var active = String(u.status).toLowerCase() === 'active';
        var opts = ROLE_OPTIONS.map(function (o) { return '<option value="' + o[0] + '"' + (String(u.system_role).toUpperCase() === o[0] ? ' selected' : '') + '>' + esc(o[1]) + '</option>'; }).join('');
        return '<div class="post"><strong>' + esc(u.full_name || u.email) + (isMe ? ' <span class="muted">(you)</span>' : '') + '</strong>' +
          '<div class="muted">' + esc(u.email) + ' · ' + esc(u.status) + '</div>' +
          (isDev ? '<div class="muted">Technical Director</div>' :
            '<select data-role-for="' + esc(u.id) + '">' + opts + '</select>' +
            (String(u.system_role).toUpperCase() === 'CLUB_ADMIN' ? clubPicker(u) : '') +
            '<div class="btns"><button class="small" data-apply="' + esc(u.id) + '">Apply role</button>' +
            (isMe ? '' : '<button class="small ' + (active ? 'danger' : '') + '" data-status="' + esc(u.id) + '" data-next="' + (active ? 'Suspended' : 'Active') + '">' + (active ? 'Suspend' : 'Restore') + '</button>') +
            '</div>') +
          '</div>';
      }).join('') : 'No accounts yet.';

      document.querySelectorAll('[data-apply]').forEach(function (b) {
        b.addEventListener('click', function () {
          var id = b.dataset.apply, role = document.querySelector('[data-role-for="' + id + '"]').value;
          var reason = prompt('Reason for this role change (at least 5 characters, kept in the log):');
          if (reason == null) return;
          if (reason.trim().length < 5) { msg('Give a reason of at least 5 characters.'); return; }
          db.rpc('set_user_role', { p_user: id, p_role: role, p_reason: reason.trim() }).then(function (res) {
            msg(res.error ? res.error.message : 'Role saved and logged.'); loadAccountsDev(p); loadRoleLog();
          });
        });
      });
      document.querySelectorAll('[data-club-apply]').forEach(function (b) {
        b.addEventListener('click', function () {
          var id = b.dataset.clubApply, club = document.querySelector('[data-club-for="' + id + '"]').value || null;
          db.rpc('set_user_club', { p_user: id, p_club: club }).then(function (res) {
            msg(res.error ? res.error.message : 'Club saved.'); loadAccountsDev(p);
          });
        });
      });
      document.querySelectorAll('[data-status]').forEach(function (b) {
        b.addEventListener('click', function () {
          var next = b.dataset.next;
          var reason = prompt(next === 'Suspended' ? 'Reason for suspending (at least 5 characters, kept in the log):' : 'Reason for restoring (at least 5 characters, kept in the log):');
          if (reason == null) return;
          if (reason.trim().length < 5) { msg('Give a reason of at least 5 characters.'); return; }
          db.rpc('set_account_status', { p_user: b.dataset.status, p_status: next, p_reason: reason.trim() }).then(function (res) {
            msg(res.error ? res.error.message : (next === 'Suspended' ? 'Account suspended and logged.' : 'Account restored and logged.'));
            loadAccountsDev(p);
          });
        });
      });
    });
  }

  function loadRoleLog() {
    db.from('role_change_log').select('user_email, previous_role, new_role, reason, changed_at').order('changed_at', { ascending: false }).limit(10).then(function (r) {
      var rows = r.data || [];
      $('roleLog').innerHTML = rows.length ? rows.map(function (x) {
        return '<div class="ev"><span class="etxt">' + esc(x.user_email) + ': ' + esc(x.previous_role || '—') + ' → ' + esc(x.new_role) + '<small>' + esc(x.reason) + '</small></span></div>';
      }).join('') : 'No role changes yet.';
    });
  }

  // ---------- REFEREE ----------
  var refEvents = [];
  function referee(p) {
    box().innerHTML =
      '<h2 class="rt">My matches</h2>' +
      '<label for="rfMatch">Match</label><select id="rfMatch"><option value="">Loading your matches…</option></select>' +
      '<div class="scores"><span id="rfScore" class="score-big">0 – 0</span></div>' +
      '<div class="btns"><button class="secondary" id="rfStart">Start match</button><button class="primary" id="rfEnd">End and submit score</button></div>' +
      '<h2 class="rt">Events so far</h2><div id="rfEvents" class="muted">No events yet.</div>' +
      '<div id="rfPanel" class="hidden">' +
        '<label for="rfTeam">Team</label><select id="rfTeam"></select>' +
        input('rfPlayer', 'Player') + input('rfAssist', 'Assist (optional)') + input('rfOff', 'Player off (substitutions only)') +
        '<label for="rfType">Event</label><select id="rfType"><option value="goal">Goal</option><option value="yellow_card">Yellow card</option><option value="red_card">Red card</option><option value="substitution">Substitution</option></select>' +
        input('rfMinute', 'Minute', 'number', 'min="0" max="130"') +
        '<div class="btns"><button class="primary" id="rfAdd">Record event</button></div>' +
      '</div>' +
      '<div class="status" id="roleMsg"></div>';

    db.auth.getUser().then(function (u) {
      return db.from('match_referee_assignments').select('match_id').eq('referee_user_id', u.data.user.id).eq('assignment_status', 'ACTIVE').eq('official_role', 'MAIN');
    }).then(function (a) {
      var ids = (a.data || []).map(function (x) { return x.match_id; });
      if (!ids.length) { $('rfMatch').innerHTML = '<option value="">No matches assigned to you yet</option>'; return; }
      return db.from('matches').select('id, home_team, away_team, match_status, match_date').in('id', ids).order('match_date', { ascending: true })
        .then(function (r) {
          $('rfMatch').innerHTML = '<option value="">Choose a match…</option>' + (r.data || []).map(function (m) {
            return '<option value="' + esc(m.id) + '">' + esc(m.home_team) + ' v ' + esc(m.away_team) + (m.match_status === 'LIVE' ? ' · LIVE' : '') + '</option>'; }).join('');
        });
    });

    $('rfMatch').addEventListener('change', function () { loadRefMatch(this.value); });
    $('rfStart').addEventListener('click', function () {
      var id = $('rfMatch').value; if (!id) { msg('Choose a match.'); return; }
      db.from('matches').update({ match_status: 'LIVE' }).eq('id', id).then(function (r) {
        msg(r.error ? r.error.message : 'Match is live.'); loadRefMatch(id); });
    });
    $('rfEnd').addEventListener('click', function () {
      var id = $('rfMatch').value; if (!id) { msg('Choose a match.'); return; }
      db.from('matches').select('id, home_team, away_team').eq('id', id).maybeSingle().then(function (r) {
        var m = r.data; var hg = goalsFor(m.home_team), ag = goalsFor(m.away_team);
        if (!confirm('Submit ' + m.home_team + ' ' + hg + ' – ' + ag + ' ' + m.away_team + ' for the Super Admin to approve?')) return;
        return db.auth.getUser().then(function (u) {
          return db.from('match_results').insert([{ match_id: String(id), home_team: m.home_team, away_team: m.away_team, home_goals: hg, away_goals: ag, status: 'PENDING', recorded_by: u.data.user.id }]);
        }).then(function (res) {
          if (res.error) { msg(res.error.message); return; }
          return db.from('matches').update({ match_status: 'FINISHED' }).eq('id', id).then(function () {
            msg('Score submitted for approval.'); loadRefMatch(id); });
        });
      });
    });
    $('rfAdd').addEventListener('click', function () {
      var id = $('rfMatch').value; if (!id) { msg('Choose a match.'); return; }
      var type = $('rfType').value, player = $('rfPlayer').value.trim(), minute = parseInt($('rfMinute').value, 10);
      if (!player || isNaN(minute)) { msg('Enter the player and the minute.'); return; }
      if (type === 'substitution' && !$('rfOff').value.trim()) { msg('Enter the player coming off.'); return; }
      db.auth.getUser().then(function (u) {
        return db.from('match_events').insert([{ match_id: String(id), event_type: type, team_name: $('rfTeam').value, player_name: player,
          assist_player_name: $('rfAssist').value.trim() || null, player_off_name: $('rfOff').value.trim() || null, minute: minute,
          recorded_by: u.data.user.id, recorded_at: new Date().toISOString(), published_at: new Date().toISOString() }]);
      }).then(function (res) {
        if (res.error) { msg(res.error.message); return; }
        msg('Recorded.'); ['rfPlayer','rfAssist','rfOff','rfMinute'].forEach(function (x) { $(x).value = ''; });
        loadRefMatch(id);
      });
    });
  }
  function goalsFor(team) { return refEvents.filter(function (e) { return e.event_type === 'goal' && e.team_name === team; }).length; }
  function loadRefMatch(id) {
    if (!id) { $('rfPanel').classList.add('hidden'); return; }
    db.from('matches').select('id, home_team, away_team, match_status').eq('id', id).maybeSingle().then(function (r) {
      var m = r.data; if (!m) return;
      $('rfTeam').innerHTML = '<option>' + esc(m.home_team) + '</option><option>' + esc(m.away_team) + '</option>';
      $('rfPanel').classList.toggle('hidden', m.match_status !== 'LIVE');
      db.from('match_events').select('id, event_type, team_name, player_name, player_off_name, minute').eq('match_id', String(id)).order('minute', { ascending: true }).then(function (e) {
        refEvents = e.data || [];
        $('rfScore').textContent = goalsFor(m.home_team) + ' – ' + goalsFor(m.away_team);
        $('rfEvents').innerHTML = refEvents.length ? refEvents.map(function (ev) {
          var label = ev.event_type === 'substitution' ? ev.player_name + ' on, ' + (ev.player_off_name || '') + ' off' : ev.player_name;
          return '<div class="ev"><span class="min">' + esc(ev.minute) + "'</span><span class=\"etxt\">" + esc(String(ev.event_type).replace('_',' ')) + ': ' + esc(label) +
            '<small>' + esc(ev.team_name || '') + '</small></span><button class="small danger" data-rev="' + ev.id + '">Reverse</button></div>';
        }).join('') : 'No events yet.';
        document.querySelectorAll('[data-rev]').forEach(function (b) {
          b.addEventListener('click', function () {
            var reason = prompt('Why is this being reversed? For example: goal disallowed for offside. Kept in the log.');
            if (reason == null) return;
            if (reason.trim().length < 5) { msg('Give a reason of at least 5 characters.'); return; }
            db.rpc('reverse_match_event', { p_event_id: Number(b.dataset.rev), p_reason: reason.trim() }).then(function (res) {
              msg(res.error ? res.error.message : 'Reversed and logged. The score is updated.'); loadRefMatch(id);
            });
          });
        });
      });
    });
  }

  // ---------- MEDIA OFFICER ----------
  function mediaOfficer(p) {
    box().innerHTML =
      '<h2 class="rt">New news post</h2>' +
      '<label for="npCat">Category</label><select id="npCat"><option>News</option><option>Match report</option><option>Announcement</option></select>' +
      input('npTitle', 'Title') +
      '<label for="npBody">Story</label><textarea id="npBody" rows="5"></textarea>' +
      input('npImage', 'Photo link (optional)', 'url') + input('npVideo', 'Video link (optional)', 'url') +
      '<div class="btns"><button class="secondary" id="npDraft">Save draft</button><button class="secondary" id="npSubmit">Submit for approval</button><button class="primary" id="npPublish">Publish now</button></div>' +
      '<h2 class="rt">My posts</h2><div id="myPosts" class="muted">Loading…</div>' +
      '<div class="status" id="roleMsg"></div>';

    function save(status) {
      var t = $('npTitle').value.trim();
      if (!t) { msg('Give the post a title.'); return; }
      db.auth.getUser().then(function (u) {
        return db.from('media_posts').insert([{
          category: $('npCat').value, title: t, body: $('npBody').value.trim(),
          image_url: $('npImage').value.trim() || null, video_url: $('npVideo').value.trim() || null,
          status: status, created_by: u.data.user.id, created_by_name: p.full_name || p.email,
          submitted_at: status === 'SUBMITTED' ? new Date().toISOString() : null,
          published_at: status === 'PUBLISHED' ? new Date().toISOString() : null
        }]);
      }).then(function (r) {
        if (r.error) { msg(r.error.message); return; }
        msg(status === 'SUBMITTED' ? 'Sent to the Super Admin for approval.' : status === 'PUBLISHED' ? 'Published.' : 'Draft saved.');
        $('npTitle').value = ''; $('npBody').value = ''; $('npImage').value = ''; $('npVideo').value = ''; loadMine();
      });
    }
    $('npDraft').addEventListener('click', function () { save('DRAFT'); });
    $('npSubmit').addEventListener('click', function () { save('SUBMITTED'); });
    $('npPublish').addEventListener('click', function () { save('PUBLISHED'); });
    loadMine();
  }
  function loadMine() {
    db.auth.getUser().then(function (u) {
      return db.from('media_posts').select('id, title, status, category').eq('created_by', u.data.user.id).order('created_at', { ascending: false }).limit(30);
    }).then(function (r) {
      var rows = r.data || [];
      $('myPosts').innerHTML = rows.length ? rows.map(function (x) {
        var open = x.status !== 'PUBLISHED';
        return '<div class="post"><strong>' + esc(x.title) + '</strong><div class="muted">' + esc(x.category) + ' · ' + esc(x.status) + '</div>' +
          (open ? '<div class="btns"><button class="small" data-sub="' + esc(x.id) + '">Submit for approval</button><button class="small" data-pub="' + esc(x.id) + '">Publish now</button></div>' : '') + '</div>';
      }).join('') : 'No posts yet.';
      document.querySelectorAll('[data-sub]').forEach(function (b) {
        b.addEventListener('click', function () {
          db.from('media_posts').update({ status: 'SUBMITTED', submitted_at: new Date().toISOString() }).eq('id', b.dataset.sub)
            .then(function (res) { msg(res.error ? res.error.message : 'Sent for approval.'); loadMine(); });
        });
      });
      document.querySelectorAll('[data-pub]').forEach(function (b) {
        b.addEventListener('click', function () {
          db.from('media_posts').update({ status: 'PUBLISHED', published_at: new Date().toISOString() }).eq('id', b.dataset.pub)
            .then(function (res) { msg(res.error ? res.error.message : 'Published.'); loadMine(); });
        });
      });
    });
  }

  db.auth.onAuthStateChange(function () { setTimeout(render, 0); });
  render();

  // LIVE ADMIN: lists update when a result, news post, event or assignment changes
  var adminTimer = null;
  function refreshAdmin() {
    if ($('pendingResults')) loadPendingResults();
    if ($('reviewList')) loadReview();
    if ($('squadReview')) loadSquadReview();
    if ($('myPosts')) loadMine();
    if ($('rfMatch') && $('rfMatch').value) loadRefMatch($('rfMatch').value);
    if ($('lvMatch') && $('lvMatch').value) loadLiveMatch($('lvMatch').value);
  }
  db.channel('admin-live')
    .on('postgres_changes', { event: '*', schema: 'public', table: 'match_results' }, function () { clearTimeout(adminTimer); adminTimer = setTimeout(refreshAdmin, 400); })
    .on('postgres_changes', { event: '*', schema: 'public', table: 'media_posts' }, function () { clearTimeout(adminTimer); adminTimer = setTimeout(refreshAdmin, 400); })
    .on('postgres_changes', { event: '*', schema: 'public', table: 'match_events' }, function () { clearTimeout(adminTimer); adminTimer = setTimeout(refreshAdmin, 400); })
    .subscribe();
})();
