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
  (async function(){
    const API_URL        = "https://d3oxbj82njk30z.cloudfront.net/dev/upload";
    const COGNITO_DOMAIN = "${COGNITO_DOMAIN}";
    const CLIENT_ID      = "${CLIENT_ID}";
    const REDIRECT_URI   = "${REDIRECT_URI}";

    // --- 1) Handle OAuth redirect (code→tokens) ---
    const params = new URLSearchParams(location.search);
    const code   = params.get("code");
    if (code) {
      const body = new URLSearchParams({
        grant_type:   "authorization_code",
        client_id:    CLIENT_ID,
        code:         code,
        redirect_uri: REDIRECT_URI
      });
      const resp = await fetch(`${COGNITO_DOMAIN}/oauth2/token`, {
        method:  "POST",
        headers: { "Content-Type":"application/x-www-form-urlencoded" },
        body
      });
      if (!resp.ok) { alert("Auth failed"); return; }
      const { id_token, access_token } = await resp.json();
      localStorage.setItem("id_token", id_token);
      localStorage.setItem("access_token", access_token);
      history.replaceState({}, "", location.pathname);
      return;
    }

    // --- 2) If no token, kick off login **once** ---
    const token = localStorage.getItem("access_token")||localStorage.getItem("id_token");
    if (!token) {
      if (!sessionStorage.getItem("logging_in")) {
        sessionStorage.setItem("logging_in","1");
        location.href = 
          `${COGNITO_DOMAIN}/login?response_type=code` +
          `&client_id=${CLIENT_ID}` +
          `&redirect_uri=$${encodeURIComponent(REDIRECT_URI)}` +
          `&scope=openid+email+profile`;
      }
      return;
    }

    // --- 3) At this point we have a token, wire up upload form ---
    const fileInput       = document.getElementById("fileInput");
    const preview         = document.getElementById("preview");
    const form            = document.getElementById("uploadForm");
    const statusContainer = document.getElementById("statusContainer");

    fileInput.addEventListener("change", ()=>{
      const f = fileInput.files[0];
      if (f && f.type.startsWith("image/")) {
        preview.src = URL.createObjectURL(f);
        preview.style.display = "block";
      } else {
        preview.style.display = "none";
      }
    });

    form.addEventListener("submit", async e=>{
      e.preventDefault();
      statusContainer.innerHTML = "";
      for (const f of fileInput.files) {
        const div = document.createElement("div");
        div.className = "status";
        div.textContent = `$${f.name}: Uploading…`;
        statusContainer.appendChild(div);

        try {
          const q = new URLSearchParams({
            filename:     f.name,
            content_type: f.type,
            filesize:     f.size.toString()
          });
          const pre = await fetch(`${API_URL}?$${q.toString()}`, {
            headers: { Authorization: `Bearer $${token}` }
          });
          if (!pre.ok) throw new Error(await pre.text()||pre.statusText);

          const { upload_url } = await pre.json();
          const put = await fetch(upload_url, {
            method:  "PUT",
            headers: { "Content-Type": f.type },
            body:    f
          });
          if (!put.ok) throw new Error(`Upload failed (${put.status})`);

          const clean = upload_url.split("?")[0];
          div.innerHTML = `✅ <strong>$${f.name}</strong>: <a href="$${clean}" target="_blank">$${clean}</a>`;
          div.classList.add("success");
        } catch (err) {
          div.textContent = `❌ $${f.name}: $${err.message}`;
          div.classList.add("error");
        }
      }
    });

  })();
  </script>
</body>
</html>
