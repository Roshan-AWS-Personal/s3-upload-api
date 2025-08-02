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
    <img id="preview" alt="Image preview" style="display: none;" />
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

    // 1) Always consume the OAuth2 code if present
    if (code) {
      const body = new URLSearchParams({
        grant_type:   "authorization_code",
        client_id:    CLIENT_ID,
        code:         code,
        redirect_uri: REDIRECT_URI,
      });

      fetch(`${COGNITO_DOMAIN}/oauth2/token`, {
        method:  "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body:    body
      })
      .then(res => {
        if (!res.ok) throw new Error("Token exchange failed");
        return res.json();
      })
      .then(tokens => {
        // break any previous login‐loop guard
        sessionStorage.removeItem("logging_in");

        localStorage.setItem("id_token",     tokens.id_token);
        localStorage.setItem("access_token", tokens.access_token);

        // remove ?code and reload cleanly
        window.location.replace(window.location.origin + window.location.pathname);
      })
      .catch(err => {
        console.error("Token exchange error:", err);
        alert("Authentication failed.");
      });

      return; // pause until exchange completes
    }

    // 2) If no token, redirect into Hosted UI—but only once
    const token = localStorage.getItem("access_token") || localStorage.getItem("id_token");
    if (!token) {
      if (!sessionStorage.getItem("logging_in")) {
        sessionStorage.setItem("logging_in", "1");
        const loginUrl =
          `${COGNITO_DOMAIN}/login?response_type=code` +
          `&client_id=${CLIENT_ID}` +
          `&redirect_uri=${encodeURIComponent(REDIRECT_URI)}` +
          `&scope=openid+email+profile`;
        window.location.href = loginUrl;
      }
      return;
    }

    // 3) At this point, we have a valid token—wire up your upload form
    const fileInput       = document.getElementById("fileInput");
    const preview         = document.getElementById("preview");
    const uploadForm      = document.getElementById("uploadForm");
    const statusContainer = document.getElementById("statusContainer");

    fileInput.addEventListener("change", () => {
      const file = fileInput.files[0];
      if (file && file.type.startsWith("image/")) {
        preview.src = URL.createObjectURL(file);
        preview.style.display = "block";
      } else {
        preview.style.display = "none";
      }
    });

    uploadForm.addEventListener("submit", async (e) => {
      e.preventDefault();
      statusContainer.innerHTML = "";

      for (const file of fileInput.files) {
        // double‐escaped so Terraform leaves it intact
        const status = createStatusBlock(`$${file.name}: Uploading…`);

        try {
          const query = new URLSearchParams({
            filename:     file.name,
            content_type: file.type,
            filesize:     file.size.toString(),
          });

          // get presigned URL
          const presignRes = await fetch(`${API_URL}?$${query.toString()}`, {
            method:  "GET",
            headers: { Authorization: `Bearer ${token}` }
          });
          if (!presignRes.ok) {
            const msg = await presignRes.text();
            throw new Error(msg || presignRes.statusText);
          }

          const { upload_url } = await presignRes.json();

          // PUT to S3 with correct Content-Type
          const uploadRes = await fetch(upload_url, {
            method:  "PUT",
            headers: { "Content-Type": file.type },
            body:    file
          });
          if (!uploadRes.ok) {
            throw new Error(`Upload failed ($${uploadRes.status})`);
          }

          // strip off the query, show final URL
          const fileUrl = upload_url.split("?")[0];
          status.innerHTML = `✅ <strong>$${file.name}</strong>: <a href="$${fileUrl}" target="_blank">$${fileUrl}</a>`;
          status.classList.add("success");
        } catch (err) {
          status.innerHTML = `❌ $${file.name}: ${err.message}`;
          status.classList.add("error");
        }
      }
    });

    function createStatusBlock(message) {
      const div = document.createElement("div");
      div.className = "status";
      div.textContent = message;
      statusContainer.appendChild(div);
      return div;
    }
  </script>
</body>
</html>
