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
  </style>
</head>
<body>
  <script src="shared-header.js"></script>
  <script>injectHeader("index");</script>

  <div class="container">
    <h2>Upload Files</h2>
    <form id="uploadForm">
      <input type="file" id="fileInput" multiple />
      <button type="submit">Upload</button>
    </form>
    <img id="preview" style="display: none;" alt="Image preview" />
    <div id="urlDisplay"></div>
  </div>

<script>
  const COGNITO_DOMAIN = "${COGNITO_DOMAIN}";
  const CLIENT_ID = "${CLIENT_ID}";
  const REDIRECT_URI = "${REDIRECT_URI}";

  async function handleCognitoLoginRedirect() {
    const params = new URLSearchParams(window.location.search);
    const code = params.get("code");

    if (code) {
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

        const tokenData = await tokenRes.json();
        if (tokenData.id_token) {
          localStorage.setItem("id_token", tokenData.id_token);
          window.history.replaceState({}, document.title, REDIRECT_URI);
        } else {
          alert("Login failed: No ID token returned.");
        }
      } catch (err) {
        alert("OAuth error: " + err.message);
      }
    }
  }

  async function ensureLoggedIn() {
    const token = localStorage.getItem("id_token");
    if (!token) {
      const loginUrl = `${COGNITO_DOMAIN}/login?response_type=code&client_id=${CLIENT_ID}&redirect_uri=${REDIRECT_URI}&scope=openid+email+profile`;
      window.location.href = loginUrl;
    }
  }

  // Run immediately before upload logic
  (async function () {
    await handleCognitoLoginRedirect();
    await ensureLoggedIn();
  })();
</script>
</body>
</html>
