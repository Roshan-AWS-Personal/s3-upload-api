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
    html, body { height:100%; margin:0; font-family: ui-sans-serif, system-ui, -apple-system, Segoe UI, Roboto, Helvetica Neue, Arial; color: var(--text); background: linear-gradient(180deg, #0b0f14 0%, #0d131b 100%); }
    .wrap { max-width: 900px; margin: 0 auto; padding: 16px; }
    nav { margin-bottom: 12px; }
    nav a { margin-right: 12px; text-decoration: none; color: var(--accent); }
    nav a:hover { text-decoration: underline; }
    header { display:flex; align-items:center; gap:12px; margin-bottom: 16px; border-bottom:1px solid var(--border); padding-bottom:10px; }
    header h1 { font-size: 18px; margin: 0; letter-spacing: .2px; }
    header button { margin-left:auto; background: var(--soft); color: var(--text); border:1px solid var(--border); border-radius:10px; padding:8px 10px; font-size:12px; cursor:pointer; }
    .card { background: rgba(17,43,33,.35); border:1px solid var(--border); border-radius:12px; padding: 14px; }
    .row { display:grid; grid-template-columns: 1fr auto; gap: 10px; }
    textarea { width:100%; min-height: 90px; resize: vertical; padding:10px; background: var(--soft); color:var(--text); border:1px solid var(--border); border-radius:10px; }
    .btn { background: var(--accent); color:#001422; border:none; padding:10px 14px; border-radius:10px; cursor:pointer; }
    .answer { white-space: pre-wrap; line-height: 1.4; }
    .sources { margin-top:10px; font-size: 13px; color: var(--muted); }
    .src a { color: var(--accent); text-decoration: none; }
    .src { margin-top:6px; }
  </style>

  <!-- Terraform fills these -->
  <script>
    window.APP_CONFIG = {
      apiUrl: "${API_URL}",               // POST /query
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
    const cfg = window.APP_CONFIG;

    function decodeJwt(token) {
      try {
        const b = token.split('.')[1];
        return JSON.parse(atob(b.replace(/-/g, '+').replace(/_/g, '/')));
      } catch { return {}; }
    }

    async function handleCognitoLoginRedirect() {
      const params = new URLSearchParams(location.search);
      const code = params.get("code");
      if (!code) return;

      const res = await fetch(cfg.cognitoDomain + "/oauth2/token", {
        method: "POST",
        headers: {"Content-Type": "application/x-www-form-urlencoded"},
        body: new URLSearchParams({
          grant_type: "authorization_code",
          client_id: cfg.clientId,
          redirect_uri: cfg.redirectUri,
          code
        })
      });
      const text = await res.text();
      let data;
      try { data = JSON.parse(text); } catch { alert("Auth error"); return; }

      if (data.id_token) localStorage.setItem("id_token", data.id_token);
      history.replaceState({}, document.title, cfg.redirectUri);
    }

    function ensureLoggedIn() {
      const t = localStorage.getItem("id_token");
      if (!t) {
        const p = new URLSearchParams({
          response_type: "code",
          client_id: cfg.clientId,
          redirect_uri: cfg.redirectUri,
          scope: "openid email profile"
        });
        location.href = `${cfg.cognitoDomain}/login?${p}`;
        return false;
      }
      document.getElementById("logoutBtn").style.display = "inline-block";
      return true;
    }

    document.getElementById("logoutBtn").onclick = () => {
      localStorage.removeItem("id_token");
      localStorage.removeItem("access_token");
      location.href = `${cfg.cognitoDomain}/logout?client_id=${cfg.clientId}&logout_uri=${cfg.logoutUri || cfg.redirectUri}`;
    };

    async function ask() {
      const token = localStorage.getItem("id_token");
      const q = document.getElementById("q").value.trim();
      if (!q) return;
      document.getElementById("answer").textContent = "Thinking…";
      document.getElementById("sources").textContent = "";

      const resp = await fetch(cfg.apiUrl, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer " + token   // same pattern as your upload API
        },
        body: JSON.stringify({ q, k: 8 })
      });

      const data = await resp.json();
      document.getElementById("answer").textContent = data.answer || "(no answer)";
      const s = data.sources || [];
      const box = document.getElementById("sources");
      if (s.length) {
        box.innerHTML = "<strong>Sources</strong>";
        s.forEach(d => {
          const div = document.createElement("div");
          div.className = "src";
          const title = d.title || (d.s3_uri ? d.s3_uri.split('/').pop() : "document");
          const link = (d.s3_uri || "").replace(/^s3:\/\//, "https://s3.console.aws.amazon.com/s3/object/");
          div.innerHTML = `${title}`;
          box.appendChild(div);
        });
      }
    }

    (async () => {
      await handleCognitoLoginRedirect();
      if (!ensureLoggedIn()) return;
      document.getElementById("askBtn").onclick = ask;
      document.getElementById("q").addEventListener("keydown", e => {
        if (e.key === "Enter" && (e.ctrlKey || e.metaKey)) ask();
      });
    })();
  </script>
</body>
</html>
