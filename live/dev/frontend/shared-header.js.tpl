function injectHeader(activePage) {
  const COGNITO_DOMAIN = "${COGNITO_DOMAIN}";
  const CLIENT_ID = "${CLIENT_ID}";
  const REDIRECT_URI = "${REDIRECT_URI}";

  const navHTML = `
    <nav style="margin-bottom: 1em;">
      <a href="index.html" style="margin-right: 1em; font-weight: ${activePage === 'index' ? 'bold' : 'normal'};">Upload</a>
      <a href="list.html" style="margin-right: 1em; font-weight: ${activePage === 'list' ? 'bold' : 'normal'};">Downloads</a>
      <button id="logoutBtn">Logout</button>
    </nav>
    <hr/>
  `;
  document.body.insertAdjacentHTML("afterbegin", navHTML);

  document.getElementById("logoutBtn").addEventListener("click", () => {
    localStorage.clear();
    const logoutUrl = `${COGNITO_DOMAIN}/logout?client_id=${CLIENT_ID}&logout_uri=${REDIRECT_URI}`;
    window.location.href = logoutUrl;
  });

  const urlParams = new URLSearchParams(window.location.search);
  const code = urlParams.get("code");
  const state = urlParams.get("state");

  if (code) {
    fetch(`https://${COGNITO_DOMAIN.replace(/^https?:\/\//, '')}/oauth2/token`, {
      method: "POST",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded"
      },
      body: new URLSearchParams({
        grant_type: "authorization_code",
        client_id: CLIENT_ID,
        code: code,
        redirect_uri: REDIRECT_URI
      })
    })
    .then(res => res.json())
    .then(data => {
      if (data.access_token) {
        localStorage.setItem("access_token", data.access_token);
        localStorage.setItem("id_token", data.id_token);
        localStorage.setItem("refresh_token", data.refresh_token);
        // Clean up query string and redirect to original state if provided
        const redirectTarget = state || window.location.pathname;
        window.location.href = redirectTarget;
      } else {
        console.error("Token response error:", data);
        alert("Login failed. Please try again.");
      }
    })
    .catch(err => {
      console.error("Token request failed:", err);
      alert("Login error occurred.");
    });
  }
}
