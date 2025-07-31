<!-- index.html -->
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>Upload Files</title>
  <style>
    body { font-family: sans-serif; margin: 2rem; }
    .container { max-width: 600px; margin: auto; }
    #preview { display: block; margin-top: 1rem; max-width: 100%; }
    #statusContainer { margin-top: 1rem; }
    .status { margin: 0.5em 0; }
    .success { color: green; }
    .error { color: red; }
  </style>
</head>
<body>
  <!-- Shared nav -->
  <script src="shared-header.js"></script>
  <script>injectHeader("index");</script>

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
    const API_URL = "${API_URL}";
    const COGNITO_DOMAIN = "${COGNITO_DOMAIN}";
    const CLIENT_ID = "${CLIENT_ID}";
    const REDIRECT_URI = "${REDIRECT_URI}"; // https://your-cloudfront-domain/

    const params = new URLSearchParams(window.location.search);
    if (params.has("code")) {
      const code = params.get("code");
      const state = params.get("state") || "index.html";

      fetch(`${COGNITO_DOMAIN}/oauth2/token`, {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: new URLSearchParams({
          grant_type: "authorization_code",
          client_id: CLIENT_ID,
          redirect_uri: REDIRECT_URI,
          code: code
        })
      })
        .then(res => res.json())
        .then(data => {
          if (data.id_token && data.access_token) {
            localStorage.setItem("id_token", data.id_token);
            localStorage.setItem("access_token", data.access_token);
            window.location.href = state;
          } else {
            console.error("Token error", data);
          }
        })
        .catch(err => console.error("Login error", err));
    }

    const token = localStorage.getItem("id_token");
    if (!token) {
      const loginUrl = `${COGNITO_DOMAIN}/login?response_type=code&client_id=${CLIENT_ID}&redirect_uri=${encodeURIComponent(REDIRECT_URI)}&scope=openid+email+profile&state=index.html`;
      window.location.href = loginUrl;
    }

    const fileInput = document.getElementById("fileInput");
    const preview = document.getElementById("preview");
    const uploadForm = document.getElementById("uploadForm");
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
      const files = fileInput.files;
      statusContainer.innerHTML = "";

      if (!files.length) {
        return showStatus("\u274C Please select one or more files to upload.", "error");
      }

      for (const file of files) {
        const status = createStatusBlock(`${file.name}: Uploading...`);
        try {
          const query = new URLSearchParams({
            filename: file.name,
            content_type: file.type,
            filesize: file.size.toString()
          });

          const presignRes = await fetch(`${API_URL}?${query.toString()}`, {
            method: "GET",
            headers: { Authorization: "Bearer " + token }
          });

          if (!presignRes.ok) {
            const errMsg = await presignRes.text();
            status.innerHTML = `\u274C ${file.name}: Failed to get upload URL<br><small>${errMsg}</small>`;
            status.classList.add("error");
            continue;
          }

          const { upload_url } = await presignRes.json();
          const uploadRes = await fetch(upload_url, {
            method: "PUT",
            body: file
          });

          if (uploadRes.ok) {
            const fileUrl = upload_url.split("?")[0];
            status.innerHTML = `\u2705 <strong>${file.name}</strong>: <a href="${fileUrl}" target="_blank">${fileUrl}</a>`;
            status.classList.add("success");
          } else {
            status.innerHTML = `\u274C ${file.name}: Upload failed (status ${uploadRes.status})`;
            status.classList.add("error");
          }
        } catch (err) {
          status.innerHTML = `\u274C ${file.name}: Error: ${err.message}`;
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

    function showStatus(message, type = "") {
      const div = document.createElement("div");
      div.className = `status ${type}`;
      div.innerHTML = message;
      statusContainer.appendChild(div);
    }
  </script>
</body>
</html>
