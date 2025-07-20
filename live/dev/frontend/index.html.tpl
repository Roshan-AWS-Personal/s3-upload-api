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
    <img id="preview" style="display: none;" />
    <div id="urlDisplay"></div>
  </div>

  <script>
    const API_URL = "https://n3bcr23wm1.execute-api.ap-southeast-2.amazonaws.com/dev/upload";
    const COGNITO_DOMAIN = "https://upload-auth.auth.ap-southeast-2.amazoncognito.com";
    const CLIENT_ID = "61ft4rv9n3ksikh5arn5ij8k90";
    const REDIRECT_URI = window.location.origin;

    async function handleCognitoLoginRedirect() {
      const params = new URLSearchParams(window.location.search);
      const code = params.get("code");

      if (code) {
        const redirect_uri = REDIRECT_URI;

        try {
          const tokenRes = await fetch(COGNITO_DOMAIN + "/oauth2/token", {
            method: "POST",
            headers: { "Content-Type": "application/x-www-form-urlencoded" },
            body: new URLSearchParams({
              grant_type: "authorization_code",
              client_id: CLIENT_ID,
              redirect_uri: redirect_uri,
              code: code
            })
          });

          const text = await tokenRes.text();
          console.log("Token endpoint raw response:", text);

          let tokenData;
          try {
            tokenData = JSON.parse(text);
          } catch {
            alert("Invalid token response: " + text);
            return;
          }

          if (tokenData.id_token) {
            // ✅ Store only the id_token for API Gateway use
            localStorage.setItem("id_token", tokenData.id_token);
            window.history.replaceState({}, document.title, redirect_uri);
          } else {
            alert("Failed to log in: " + (tokenData.error_description || "Unknown error"));
          }
        } catch (err) {
          alert("OAuth error: " + err.message);
        }
      }
    }

    async function ensureLoggedIn() {
      if (!localStorage.getItem("id_token")) {
        const loginUrl = COGNITO_DOMAIN + "/login?response_type=code&client_id=" + CLIENT_ID + "&redirect_uri=" + encodeURIComponent(REDIRECT_URI);
        const lastRedirect = sessionStorage.getItem("last_redirect");

        if (!lastRedirect || Date.now() - parseInt(lastRedirect) > 10000) {
          sessionStorage.setItem("last_redirect", Date.now().toString());
          window.location.href = loginUrl;
        }
      } else {
        document.getElementById("logoutBtn").style.display = "inline-block";
      }
    }

    document.getElementById("logoutBtn").onclick = function () {
      localStorage.removeItem("id_token");
      window.location.href = COGNITO_DOMAIN + "/logout?client_id=" + CLIENT_ID + "&logout_uri=" + encodeURIComponent(REDIRECT_URI);
    };

    // MAIN LOGIN FLOW
    (async function () {
      await handleCognitoLoginRedirect();
      await ensureLoggedIn();
    })();

    // Upload logic
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
      const token = localStorage.getItem("id_token"); // ✅ API Gateway expects id_token

      if (!files.length) return alert("Please choose one or more files.");
      if (!token) return alert("You're not logged in.");

      urlDisplay.innerHTML = "";

      for (const file of files) {
        const status = document.createElement("p");
        status.textContent = "Uploading " + file.name + "...";
        urlDisplay.appendChild(status);

        try {
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
            status.textContent = "❌ Failed to get upload URL for " + file.name;
            status.classList.add("error");
            continue;
          }

          const data = await response.json();
          const upload_url = data.upload_url;

          const uploadRes = await fetch(upload_url, {
            method: 'PUT',
            body: file
          });

          if (uploadRes.ok) {
            const cleanUrl = upload_url.split("?")[0];
            status.innerHTML = "✅ <strong>" + file.name + ":</strong> <a href=\"" + cleanUrl + "\" target=\"_blank\">" + cleanUrl + "</a>";
            status.classList.add("success");
          } else {
            status.textContent = "❌ Upload failed for " + file.name;
            status.classList.add("error");
          }
        } catch (err) {
          status.textContent = "❌ Error uploading " + file.name + ": " + err.message;
          status.classList.add("error");
        }
      }
    });
  </script>
</body>
</html>
