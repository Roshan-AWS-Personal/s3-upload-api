<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>File Upload</title>
  <style>
    body { font-family: sans-serif; margin: 2rem; }
    .container { max-width: 600px; margin: auto; }
    nav { margin-bottom: 1rem; }
    nav a { margin-right: 1rem; text-decoration: none; color: #0366d6; }
    nav a:hover { text-decoration: underline; }
    #preview { display: block; margin-top: 1rem; max-width: 100%; }
    #urlDisplay { margin-top: 1rem; font-weight: bold; }
    .success { color: green; }
    .error { color: red; }
    #logoutBtn { margin-top: 1rem; display: none; }
  </style>
</head>
<body>
  <!-- Navigation -->
  <nav>
    <a href="index.html"><strong>Upload</strong></a>
    <a href="list.html">View Files</a>
  </nav>

  <div class="container">
    <h2>Upload Files</h2>
    <button id="logoutBtn">Logout</button>
    <form id="uploadForm">
      <input type="file" id="fileInput" multiple />
      <button type="submit">Upload</button>
    </form>
    <div id="status"></div>
  </div>

  <script>
    /* Terraform-injected values: DO NOT ESCAPE THESE */
    const API_URL = "${API_URL}";
    const COGNITO_DOMAIN = "${COGNITO_DOMAIN}";
    const CLIENT_ID = "${CLIENT_ID}";
    const REDIRECT_URI = "${REDIRECT_URI}";

    const token = localStorage.getItem("id_token");

    if (!token) {
      const loginUrl = `${COGNITO_DOMAIN}/login?response_type=token&client_id=$${CLIENT_ID}&redirect_uri=$${encodeURIComponent(REDIRECT_URI)}&scope=openid+email+profile`;
      window.location.href = loginUrl;
    }

    document.getElementById("uploadForm").addEventListener("submit", async (e) => {
      e.preventDefault();
      const fileInput = document.getElementById("fileInput");
      if (!fileInput.files.length) return;

      const file = fileInput.files[0];
      document.getElementById("status").textContent = "Requesting upload URL...";

      try {
        const presignRes = await fetch(API_URL, {
          method: "POST",
          headers: {
            "Authorization": "Bearer " + token,
            "Content-Type": "application/json"
          },
          body: JSON.stringify({ filename: file.name, type: file.type })
        });

        if (presignRes.status === 401) {
          localStorage.removeItem("id_token");
          const loginUrl = `${COGNITO_DOMAIN}/login?response_type=token&client_id=$${CLIENT_ID}&redirect_uri=$${encodeURIComponent(REDIRECT_URI)}&scope=openid+email+profile`;
          window.location.href = loginUrl;
          return;
        }

        if (!presignRes.ok) throw new Error("Failed to get upload URL");

        const { upload_url, file_url } = await presignRes.json();

        document.getElementById("status").textContent = "Uploading file...";

        const uploadRes = await fetch(upload_url, {
          method: "PUT",
          body: file
        });

        if (!uploadRes.ok) throw new Error("Upload failed");

        document.getElementById("status").innerHTML =
          `<span class="success">Upload successful! <a href="$${file_url}" target="_blank">View file</a></span>`;
      } catch (err) {
        document.getElementById("status").innerHTML =
          `<span class="error">$${err.message}</span>`;
      }
    });

    document.getElementById("logoutBtn").addEventListener("click", () => {
      localStorage.removeItem("id_token");
      window.location.href = `${COGNITO_DOMAIN}/logout?client_id=$${CLIENT_ID}&logout_uri=$${encodeURIComponent(REDIRECT_URI)}`;
    });
  </script>
</body>
</html>
