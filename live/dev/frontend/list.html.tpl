<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Uploaded Files</title>
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <style>
    body { font-family: sans-serif; padding: 2em; }
    table { width: 100%; border-collapse: collapse; margin-top: 1em; }
    th, td { padding: 0.5em; border: 1px solid #ccc; }
    th { background: #f0f0f0; }
  </style>
</head>
<body>
  <h1>Uploaded Files</h1>
  <div id="loading">Loading...</div>
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
    const API_URL = "${API_URL}"; // replace with actual
    const token = localStorage.getItem('access_token'); // assuming this is how you're storing it

    if (!token) {
      window.location.href = '/login.html'; // or your Cognito Hosted UI
    }

    fetch(API_URL, {
      method: 'GET',
      headers: {
        'Authorization': token
      }
    })
    .then(res => {
      if (!res.ok) throw new Error('Auth failed or bad response');
      return res.json();
    })
    .then(data => {
      document.getElementById('loading').style.display = 'none';
      const table = document.getElementById('uploadsTable');
      const tbody = document.getElementById('uploadsBody');
      table.style.display = 'table';

      data.forEach(item => {
        const row = document.createElement('tr');
        row.innerHTML = `
          <td>$${item.filename}</td>
          <td>$${item.uploader || '-'}</td>
          <td>$${(item.size / 1024).toFixed(1)}</td>
          <td>$${new Date(item.timestamp).toLocaleString()}</td>
          <td><a href="${item.s3_url}" target="_blank">View</a></td>
        `;
        tbody.appendChild(row);
      });
    })
    .catch(err => {
      document.getElementById('loading').textContent = 'Failed to load uploads.';
      console.error(err);
    });
  </script>
</body>
</html>
