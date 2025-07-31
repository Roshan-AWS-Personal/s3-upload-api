<script>
  const API_URL = "${API_URL}";
  const COGNITO_DOMAIN = "${COGNITO_DOMAIN}";
  const CLIENT_ID = "${CLIENT_ID}";
  const REDIRECT_URI = "https://d3oxbj8znjk30z.cloudfront.net/list.html";

  async function exchangeCodeForToken(code) {
    const params = new URLSearchParams();
    params.append("grant_type", "authorization_code");
    params.append("client_id", CLIENT_ID);
    params.append("code", code);
    params.append("redirect_uri", REDIRECT_URI);

    const response = await fetch(COGNITO_DOMAIN + "/oauth2/token", {
      method: "POST",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded"
      },
      body: params
    });

    if (!response.ok) throw new Error("Token exchange failed");
    const data = await response.json();
    localStorage.setItem("access_token", data.access_token);

    // Optional: store id_token if you want
    // localStorage.setItem("id_token", data.id_token);

    // Remove code from URL
    window.history.replaceState({}, document.title, REDIRECT_URI);
  }

  async function init() {
    const urlParams = new URLSearchParams(window.location.search);
    const code = urlParams.get("code");

    if (code) {
      try {
        await exchangeCodeForToken(code);
      } catch (err) {
        document.getElementById("error").textContent = "Failed to login: " + err.message;
        return;
      }
    }

    const token = localStorage.getItem("access_token");
    if (!token) {
      const loginUrl = COGNITO_DOMAIN + "/login?response_type=code&client_id=" + CLIENT_ID + "&redirect_uri=" + encodeURIComponent(REDIRECT_URI) + "&scope=openid+email+profile";
      window.location.href = loginUrl;
      return;
    }

    fetch(API_URL, {
      method: "GET",
      headers: { "Authorization": "Bearer " + token }
    })
    .then(res => {
      if (!res.ok) throw new Error("Auth failed or bad response");
      return res.json();
    })
    .then(data => {
      document.getElementById("loading").style.display = "none";
      const table = document.getElementById("uploadsTable");
      const tbody = document.getElementById("uploadsBody");
      table.style.display = "table";

      data.forEach(item => {
        const row = document.createElement("tr");
        row.innerHTML =
          "<td>" + item.filename + "</td>" +
          "<td>" + (item.uploader || "-") + "</td>" +
          "<td>" + (item.size / 1024).toFixed(1) + "</td>" +
          "<td>" + new Date(item.timestamp).toLocaleString() + "</td>" +
          "<td><a href=\"" + item.s3_url + "\" target=\"_blank\">View</a></td>";
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

  init();
</script>
