<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>Upload Files</title>
  <style>
    body { font-family: sans-serif; margin: 2rem; }
    .container { max-width: 600px; margin: auto; }
    nav { margin-bottom: 2rem; }
    nav a { margin-right: 1rem; text-decoration: none; color: #0366d6; }
    nav a:hover { text-decoration: underline; }
    #preview { display: block; margin-top: 1rem; max-width: 100%; }
    #statusContainer { margin-top: 1rem; }
    .status { margin: 0.5em 0; }
    .success { color: green; }
    .error { color: red; }
  </style>
</head>
<body>
  <nav>
    <a href="index.html"><strong>Upload</strong></a>
    <a href="list.html">View Files</a>
  </nav>
  <div class="container">
    <h2>Upload Files</h2>
    <form id="uploadForm">
      <input type="file" id="fileInput" multiple />
      <button type="submit">Upload</button>
    </form>
    <img id="preview" style="display:none;" />
    <div id="statusContainer"></div>
  </div>

  <script>
    const API_URL        = "${API_URL}";
    const COGNITO_DOMAIN = "${COGNITO_DOMAIN}";
    const CLIENT_ID      = "${CLIENT_ID}";
    const REDIRECT_URI   = "${REDIRECT_URI}";
    const LOGOUT_URI     = "${LOGOUT_URI}";

    const urlParams = new URLSearchParams(window.location.search);
    const code      = urlParams.get("code");

    // 1) Exchange code if present
    if (code) {
      const body = new URLSearchParams({
        grant_type:   "authorization_code",
        client_id:    CLIENT_ID,
        code:         code,
        redirect_uri: REDIRECT_URI
      });

      fetch(`${COGNITO_DOMAIN}/oauth2/token`, {
        method:  "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body:    body
      })
      .then(r => { if (!r.ok) throw new Error("Token exchange failed"); return r.json(); })
      .then(tokens => {
        sessionStorage.removeItem("logging_in");
        localStorage.setItem("id_token",     tokens.id_token);
        localStorage.setItem("access_token", tokens.access_token);
        window.location.replace(window.location.origin + window.location.pathname);
      })
      .catch(e => {
        console.error(e);
        alert("Auth failed.");
      });
      return;
    }

    // 2) Redirect to login only once
    const token = localStorage.getItem("access_token") || localStorage.getItem("id_token");
    if (!token) {
      if (!sessionStorage.getItem("logging_in")) {
        sessionStorage.setItem("logging_in", "1");
        const loginUrl =
          `${COGNITO_DOMAIN}/login?response_type=code` +
          `&client_id=${CLIENT_ID}` +
          `&redirect_uri=$${encodeURIComponent(REDIRECT_URI)}` +
          `&scope=openid+email+profile`;
        window.location.href = loginUrl;
      }
      return;
    }

    // 3) Upload logic
    const fileInput       = document.getElementById("fileInput");
    const preview         = document.getElementById("preview");
    const uploadForm      = document.getElementById("uploadForm");
    const statusContainer = document.getElementById("statusContainer");

    fileInput.addEventListener("change", () => {
      const f = fileInput.files[0];
      if (f && f.type.startsWith("image/")) {
        preview.src = URL.createObjectURL(f);
        preview.style.display = "block";
      } else {
        preview.style.display = "none";
      }
    });

    uploadForm.addEventListener("submit", async e => {
      e.preventDefault();
      statusContainer.innerHTML = "";

      for (const f of fileInput.files) {
        const status = createStatusBlock(`$${f.name}: Uploading…`);
        try {
          const q = new URLSearchParams({
            filename:     f.name,
            content_type: f.type,
            filesize:     f.size.toString(),
          });

          const pre = await fetch(`${API_URL}?$${q.toString()}`, {
            method:  "GET",
            headers: { Authorization: `Bearer ${token}` }
          });
          if (!pre.ok) throw new Error(await pre.text() || pre.statusText);

          const { upload_url } = await pre.json();
          const putRes = await fetch(upload_url, {
            method:  "PUT",
            headers: { "Content-Type": f.type },
            body:    f
          });
          if (!putRes.ok) throw new Error(`Upload failed ($${putRes.status})`);

          const clean = upload_url.split("?")[0];
          status.innerHTML = `✅ <strong>$${f.name}</strong>: <a href="$${clean}" target="_blank">$${clean}</a>`;
          status.classList.add("success");
        } catch (err) {
          status.innerHTML = `❌ ${f.name}: ${err.message}`;
          status.classList.add("error");
        }
      }
    });

    function createStatusBlock(msg) {
      const d = document.createElement("div");
      d.className = "status";
      d.textContent = msg;
      statusContainer.appendChild(d);
      return d;
    }
  </script>
</body>
</html>
