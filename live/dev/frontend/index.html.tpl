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
    const API_URL = "$${API_URL}";
    const COGNITO_DOMAIN = "$${COGNITO_DOMAIN}";
    const CLIENT_ID = "$${CLIENT_ID}";
    const REDIRECT_URI = "$${REDIRECT_URI}";
    const LOGOUT_URI = "$${LOGOUT_URI}";

    const token = localStorage.getItem("id_token");
    if (!token) {
      const loginUrl = COGNITO_DOMAIN + "/login?response_type=code&client_id=" + CLIENT_ID +
        "&redirect_uri=" + encodeURIComponent(REDIRECT_URI) +
        "&scope=openid+email+profile";
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
        return showStatus("❌ Please select one or more files to upload.", "error");
      }

      for (const file of files) {
        const status = createStatusBlock(`$${file.name}: Uploading...`);
        try {
          const query = new URLSearchParams({
            filename: file.name,
            content_type: file.type,
            filesize: file.size.toString()
          });

          const presignRes = await fetch(`$${API_URL}?$${query.toString()}`, {
            method: "GET",
            headers: { Authorization: "Bearer " + token }
          });

          if (!presignRes.ok) {
            const errMsg = await presignRes.text();
            status.innerHTML = `❌ $${file.name}: Failed to get upload URL<br><small>$${errMsg}</small>`;
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
            status.innerHTML = `✅ <strong>$${file.name}</strong>: <a href="$${fileUrl}" target="_blank">$${fileUrl}</a>`;
            status.classList.add("success");
          } else {
            status.innerHTML = `❌ $${file.name}: Upload failed (status $${uploadRes.status})`;
            status.classList.add("error");
          }
        } catch (err) {
          status.innerHTML = `❌ $${file.name}: Error: $${err.message}`;
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
      div.className = "status " + type;
      div.innerHTML = message;
      statusContainer.appendChild(div);
    }
  </script>
</body>
</html>
