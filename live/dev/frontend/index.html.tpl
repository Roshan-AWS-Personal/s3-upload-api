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
  <div class="container">
    <h2>Upload Files</h2>
    <form id="uploadForm">
      <input type="file" id="fileInput" multiple />
      <button type="submit">Upload</button>
    </form>
    <img id="preview" style="display: none;" />
    <div id="urlDisplay"></div>
  </div>

  <script>
    const BEARER_TOKEN = "__API_KEY__";
    const API_URL = "__API_URL__";

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
      if (!files.length) return alert("Please choose one or more files.");

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
              "Authorization": BEARER_TOKEN
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
