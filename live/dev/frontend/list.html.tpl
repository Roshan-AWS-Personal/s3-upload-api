<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <title>Uploaded Files</title>
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <style>
    body { font-family: sans-serif; padding: 2em; }
    nav { margin-bottom: 2rem; }
    nav a { margin-right: 1rem; text-decoration: none; color: #0366d6; }
    nav a:hover { text-decoration: underline; }
    table { width: 100%; border-collapse: collapse; margin-top: 1em; }
    th, td { padding: 0.5em; border: 1px solid #ccc; }
    th { background: #f0f0f0; }
    .error { color: red; margin-top: 1em; }
  </style>
</head>
<body>

  <nav>
    <a href="index.html">Upload</a>
    <a href="list.html"><strong>View Files</strong></a>
  </nav>

  <h1>Uploaded Files</h1>
  <div id="loading">Loading...</div>
  <div id="error" class="error" style="display: none;"></div>
  <table id="uploadsTable" style="display: none;">
    <thead>
      <tr>
        <th>Filename</th>
        <th>Uploader</th>
        <th>Size (KB)</th>
        <th>Timestamp</th>
        <th>S3 Link</th>
      </tr>
    </thead>
    <tbody id="uploadsBody"></tbody>
  </table>

  <script>
    const API_URL = "${API_URL}";
    const COGNITO_DOMAIN = "${COGNITO_DOMAIN}";
    const CLIENT_ID = "${CLIENT_ID}";
    const REDIRECT_URI = "https://d3oxbj8znjk30z.cloudfront.net/list.html";

    const token = localStorage.getItem("access_token") || localStorage.getItem("id_token");

    if (!token) {
      const loginUrl = `${COGNITO_DOMAIN}/login?response_type=code&client_id=${CLIENT_ID}&redirect_uri=$${encodeURIComponent(REDIRECT_URI)}&scope=openid+email+profile`;
      window.location.href = loginUrl;
    } else {
      fetch(API_URL, {
        method: "GET",
        headers: {
          "Authorization": "Bearer " + token
        }
      })
      .then(res => {
        if (!res.ok) throw new Error("Auth failed or bad response");
        return res.json();
      })
      .then(data => {
        const uploads = data.uploads || [];

        document.getElementById("loading").style.display = "none";
        const table = document.getElementById("uploadsTable");
        const tbody = document.getElementById("uploadsBody");
        table.style.display = "table";

        uploads.forEach(item => {
          const row = document.createElement("tr");
          row.innerHTML =
            "<td>" + item.filename + "</td>" +
            "<td>" + (item.uploader || "-") + "</td>" +
            "<td>" + (item.size / 1024).toFixed(1) + "</td>" +
            "<td>" + new Date(item.timestamp).toLocaleString() + "</td>" +
            "<td><a href='" + item.s3_url + "' target='_blank'>View</a></td>";
          tbody.appendChild(row);
        });
      })
      .catch(err => {
        document.getElementById("loading").style.display = "none";
        const errorDiv = document.getElementById("error");
        errorDiv.style.display = "block";
        errorDiv.textContent = "Failed to load uploads: " + err.message;
        console.error(err);
      });
    }
  </script>
</body>
</html>
