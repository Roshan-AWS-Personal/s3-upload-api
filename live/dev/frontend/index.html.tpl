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
    progress { width: 100%; height: 1rem; margin-top: 0.5rem; }
    .file-box { margin-bottom: 1.5rem; }
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
        const fileBox = document.createElement("div");
        fileBox.className = "file-box";

        const status = document.createElement("p");
        status.textContent = "Uploading " + file.name + "...";

        const progress = document.createElement("progress");
        progress.value = 0;
        progress.max = 100;

        fileBox.appendChild(status);
        fileBox.appendChild(progress);
        urlDisplay.appendChild(fileBox);

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

          // Use XMLHttpRequest to track upload progress
          await new Promise((resolve, reject) => {
            const xhr = new XMLHttpRequest();
            xhr.open("PUT", upload_url, true);
            xhr.upload.onprogress = (e) => {
              if (e.lengthComputable) {
                progress.value = (e.loaded / e.total) * 100;
              }
            };
            xhr.onload = () => {
              if (xhr.status >= 200 && xhr.status < 300) {
                const cleanUrl = upload_url.split("?")[0];
                status.innerHTML = `✅ <strong>${file.name}:</strong> <a href="${cleanUrl}" target="_blank">${cleanUrl}</a>`;
                status.classList.add("success");
                resolve();
              } else {
                status.textContent = `❌ Upload failed for ${file.name}`;
                status.classList.add("error");
                reject();
              }
            };
            xhr.onerror = () => {
              status.textContent = `❌ Network error uploading ${file.name}`;
              status.classList.add("error");
              reject();
            };
            xhr.send(file);
          });

        } catch (err) {
          status.textContent = "❌ Error uploading " + file.name + ": " + err.message;
          status.classList.add("error");
        }
      }
    });
  </script>
</body>
</html>
