<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>AI KB | Chat</title>
  <style>
    :root {
      --bg: #0b0f14; --panel: #112B21; --soft:#1A2330; --border:#263244;
      --text:#e6edf3; --muted:#94a3b8; --accent:#06a5fa; --danger:#fe4444;
    }
    * { box-sizing: border-box; }
    html, body {
      height:100%; margin:0;
      font-family: ui-sans-serif, system-ui, -apple-system, Segoe UI, Roboto, "Helvetica Neue", Arial;
      color: var(--text);
      background: linear-gradient(180deg, #0b0f14 0%, #0d131b 100%);
    }
    .wrap { max-width: 900px; margin: 0 auto; padding: 16px; }
    nav { margin-bottom: 12px; }
    nav a { margin-right: 12px; text-decoration: none; color: var(--accent); }
    nav a:hover { text-decoration: underline; }
    header { display:flex; align-items:center; gap:12px; margin-bottom: 16px; border-bottom:1px solid var(--border); padding-bottom:10px; }
    header h1 { font-size: 18px; margin: 0; letter-spacing: .2px; }
    header button { margin-left:auto; background: var(--soft); color: var(--text); border:1px solid var(--border); border-radius:10px; padding:8px 10px; font-size:12px; cursor:pointer; }
    .card { background: rgba(17,43,33,.35); border:1px solid var(--border); border-radius:12px; padding: 14px; }
    .row { display:grid; grid-template-columns: 1fr auto; gap: 10px; }
    textarea { width:100%; min-height: 100px; resize: vertical; padding:10px; background: var(--soft); color:var(--text); border:1px solid var(--border); border-radius:10px; }
    .btn { background: var(--accent); color:#001422; border:none; padding:10px 14px; border-radius:10px; cursor:pointer; }
    .answer { white-space: pre-wrap; line-height: 1.4; }
    .sources { margin-top:10px; font-size: 13px; color: var(--muted); }
    .src { margin-top:6px; }
    .error { color: var(--danger); }
  </style>

  <!-- Terraform fills these values -->
  <script>
    window.APP_CONFIG = {
      apiUrl: "${API_URL}",
      cognitoDomain: "${COGNITO_DOMAIN}",
      clientId: "${CLIENT_ID}",
      redirectUri: "${REDIRECT_URI}",
      logoutUri: "${LOGOUT_URI}"
    };
  </script>
</head>
<body>
  <div class="wrap">
    <nav>
      <a href="index.html">Upload</a>
      <a href="list.html">View Files</a>
      <a href="chat.html"><strong>Chat</strong></a>
    </nav>

    <header>
      <h1>Knowledge Base Chat</h1>
      <button id="logoutBtn" style="display:none">Logout</button>
    </header>

    <div class="card">
      <div class="row">
        <textarea id="q" placeholder="Ask a question about your uploaded docs..."></textarea>
        <button class="btn" id="askBtn">Ask</button>
      </div>
      <div id="out" style="margin-top:14px">
        <div class="answer" id="answer"></div>
        <div class="sources" id="sources"></div>
      </div>
    </div>
  </div>

  <script>
    // Config object
    var cfg = window.APP_CONFIG || {};

    function decodeJwt(token) {
      try {
        var b = token.split('.')[1];
        return JSON.parse(atob(b.replace(/-/g, '+').replace(/_/g, '/')));
      } catch (e) { return {}; }
    }

    async function handleCognitoLoginRedirect() {
      var params = new URLSearchParams(location.search);
      var code = params.get("code");
      if (!code) return;

      var res = await fetch(cfg.cognitoDomain + "/oauth2/token", {
        method: "POST",
        headers: {"Content-Type": "application/x-www-form-urlencoded"},
        body: new URLSearchParams({
          grant_type: "authorization_code",
          client_id: cfg.clientId,
          redirect_uri: cfg.redirectUri,
          code: code
        })
      });

      var text = await res.text();
      var data;
      try { data = JSON.parse(text); } catch (e) { alert("Auth error"); return; }

      if (data && data.id_token) {
        localStorage.setItem("id_token", data.id_token);
      }
      history.replaceState({}, document.title, cfg.redirectUri);
    }

    function ensureLoggedIn() {
      var t = localStorage.getItem("id_token");
      if (!t) {
        var p = new URLSearchParams({
          response_type: "code",
          client_id: cfg.clientId,
          redirect_uri: cfg.redirectUri,
          scope: "openid email profile"
        });
        location.href = cfg.cognitoDomain + "/login?" + p.toString();
        return false;
      }
      document.getElementById("logoutBtn").style.display = "inline-block";
      return true;
    }

    document.getElementById("logoutBtn").onclick = function () {
      localStorage.removeItem("id_token");
      localStorage.removeItem("access_token");
      var url = cfg.cognitoDomain
        + "/logout?client_id=" + encodeURIComponent(cfg.clientId)
        + "&logout_uri=" + encodeURIComponent(cfg.logoutUri || cfg.redirectUri);
      location.href = url;
    };

    async function ask() {
      var token = localStorage.getItem("id_token");
      var q = document.getElementById("q").value.trim();
      if (!q) return;

      document.getElementById("answer").textContent = "Thinking…";
      document.getElementById("sources").textContent = "";

      try {
        var resp = await fetch(cfg.apiUrl, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "Authorization": "Bearer " + token
          },
          body: JSON.stringify({ q: q, k: 8 })
        });

        var data = await resp.json();
        document.getElementById("answer").textContent = (data && data.answer) ? data.answer : "(no answer)";
        var s = (data && data.sources) ? data.sources : [];
        var box = document.getElementById("sources");
        if (s.length) {
          var title = document.createElement("div");
          title.innerHTML = "<strong>Sources</strong>";
          box.appendChild(title);
          s.forEach(function (d) {
            var div = document.createElement("div");
            div.className = "src";
            var t = d.title ? d.title : (d.s3_uri ? d.s3_uri.split('/').pop() : "document");
            div.textContent = t;
            box.appendChild(div);
          });
        }
      } catch (e) {
        document.getElementById("answer").textContent = "Error fetching answer.";
        var err = document.createElement("div");
        err.className = "error";
        err.textContent = e.message || String(e);
        document.getElementById("sources").appendChild(err);
      }
    }

    (async function () {
      await handleCognitoLoginRedirect();
      if (!ensureLoggedIn()) return;
      document.getElementById("askBtn").onclick = ask;
      document.getElementById("q").addEventListener("keydown", function (e) {
        if (e.key === "Enter" && (e.ctrlKey || e.metaKey)) ask();
      });
    })();
  </script>
</body>
</html>
