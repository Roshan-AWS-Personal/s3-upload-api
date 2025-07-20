<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>File Upload</title>
  <style>
    body { font-family: sans-serif; margin: 2rem; }
    .container { max-width: 600px; margin: auto; }
    #preview { display: block; margin-top: 1rem; max-width: 100%; }
    #urlDisplay { margin-top: 1rem; font-weight: bold; }
    .success { color: green; }
    .error { color: red; }
    #logoutBtn { margin-top: 1rem; display: none; }
  </style>
</head>
<body>
  <div class="container">
    <h2>Upload Files</h2>
    <button id="logoutBtn">Logout</button>
    <form id="uploadForm">
      <input type="file" id="fileInput" multiple />
      <button type="submit">Upload</button>
    </form>
    <img id="preview" style="display: none;" alt="Image preview" />
    <div id="urlDisplay"></div>
  </div>

  <script>
    const API_URL = "${API_URL}";
    const COGNITO_DOMAIN = "${COGNITO_DOMAIN}";
    const CLIENT_ID = "${CLIENT_ID}";
    const REDIRECT_URI = "${REDIRECT_URI}";

    function decodeJwt(token) {
      try {
        const payload = token.split('.')[1];
        const decoded = atob(payload.replace(/-/g, '+').replace(/_/g, '/'));
        return JSON.parse(decoded);
      } catch (e) {
        console.warn("Failed to decode JWT:", e);
        return {};
      }
    }

    async function handleCognitoLoginRedirect() {
      const params = new URLSearchParams(window.location.search);
      const code = params.get("code");

      if (code) {
        console.log("[Auth] Got code from redirect:", code);
        try {
          const tokenRes = await fetch(COGNITO_DOMAIN + "/oauth2/token", {
            method: "POST",
            headers: { "Content-Type": "application/x-www-form-urlencoded" },
            body: new URLSearchParams({
              grant_type: "authorization_code",
              client_id: CLIENT_ID,
              redirect_uri: REDIRECT_URI,
              code: code
            })
          });

          const text = await tokenRes.text();
          console.log("[Auth] Raw token response:", text);

          let tokenData;
          try {
            tokenData = JSON.parse(text);
          } catch {
            console.error("[Auth] Failed to parse token response:", text);
            alert("Invalid token response");
            return;
          }

          if (tokenData.id_token) {
            localStorage.setItem("id_token", tokenData.id_token);
            const decoded = decodeJwt(tokenData.id_token);
            console.log("[Auth] ID token saved ✅");
            console.log("[Auth] Token use:", decoded.token_use);
            console.log("[Auth] Cognito username/email:", decoded["cognito:username"], decoded.email);
          } else {
            console.error("[Auth] No id_token found", tokenData);
            alert("Login failed: No ID token returned.");
            return;
          }

          window.history.replaceState({}, document.title, REDIRECT_URI);
        } catch (err) {
          console.error("[Auth] Token exchange failed:", err);
          alert("OAuth error: " + err.message);
        }
      }
    }

    async function ensureLoggedIn() {
      const token = localStorage.getItem("id_token");
      if (!token) {
        const loginUrl = `${COGNITO_DOMAIN}/login?response_type=code&client_id=${CLIENT_ID}&redirect_uri=${REDIRECT_URI}&scope=openid+email+profile`;
        const lastRedirect = sessionStorage.getItem("last_redirect");

        if (!lastRedirect || Date.now() - parseInt(lastRedirect) > 10000) {
          sessionStorage.setItem("last_redirect", Date.now().toString());
          window.location.href = loginUrl;
        }
      } else {
        const decoded = decodeJwt(token);
        console.log("[Auth] Logged in as:", decoded["cognito:username"] || "unknown", "| Token use:", decoded.token_use);
        if (decoded.token_use !== "id") {
          console.warn("[Auth] ⚠️ Token is not an ID token. API calls may fail.");
        }
        document.getElementById("logoutBtn").style.display = "inline-block";
      }
    }

    document.getElementById("logoutBtn").onclick = function () {
      localStorage.removeItem("id_token");
      localStorage.removeItem("access_token");
      window.location.href = `${COGNITO_DOMAIN}/logout?client_id=${CLIENT_ID}&redirect_uri=${REDIRECT_URI}`;
    };

    (async function () {
      await handleCognitoLoginRedirect();
      await ensureLoggedIn();
    })();

    const form = document.getElementById('uploadForm');
    const fileInput = document.getElementById('fileInput');
    const preview = document.getElementById('preview');
    const urlDisplay = document.getElementById('urlDisplay');

    fileInput.addEventListener('change', () => {
      const file = fileInput.files[0];
      if (file && file.type.startsWith("image/")) {
        preview.src = URL.createObjectURL(file);
        preview.style.display = 'block';
      } else {
        preview.style.display = 'none';
      }
    });

    form.addEventListener('submit', async (e) => {
      e.preventDefault();
      const files = fileInput.files;
      const token = localStorage.getItem("id_token");

      if (!files.length) return alert("Please choose one or more files.");
      if (!token) return alert("You're not logged in.");

      const decoded = decodeJwt(token);
      console.log("[Upload] Using token_use:", decoded.token_use);
      if (decoded.token_use !== "id") {
        alert("Invalid token type. Please log in again.");
        return;
      }

      urlDisplay.innerHTML = "";

      for (const file of files) {
        const status = document.createElement("p");
        status.textContent = "Uploading " + file.name + "...";
        urlDisplay.appendChild(status);

        try {
          console.log("[Upload] Requesting upload URL for", file.name);

          const query = new URLSearchParams({
            filename: file.name,
            content_type: file.type,
            filesize: file.size.toString()
          });

          const response = await fetch(API_URL + "?" + query.toString(), {
            method: 'GET',
            headers: {
              "Authorization": "Bearer " + token
            }
          });

          if (!response.ok) {
            const errorText = await response.text();
            console.error("[Upload] Failed to get upload URL for", file.name, response.status, errorText);
            status.textContent = "❌ Failed to get upload URL for " + file.name;
            status.classList.add("error");
            continue;
          }

          const data = await response.json();
          console.log("[Upload] Got presigned URL for", file.name, data.upload_url);

          const uploadRes = await fetch(data.upload_url, {
            method: 'PUT',
            body: file
          });

          if (uploadRes.ok) {
            const cleanUrl = data.upload_url.split("?")[0];
            console.log("[Upload] Upload success ✅", file.name, cleanUrl);
            status.innerHTML = "✅ <strong>" + file.name + ":</strong> <a href=\"" + cleanUrl + "\" target=\"_blank\">" + cleanUrl + "</a>";
            status.classList.add("success");
          } else {
            console.error("[Upload] PUT failed for", file.name, uploadRes.status);
            status.textContent = "❌ Upload failed for " + file.name;
            status.classList.add("error");
          }
        } catch (err) {
          console.error("[Upload] Exception during upload for", file.name, err);
          status.textContent = "❌ Error uploading " + file.name + ": " + err.message;
          status.classList.add("error");
        }
      }
    });
  </script>
</body>
</html>
