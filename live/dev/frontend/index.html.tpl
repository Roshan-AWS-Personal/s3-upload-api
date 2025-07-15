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
    const API_URL = "https://n3bcr23wm1.execute-api.ap-southeast-2.amazonaws.com/dev/upload";

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

          await uploadFileWithProgress(file, upload_url, progress, status);
        } catch (err) {
          status.textContent = "❌ Error uploading " + file.name + ": " + err.message;
          status.classList.add("error");
        }
      }
    });

    function uploadFileWithProgress(file, uploadUrl, progressElem, statusElem) {
      return new Promise((resolve, reject) => {
        const xhr = new XMLHttpRequest();
        xhr.open("PUT", uploadUrl, true);

        xhr.upload.onprogress = (event) => {
          if (event.lengthComputable) {
            const percent = (event.loaded / event.total) * 100;
            progressElem.value = percent;
          }
        };

        xhr.onload = () => {
          if (xhr.status === 200) {
            const cleanUrl = uploadUrl.split("?")[0];
            statusElem.innerHTML = `✅ <strong>${file.name}:</strong> <a href="${cleanUrl}" target="_blank">${cleanUrl}</a>`;
            statusElem.classList.add("success");
            resolve();
          } else {
            statusElem.textContent = "❌ Upload failed for " + file.name;
            statusElem.classList.add("error");
            reject(new Error("Upload failed"));
          }
        };

        xhr.onerror = () => {
          statusElem.textContent = "❌ Upload error for " + file.name;
          statusElem.classList.add("error");
          reject(new Error("XHR error"));
        };

        xhr.send(file);
      });
    }
  </script>
</body>
</html>
