<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>Image Upload</title>
  <style>
    body { font-family: sans-serif; margin: 2rem; }
    .container { max-width: 600px; margin: auto; }
    #preview { display: block; margin-top: 1rem; max-width: 100%; }
    #urlDisplay { margin-top: 1rem; font-weight: bold; }
  </style>
</head>
<body>
  <div class="container">
    <h2>Upload an Image</h2>
    <form id="uploadForm">
      <input type="file" name="file" id="fileInput" accept="image/*" required />
      <button type="submit">Upload</button>
    </form>
    <img id="preview" />
    <div id="urlDisplay"></div>
  </div>

  <script>
    const BEARER_TOKEN = "${BEARER_TOKEN}";

    const form = document.getElementById('uploadForm');
    const fileInput = document.getElementById('fileInput');
    const preview = document.getElementById('preview');
    const urlDisplay = document.getElementById('urlDisplay');

    fileInput.addEventListener('change', () => {
      const file = fileInput.files[0];
      if (file) {
        preview.src = URL.createObjectURL(file);
        preview.style.display = 'block';
      }
    });

    form.addEventListener('submit', async (e) => {
      e.preventDefault();
      const file = fileInput.files[0];
      if (!file) return alert("Please choose a file.");

      try {
        status.textContent = "Requesting upload URL...";
        const apiUrl = "https://n3bcr23wm1.execute-api.ap-southeast-2.amazonaws.com/dev/upload";
        const query = new URLSearchParams({
          filename: file.name,
          content_type: file.type
        });

        const response = await fetch(`${apiUrl}?${query.toString()}`, {
          method: 'GET',
          headers: {
              "Authorization": `Bearer ${BEARER_TOKEN}`
          }
        });

        if (!response.ok) {
          urlDisplay.textContent = "Failed to get upload URL.";
          return;
        }

        const data = await response.json();
        const uploadUrl = data.upload_url;

        await fetch(uploadUrl, {
          method: 'PUT',
          headers: {
            'Content-Type': file.type
          },
          body: file
        });

        urlDisplay.innerHTML = `<p><strong>Uploaded URL:</strong> <a href="${uploadUrl.split('?')[0]}" target="_blank">${uploadUrl.split('?')[0]}</a></p>`;
      } catch (err) {
        urlDisplay.textContent = `Error: ${err.message}`;
      }
    });
  </script>
</body>
</html>
